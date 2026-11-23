import Foundation

/// History records as bytes, for the app's files. One file is a sequence of records, each a tag
/// byte and a fixed or length-prefixed payload, little-endian. Keys and Links are defined once
/// per file, then named by number, so a result costs 9 bytes. A record cut short by a kill ends
/// the file: everything before it is read.
public enum HistoryCodec {
    enum Tag: UInt8 {
        case key = 1, link = 2, result = 3, pause = 4, mark = 5, route = 6, row = 7, paused = 8, written = 9
    }

    /// RTTs are whole milliseconds (spec rules/probe-stats.md); this one means lost.
    static let lost: UInt16 = .max

    /// Encodes records for one file; keeps the key and Link numbers it has defined there.
    public struct Writer: Sendable {
        private var keys: [HistoryKey: UInt16] = [:]
        private var links: [Link: UInt16] = [:]

        public init() {}

        public mutating func encode(_ records: [HistoryRecord]) -> Data {
            var out = Data()
            for r in records { encode(r, into: &out) }
            return out
        }

        private mutating func encode(_ r: HistoryRecord, into out: inout Data) {
            switch r {
            case .result(let key, let result):
                let id = keyID(key, &out)
                out.tag(.result); out.u16(id); out.u32(result.at)
                out.u16(result.rttMs.map { UInt16(min(max($0.rounded(), 0), Double(HistoryCodec.lost - 1))) } ?? HistoryCodec.lost)
            case .pause(let p):
                out.tag(.pause); out.f64(p.begin); out.f64(p.end)
            case .mark(let at):
                out.tag(.mark); out.u32(at)
            case .route(let at, let link):
                let id = link.map { linkID($0, &out) } ?? UInt16.max
                out.tag(.route); out.u32(at); out.u16(id)
            case .row(let level, let key, let m, let row):
                let id = keyID(key, &out)
                let sk = row.sketch.encoded
                out.tag(.row); out.u8(level); out.u16(id); out.u32(m); out.u32(row.n); out.u32(row.lost)
                out.f64(row.sum); out.f64(row.min); out.f64(row.max); out.u16(sk.count); out.append(contentsOf: sk)
            case .paused(let level, let m, let seconds):
                out.tag(.paused); out.u8(level); out.u32(m); out.f64(seconds)
            case .written(let level, let next):
                out.tag(.written); out.u8(level); out.u32(next)
            }
        }

        private mutating func keyID(_ key: HistoryKey, _ out: inout Data) -> UInt16 {
            if let id = keys[key] { return id }
            let id = UInt16(keys.count)
            keys[key] = id
            out.tag(.key); out.u16(id); out.json(key)
            return id
        }

        private mutating func linkID(_ link: Link, _ out: inout Data) -> UInt16 {
            if let id = links[link] { return id }
            let id = UInt16(links.count)
            links[link] = id
            out.tag(.link); out.u16(id); out.json(link)
            return id
        }
    }

    /// Every whole record in `data`, in order.
    public static func decode(_ data: Data) -> [HistoryRecord] {
        var r = Reader(bytes: [UInt8](data))
        var keys: [UInt16: HistoryKey] = [:], links: [UInt16: Link] = [:]
        var out: [HistoryRecord] = []
        while !r.atEnd {
            let start = r.i
            guard let record = r.next(keys: &keys, links: &links) else {
                // A torn tail, damaged bytes, or a tag this version doesn't know: stop.
                r.i = start
                break
            }
            if let record { out.append(record) }
        }
        return out
    }

    private struct Reader {
        var bytes: [UInt8]
        var i = 0
        var atEnd: Bool { i >= bytes.count }

        /// Nil when the record can't be read; `.some(nil)` for a definition, which yields no record.
        mutating func next(keys: inout [UInt16: HistoryKey], links: inout [UInt16: Link]) -> HistoryRecord?? {
            guard let raw = u8(), let tag = Tag(rawValue: raw) else { return nil }
            switch tag {
            case .key:
                guard let id = u16(), let key: HistoryKey = json() else { return nil }
                keys[id] = key
                return .some(nil)
            case .link:
                guard let id = u16(), let link: Link = json() else { return nil }
                links[id] = link
                return .some(nil)
            case .result:
                guard let id = u16(), let at = u32(), let rtt = u16(), let key = keys[id] else { return nil }
                return .result(key, RawResult(at: at, rttMs: rtt == HistoryCodec.lost ? nil : Double(rtt)))
            case .pause:
                // Only damaged bytes hold a non-finite time, and History turns times into Ints.
                guard let b = f64(), let e = f64(), b.isFinite, e.isFinite else { return nil }
                return .pause(Pause(begin: b, end: e))
            case .mark:
                guard let at = u32() else { return nil }
                return .mark(at: at)
            case .route:
                guard let at = u32(), let id = u16() else { return nil }
                return .route(at: at, link: id == .max ? nil : links[id])
            case .row:
                guard let level = u8(), let id = u16(), let m = u32(), let n = u32(), let lost = u32(),
                      let sum = f64(), let mn = f64(), let mx = f64(), let len = u16(), i + Int(len) <= bytes.count,
                      let key = keys[id] else { return nil }
                let sk = Array(bytes[i..<i + Int(len)])
                i += Int(len)
                guard let sketch = try? Sketch(encoded: sk) else { return nil }
                return .row(level: Int(level), key: key, m: m, row: Row(n: n, lost: lost, sum: sum, min: mn, max: mx, sketch: sketch))
            case .paused:
                guard let level = u8(), let m = u32(), let s = f64(), s.isFinite else { return nil }
                return .paused(level: Int(level), m: m, seconds: s)
            case .written:
                guard let level = u8(), let n = u32() else { return nil }
                return .written(level: Int(level), next: n)
            }
        }

        mutating func take(_ n: Int) -> ArraySlice<UInt8>? {
            guard i + n <= bytes.count else { return nil }
            defer { i += n }
            return bytes[i..<i + n]
        }
        mutating func uint(_ n: Int) -> UInt64? {
            guard let b = take(n) else { return nil }
            return b.reversed().reduce(0) { $0 << 8 | UInt64($1) }
        }
        mutating func u8() -> UInt8? { uint(1).map { UInt8($0) } }
        mutating func u16() -> UInt16? { uint(2).map { UInt16($0) } }
        mutating func u32() -> Int? { uint(4).map { Int($0) } }
        mutating func f64() -> Double? { uint(8).map { Double(bitPattern: $0) } }
        mutating func json<T: Decodable>() -> T? {
            guard let len = u16(), let b = take(Int(len)) else { return nil }
            return try? JSONDecoder().decode(T.self, from: Data(b))
        }
    }
}

private extension Data {
    mutating func tag(_ t: HistoryCodec.Tag) { append(t.rawValue) }
    mutating func le(_ v: UInt64, _ n: Int) { for k in 0..<n { append(UInt8(truncatingIfNeeded: v >> (8 * UInt64(k)))) } }
    mutating func u8(_ v: Int) { le(UInt64(v), 1) }
    mutating func u16(_ v: UInt16) { le(UInt64(v), 2) }
    mutating func u16(_ v: Int) { le(UInt64(v), 2) }
    mutating func u32(_ v: Int) { le(UInt64(UInt32(clamping: v)), 4) }
    mutating func f64(_ v: Double) { le(v.bitPattern, 8) }
    mutating func json<T: Encodable>(_ v: T) {
        let d = (try? JSONEncoder().encode(v)) ?? Data()
        u16(d.count)
        append(d)
    }
}
