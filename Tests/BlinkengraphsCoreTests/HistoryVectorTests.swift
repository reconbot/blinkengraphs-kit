import Foundation
import Testing
import BlinkengraphsCore

// spec rules/history.md, vectors/history/*.json

private struct File<Case: Decodable>: Decodable { var cases: [Case] }

private func file<T: Decodable>(_ name: String, as: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Spec.file("vectors/history/\(name).json"))
}

private struct BitsJSON: Decodable { var bits: String }
private struct RowJSON: Decodable { var m: Int; var n: Int; var lost: Int; var sum: BitsJSON?; var min: BitsJSON?; var max: BitsJSON?; var sk: String }
private struct ValuesRow: Decodable { var m: Int; var values: [Double?] }
private struct PausedJSON: Decodable { var m: Int; var paused_s: Double }
private struct PauseJSON: Decodable { var begin: Double; var end: Double }
private struct ResultJSON: Decodable { var at: Int; var rtt_ms: Double? }
private struct PointJSON: Decodable { var at: Int; var loss: Double?; var provisional: Bool; var state: String; var value: BitsJSON? }

private func hex(_ d: Double) -> String { String(format: "%016llx", d.bitPattern) }
private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }

private extension PauseJSON { var pause: Pause { Pause(begin: begin, end: end) } }
private extension ResultJSON { var raw: RawResult { RawResult(at: at, rttMs: rtt_ms) } }

private func archive(_ rows: [ValuesRow]?, step: Int) -> Archive {
    var a = Archive(step: step)
    for r in rows ?? [] { a.set(r.m, Row(values: r.values)) }
    return a
}

private func paused(_ p: [PausedJSON]?) -> [Int: Double] {
    Dictionary(uniqueKeysWithValues: (p ?? []).map { ($0.m, $0.paused_s) })
}

private func matches(_ row: Row?, _ e: RowJSON) -> Bool {
    guard let row else { return false }
    return row.n == e.n && row.lost == e.lost && hex(row.sketch.encoded) == e.sk
        && (e.sum.map { hex(row.sum) == $0.bits } ?? true)
        && (e.min.map { hex(row.min) == $0.bits } ?? true)
        && (e.max.map { hex(row.max) == $0.bits } ?? true)
}

private func expectPoints(_ got: [GraphPoint], _ want: [PointJSON], _ name: String) {
    #expect(got.count == want.count, "\(name): \(got.count) points, want \(want.count)")
    for (p, e) in zip(got, want) {
        let same = p.at == e.at && p.state.rawValue == e.state && p.provisional == e.provisional
            && (p.value.map(hex) == e.value?.bits)
            && ((p.loss == nil && e.loss == nil) || (p.loss != nil && e.loss != nil && abs(p.loss! - e.loss!) < 1e-9))
        #expect(same, "\(name) at \(e.at): got \(p.state) \(p.value.map { "\($0)" } ?? "-") loss \(p.loss.map { "\($0)" } ?? "-") prov \(p.provisional)")
    }
}

private let g = 2  // max_timeout_ms 1000 in every vector
private let steps = [300, 3600, 86_400]

private func written(now: Int) -> @Sendable (Int, Int) -> Bool {
    { level, m in Archive.written(m, step: steps[level - 1], now: now, g: g) }
}

@Test func timingVectors() throws {
    struct Case: Decodable {
        struct Round: Decodable { var at: Double; var start: Double }
        var name: String; var start: Double; var interval_s: Double; var durations_s: [Double]; var expected: [Round]
    }
    for c in try file("timing", as: File<Case>.self).cases {
        var clock = RoundClock(start: c.start, interval: c.interval_s)
        for (i, duration) in c.durations_s.enumerated() {
            #expect(abs(clock.start - c.expected[i].start) < 1e-6 && clock.at == c.expected[i].at, "\(c.name) round \(i)")
            clock.finished(at: clock.start + duration)
        }
    }
}

@Test func roundsVectors() throws {
    struct Case: Decodable {
        struct Round: Decodable { var start: Double; var end: Double }
        var name: String; var pauses: [PauseJSON]; var rounds: [Round]; var expected: [Int]
    }
    for c in try file("rounds", as: File<Case>.self).cases {
        let recorded = c.rounds.filter { !Pause.cuts(start: $0.start, end: $0.end, c.pauses.map(\.pause)) }
            .map { Int($0.start.rounded(.down)) }
        #expect(recorded == c.expected, "\(c.name)")
    }
}

@Test func rawVectors() throws {
    struct Kill: Decodable { var name: String; var newest_at: Int; var launch: Double; var settle_s: Double; var expected: PauseJSON }
    struct Retention: Decodable { var name: String; var ats: [Int]; var now: Int; var raw_s: Int; var expected: [Int] }
    struct F: Decodable { var kill: [Kill]; var retention: [Retention] }
    let f = try file("raw", as: F.self)
    for k in f.kill {
        #expect(Pause.afterKill(newestAt: k.newest_at, launch: k.launch, settle: k.settle_s) == k.expected.pause, "\(k.name)")
    }
    let key = HistoryKey(link: Link(interface: "en0", gateway: nil), probe: Probe(target: "1.1.1.1", protocol: "icmp"))
    for r in f.retention {
        var h = History(levels: [.init(step: 300, rows: 288)], rawSeconds: r.raw_s, g: g)
        for at in r.ats { h.record(key, RawResult(at: at, rttMs: 1)) }
        h.advance(now: r.now)
        #expect(h.raw[key]?.map(\.at) == r.expected, "\(r.name)")
    }
}

@Test func rowsVectors() throws {
    struct Check: Decodable { var now: Int; var rows: [RowJSON]; var paused: [PausedJSON] }
    struct F: Decodable { var results: [ResultJSON]; var pauses: [PauseJSON]; var step_s: Int; var checks: [Check] }
    let f = try file("rows", as: F.self)
    let key = HistoryKey(link: Link(interface: "en0", gateway: nil), probe: Probe(target: "1.1.1.1", protocol: "icmp"))
    var h = History(levels: [.init(step: f.step_s, rows: 288)], rawSeconds: 7200, g: g)
    for r in f.results { h.record(key, r.raw) }
    for p in f.pauses { h.add(p.pause) }
    for c in f.checks {
        h.advance(now: c.now)
        let rows = h.archives[0][key]?.rows ?? [:]
        #expect(rows.keys.sorted() == c.rows.map(\.m), "rows written by \(c.now)")
        for e in c.rows { #expect(matches(rows[e.m], e), "row \(e.m) at \(c.now)") }
        #expect(h.paused[0].keys.sorted() == c.paused.map(\.m), "paused steps by \(c.now)")
        for e in c.paused { #expect(abs((h.paused[0][e.m] ?? -1) - e.paused_s) < 1e-9, "paused \(e.m) at \(c.now)") }
    }
}

@Test func archivesVectors() throws {
    struct Expected: Decodable { var a2: [RowJSON]; var a2_paused: [PausedJSON]; var a3: [RowJSON]; var a3_paused: [PausedJSON] }
    struct Retention: Decodable { var name: String; var ms: [Int]; var now: Int; var rows: Int; var step_s: Int; var expected: [Int] }
    struct F: Decodable { var a1: [ValuesRow]; var a1_paused: [PausedJSON]; var expected: Expected; var retention: [Retention] }
    let f = try file("archives", as: F.self)
    let a2 = archive(f.a1, step: 300).merged(into: 3600), a3 = a2.merged(into: 86_400)
    #expect(a2.rows.keys.sorted() == f.expected.a2.map(\.m))
    for e in f.expected.a2 { #expect(matches(a2.rows[e.m], e), "a2 \(e.m)") }
    #expect(a3.rows.keys.sorted() == f.expected.a3.map(\.m))
    for e in f.expected.a3 { #expect(matches(a3.rows[e.m], e), "a3 \(e.m)") }
    let p2 = Archive.mergedPaused(paused(f.a1_paused), into: 3600), p3 = Archive.mergedPaused(p2, into: 86_400)
    #expect(p2 == paused(f.expected.a2_paused))
    #expect(p3 == paused(f.expected.a3_paused))
    for r in f.retention {
        var a = Archive(step: r.step_s)
        for m in r.ms { a.set(m, Row(values: [1])) }
        a.retain(now: r.now, rows: r.rows)
        #expect(a.rows.keys.sorted() == r.expected, "\(r.name)")
    }
}

@Test func rangeVectors() throws {
    struct Range: Decodable { var range: String; var source: String; var span_s: Int?; var width_s: Int }
    struct F: Decodable { var ranges: [Range] }
    for r in try file("ranges", as: F.self).ranges {
        let range = GraphRange.allCases.first { $0.rawValue.lowercased() == r.range.lowercased() }
        #expect(range != nil, "\(r.range)")
        guard let range else { continue }
        #expect(range.span == r.span_s && range.width == r.width_s, "\(r.range)")
        #expect(["raw", "a1", "a2", "a3"][range.level] == r.source, "\(r.range) source")
    }
}

private func graphRange(_ id: String) -> GraphRange {
    GraphRange.allCases.first { $0.rawValue.lowercased() == id.lowercased() }!
}

@Test func graphRawVectors() throws {
    struct Case: Decodable { var name: String; var range: String; var now: Int; var results: [ResultJSON]; var pauses: [PauseJSON]; var expected: [PointJSON] }
    struct F: Decodable { var aggregate: Aggregate; var cases: [Case] }
    for name in ["graph-raw", "graph-raw-half-paused"] {
        let f = try file(name, as: F.self)
        for c in f.cases {
            let src = GraphSource(raw: c.results.map(\.raw), pauses: c.pauses.map(\.pause), archives: steps.map { Archive(step: $0) },
                                  paused: [[:], [:], [:]], g: g, written: written(now: c.now))
            expectPoints(Graph.points(graphRange(c.range), now: c.now, source: src, aggregate: f.aggregate), c.expected, c.name)
        }
    }
}

@Test func graphArchiveVectors() throws {
    struct Case: Decodable {
        var name: String; var range: String; var now: Int; var raw: [ResultJSON]; var pauses: [PauseJSON]
        var a1: [ValuesRow]?; var a1_paused: [PausedJSON]?; var a2: [ValuesRow]?; var a2_paused: [PausedJSON]?
        var expected: [PointJSON]
    }
    struct F: Decodable { var aggregate: Aggregate; var cases: [Case] }
    let f = try file("graph-archive", as: F.self)
    for c in f.cases {
        let src = GraphSource(raw: c.raw.map(\.raw), pauses: c.pauses.map(\.pause),
                              archives: [archive(c.a1, step: 300), archive(c.a2, step: 3600), Archive(step: 86_400)],
                              paused: [paused(c.a1_paused), paused(c.a2_paused), [:]], g: g, written: written(now: c.now))
        expectPoints(Graph.points(graphRange(c.range), now: c.now, source: src, aggregate: f.aggregate), c.expected, c.name)
    }
}

@Test func graphAllVector() throws {
    struct Expected: Decodable { var k: Int; var points: [PointJSON] }
    struct F: Decodable { var aggregate: Aggregate; var now: Int; var a3: [ValuesRow]; var a3_paused: [PausedJSON]; var expected: Expected }
    let f = try file("graph-all", as: F.self)
    let a3 = archive(f.a3, step: 86_400)
    #expect(GraphRange.allK(oldest: a3.rows.keys.min()!, now: f.now) == f.expected.k)
    let src = GraphSource(raw: [], pauses: [], archives: [Archive(step: 300), Archive(step: 3600), a3],
                          paused: [[:], [:], paused(f.a3_paused)], g: g, written: written(now: f.now))
    expectPoints(Graph.points(.all, now: f.now, source: src, aggregate: f.aggregate), f.expected.points, "all")
}

@Test func historyWritesEveryArchiveBeforePruningAfterALongAbsence() {
    // Measured for ten minutes, then away three days: every Archive still gets its Rows.
    let key = HistoryKey(link: Link(interface: "en0", gateway: nil), probe: Probe(target: "1.1.1.1", protocol: "icmp"))
    var h = History(levels: [.init(step: 300, rows: 288), .init(step: 3600, rows: 168), .init(step: 86_400, rows: 365)],
                    rawSeconds: 7200, g: g)
    let t0 = 1_800_000_000
    for s in 0..<600 { h.record(key, RawResult(at: t0 + s, rttMs: 10)) }
    h.add(Pause(begin: Double(t0 + 600), end: Double(t0 + 3 * 86_400)))
    h.advance(now: t0 + 3 * 86_400)
    #expect(h.raw[key] == nil)
    #expect(h.archives[0][key] == nil || h.archives[0][key]!.rows.isEmpty)
    #expect(h.archives[1][key]?.rows.values.map(\.n).reduce(0, +) == 600)
    #expect(h.archives[2][key]?.rows.values.map(\.n).reduce(0, +) == 600)
    // A1 keeps only its last 24 h of Paused seconds; the days below are wholly Paused.
    // A1 keeps 24 h of Paused seconds: 287 written steps, the current one still open.
    #expect(h.paused[0].count == 287)
    #expect(h.paused[2][t0 / 86_400 * 86_400 + 86_400] == 86_400)
}

@Test func aWrittenStepIsNeverWrittenAgain() {
    let key = HistoryKey(link: Link(interface: "en0", gateway: nil), probe: Probe(target: "1.1.1.1", protocol: "icmp"))
    var h = History(levels: [.init(step: 300, rows: 288)], rawSeconds: 7200, g: g)
    h.record(key, RawResult(at: 1_800_000_000, rttMs: 10))
    h.advance(now: 1_800_000_302)
    let first = h.archives[0][key]?.rows
    // A result for a written step, arriving too late, changes nothing.
    h.record(key, RawResult(at: 1_800_000_001, rttMs: 99))
    h.advance(now: 1_800_000_900)
    #expect(h.archives[0][key]?.rows[1_800_000_000] == first?[1_800_000_000])
}

@Test func seededA1RowsBuildEveryArchiveAndTheirGraphs() throws {
    // As demo data does: eight days of A1 Rows with nightly Pauses, then `advance`.
    let defaults = try Defaults.decode(Spec.file("defaults.json"))
    let key = HistoryKey(link: Link(interface: "en0", gateway: "192.168.1.1"), probe: Probe(target: "1.1.1.1", protocol: "icmp"))
    var h = History(defaults: defaults)
    let now = 1_800_000_000, last = now / 300 * 300 - 300, first = last - 8 * 86_400
    for m in stride(from: first, through: last, by: 300) where !(1...6).contains((m / 3600) % 24) {
        h.insert(Row(values: [10, 12, nil]), key: key, level: 0, m: m)
    }
    for day in stride(from: first / 86_400 * 86_400, through: last, by: 86_400) {
        h.add(Pause(begin: Double(day + 3600), end: Double(day + 7 * 3600)))
    }
    h.advance(now: now)
    let src = h.source(key)
    let day = Graph.points(.oneDay, now: now, source: src, aggregate: .max)
    let week = Graph.points(.sevenDays, now: now, source: src, aggregate: .max)
    let all = Graph.points(.all, now: now, source: src, aggregate: .max)
    #expect(day.contains { $0.state == .paused } && day.contains { $0.state == .value })
    #expect(week.filter { $0.state == .paused }.count >= 6 * 6)
    #expect(week.contains { $0.state == .value && $0.value == 12 && abs(($0.loss ?? 0) - 1.0 / 3) < 1e-9 })
    #expect(all.contains { $0.state == .value })
    #expect(Graph.summary(.sevenDays, now: now, source: src, aggregate: .max).value == 12)
}
