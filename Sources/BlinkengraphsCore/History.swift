// spec rules/history.md: Raw plus three Archives, and the Pauses between measurements.

/// What History keeps one series for: one Probe on one Link.
public struct HistoryKey: Hashable, Codable, Sendable {
    public var link: Link
    public var probe: Probe
    public init(link: Link, probe: Probe) { self.link = link; self.probe = probe }
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
        let r = raw.values.compactMap { $0.last?.at }.max()
        let p = pauses.last.map { Int($0.end.rounded(.down)) }
        return [r, p].compactMap { $0 }.max()
    }

    public mutating func record(_ key: HistoryKey, _ result: RawResult) {
        raw[key, default: []].append(result)
        start(at: result.at)
    }

    public mutating func add(_ pause: Pause) {
        guard pause.end > pause.begin else { return }
        pauses.append(pause)
        pauses.sort { $0.begin < $1.begin }
        start(at: Int(pause.begin.rounded(.down)))
    }

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
                    }
                }
            } else {
                for (key, lower) in archives[i - 1] {
                    var groups: [Int: [(m: Int, row: Row)]] = [:]
                    for (m, row) in lower.rows where m >= from && m < to {
                        groups[Archive.floor(m, s), default: []].append((m, row))
                    }
                    for (m, rows) in groups {
                        archives[i][key, default: Archive(step: s)].set(m, Row.merge(rows.sorted { $0.m < $1.m }.map(\.row)))
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
                        if secs > 0 { paused[i][m] = secs }
                    }
                    m += s
                }
            }
            next[i] = to
        }
        prune(now: now)
    }

    private mutating func prune(now: Int) {
        for (i, level) in levels.enumerated() {
            for key in archives[i].keys { archives[i][key]!.retain(now: now, rows: level.rows) }
            paused[i] = paused[i].filter { Archive.kept($0.key, step: level.step, rows: level.rows, now: now) }
        }
        // Raw keeps `at > now − raw_s`, but never drops what A1 hasn't written yet.
        let a1 = next.first.flatMap { $0 } ?? Int.min
        let cutoff = min(now - rawSeconds, a1 - 1)
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
