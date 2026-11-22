// spec rules/history.md: Raw plus three Archives, and the Pauses between measurements.

/// What History keeps one series for: one Probe on one Link.
public struct HistoryKey: Hashable, Codable, Sendable {
    public var link: Link
    public var probe: Probe
    public init(link: Link, probe: Probe) { self.link = link; self.probe = probe }
}

/// One change to History, as storage keeps it: replaying every record restores the History.
public enum HistoryRecord: Equatable, Sendable {
    case result(HistoryKey, RawResult)
    case pause(Pause)
    /// Measuring at `at`, with nothing else to record: a kill's Pause begins after the newest record.
    case mark(at: Int)
    /// The Link carrying the default route from `at`; nil while there is no network path.
    case route(at: Int, link: Link?)
    case row(level: Int, key: HistoryKey, m: Int, row: Row)
    case paused(level: Int, m: Int, seconds: Double)
    /// Every step of `level` before `next` is written.
    case written(level: Int, next: Int)

    /// Whether it belongs with the Archives, kept as long as they are, rather than with Raw.
    public var isArchive: Bool {
        switch self {
        case .result, .mark, .route: false
        case .pause, .row, .paused, .written: true
        }
    }
}

/// Raw, Pauses and Archives for every key. Rows are written by `advance(now:)`, once each, and
/// never changed. Storage on disk is the app's; this is the model it saves and restores.
public struct History: Sendable {
    public struct Level: Sendable {
        public var step: Int
        public var rows: Int
        public init(step: Int, rows: Int) { self.step = step; self.rows = rows }
    }

    public let levels: [Level]
    public let rawSeconds: Int
    /// `g`: how long after its `at` a result can still arrive.
    public let g: Int

    public private(set) var raw: [HistoryKey: [RawResult]] = [:]
    public private(set) var pauses: [Pause] = []
    /// Per level, per key.
    public private(set) var archives: [[HistoryKey: Archive]]
    /// Per level: Paused seconds by step. Machine-wide, so not per key.
    public private(set) var paused: [[Int: Double]]
    /// Per level: the first step not yet written. Nil until anything is recorded.
    public private(set) var next: [Int?]
    /// When the default-route Link changed, for graph markers; nil Link while no path.
    public private(set) var routes: [(at: Int, link: Link?)] = []
    /// Records since the last `takeUnsaved()`, for storage.
    public private(set) var unsaved: [HistoryRecord] = []
    private var journaling = true
    private var newest: Int?

    public init(defaults: Defaults) {
        self.init(levels: defaults.history.archives.map { Level(step: $0.stepS, rows: $0.rows) },
                  rawSeconds: defaults.history.rawMinutes * 60,
                  g: (defaults.maxTimeoutMs + 999) / 1000 + 1)
    }

    public init(levels: [Level], rawSeconds: Int, g: Int) {
        self.levels = levels
        self.rawSeconds = rawSeconds
        self.g = g
        archives = levels.map { _ in [:] }
        paused = levels.map { _ in [:] }
        next = levels.map { _ in nil }
    }

    public var keys: some Collection<HistoryKey> { raw.keys }

    /// Every record kind counts: the kill Pause begins after the newest of them.
    public var newestAt: Int? {
        let p = pauses.last.map { Int($0.end.rounded(.down)) }
        return [newest, p].compactMap { $0 }.max()
    }

    public mutating func record(_ key: HistoryKey, _ result: RawResult) {
        raw[key, default: []].append(result)
        start(at: result.at)
        seen(result.at)
        log(.result(key, result))
    }

    public mutating func add(_ pause: Pause) {
        guard pause.end > pause.begin else { return }
        pauses.append(pause)
        pauses.sort { $0.begin < $1.begin }
        start(at: Int(pause.begin.rounded(.down)))
        log(.pause(pause))
    }

    /// Still measuring at `at`, though nothing else was recorded.
    public mutating func mark(at: Int) {
        seen(at)
        log(.mark(at: at))
    }

    /// The default-route Link changed at `at`.
    public mutating func route(at: Int, link: Link?) {
        guard routes.last.map({ $0.link != link }) ?? true else { return }
        routes.append((at, link))
        seen(at)
        log(.route(at: at, link: link))
    }

    /// The records since the last call, which storage then holds.
    public mutating func takeUnsaved() -> [HistoryRecord] {
        defer { unsaved = [] }
        return unsaved
    }

    /// Restores what storage held, in the order it was written. Nothing replayed is unsaved.
    public mutating func replay(_ records: [HistoryRecord]) {
        journaling = false
        defer { journaling = true }
        for r in records {
            switch r {
            case .result(let key, let result): record(key, result)
            case .pause(let p): add(p)
            case .mark(let at): mark(at: at)
            case .route(let at, let link): route(at: at, link: link)
            case .row(let level, let key, let m, let row):
                guard levels.indices.contains(level) else { continue }
                start(at: m)
                archives[level][key, default: Archive(step: levels[level].step)].set(m, row)
            case .paused(let level, let m, let seconds):
                guard levels.indices.contains(level) else { continue }
                paused[level][m] = seconds
            case .written(let level, let n):
                guard levels.indices.contains(level) else { continue }
                next[level] = max(next[level] ?? n, n)
            }
        }
    }

    /// Everything the Archives hold, as records: what storage rewrites when it compacts.
    public var archiveRecords: [HistoryRecord] {
        var out = pauses.map(HistoryRecord.pause)
        for (i, level) in archives.enumerated() {
            for (key, archive) in level {
                for m in archive.rows.keys.sorted() { out.append(.row(level: i, key: key, m: m, row: archive.rows[m]!)) }
            }
            for m in paused[i].keys.sorted() { out.append(.paused(level: i, m: m, seconds: paused[i][m]!)) }
            if let n = next[i] { out.append(.written(level: i, next: n)) }
        }
        return out
    }

    /// Raw records older than this are gone from Raw, and A1 has written them.
    public func rawCutoff(now: Int) -> Int {
        min(now - rawSeconds, (next.first.flatMap { $0 } ?? Int.min) - 1)
    }

    private mutating func seen(_ at: Int) { newest = max(newest ?? at, at) }

    private mutating func log(_ r: HistoryRecord) { if journaling { unsaved.append(r) } }

    /// Writes every Row and Paused second whose step has ended, lowest Archive first, then
    /// applies retention. Writing comes before pruning, so a long absence loses nothing that an
    /// Archive should still hold.
    public mutating func advance(now: Int) {
        for (i, level) in levels.enumerated() {
            guard let from = next[i] else { continue }
            let s = level.step
            let last = Archive.floor(now - g - s, s)
            guard last >= from else { continue }
            let to = last + s
            // Rows: one pass per key, grouping what falls in the steps now ending.
            if i == 0 {
                for (key, results) in raw {
                    var groups: [Int: [(at: Int, order: Int, rtt: Double?)]] = [:]
                    for (order, r) in results.enumerated() where r.at >= from && r.at < to {
                        groups[Archive.floor(r.at, s), default: []].append((r.at, order, r.rttMs))
                    }
                    for (m, values) in groups {
                        // By `at`, then arrival order: the order `sum` adds in.
                        let row = Row(values: values.sorted { ($0.at, $0.order) < ($1.at, $1.order) }.map(\.rtt))
                        archives[i][key, default: Archive(step: s)].set(m, row)
                        log(.row(level: i, key: key, m: m, row: row))
                    }
                }
            } else {
                for (key, lower) in archives[i - 1] {
                    var groups: [Int: [(m: Int, row: Row)]] = [:]
                    for (m, row) in lower.rows where m >= from && m < to {
                        groups[Archive.floor(m, s), default: []].append((m, row))
                    }
                    for (m, rows) in groups {
                        let row = Row.merge(rows.sorted { $0.m < $1.m }.map(\.row))
                        archives[i][key, default: Archive(step: s)].set(m, row)
                        log(.row(level: i, key: key, m: m, row: row))
                    }
                }
            }
            // Paused seconds: only steps this Archive still keeps. Each equals the sum of the
            // steps below it, since the steps nest; computed from the Pauses directly so steps
            // the lower Archive has already dropped still count.
            let keepFrom = max(from, Archive.floor(now - level.rows * s, s))
            for p in pauses where p.end > Double(keepFrom) && p.begin < Double(to) {
                var m = max(keepFrom, Archive.floor(Int(p.begin.rounded(.down)), s))
                while Double(m) < p.end && m < to {
                    if Archive.kept(m, step: s, rows: level.rows, now: now) {
                        let secs = Pause.seconds(in: pauses, from: Double(m), to: Double(m + s))
                        if secs > 0 {
                            paused[i][m] = secs
                            log(.paused(level: i, m: m, seconds: secs))
                        }
                    }
                    m += s
                }
            }
            next[i] = to
            log(.written(level: i, next: to))
        }
        prune(now: now)
    }

    private mutating func prune(now: Int) {
        for (i, level) in levels.enumerated() {
            for key in archives[i].keys { archives[i][key]!.retain(now: now, rows: level.rows) }
            paused[i] = paused[i].filter { Archive.kept($0.key, step: level.step, rows: level.rows, now: now) }
        }
        // Raw keeps `at > now − raw_s`, but never drops what A1 hasn't written yet.
        let cutoff = rawCutoff(now: now)
        if let keep = routes.lastIndex(where: { $0.at <= cutoff }), keep > 0 { routes.removeFirst(keep) }
        for key in raw.keys {
            let results = raw[key]!
            if let first = results.firstIndex(where: { $0.at > cutoff }) {
                if first > 0 { raw[key] = Array(results[first...]) }
            } else {
                raw[key] = nil
            }
        }
        // A Pause matters while Raw or any Archive still spans it.
        let oldest = levels.map { now - $0.rows * $0.step }.min() ?? now - rawSeconds
        pauses.removeAll { $0.end <= Double(min(oldest, now - rawSeconds)) }
    }

    /// Seeds a Row at `level` (0 is A1) before `advance` runs, as demo data does. `advance` then
    /// writes the Archives above from it, and the Paused seconds of its steps.
    public mutating func insert(_ row: Row, key: HistoryKey, level: Int, m: Int) {
        start(at: m)
        archives[level][key, default: Archive(step: levels[level].step)].set(m, row)
    }

    /// The first record starts every Archive's clock. Later ones never move it back: a written
    /// step is never written again.
    private mutating func start(at t: Int) {
        for (i, level) in levels.enumerated() where next[i] == nil {
            next[i] = Archive.floor(t, level.step)
        }
    }

    /// Raw results of `key` with `from < at ≤ to`, in arrival order.
    public func results(_ key: HistoryKey, after from: Int, through to: Int) -> [RawResult] {
        guard let all = raw[key] else { return [] }
        var lo = all.count
        while lo > 0 && all[lo - 1].at > from { lo -= 1 }
        return all[lo...].filter { $0.at <= to }
    }
}
