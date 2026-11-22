// spec rules/history.md, "Archives"; rules/graph-aggregate.md, "A Row".

/// One result as Raw keeps it: its Round's whole Unix second and its RTT, nil when lost.
public struct RawResult: Codable, Equatable, Sendable {
    public var at: Int
    public var rttMs: Double?
    public init(at: Int, rttMs: Double?) { self.at = at; self.rttMs = rttMs }
}

/// One Archive's Rows for one key, by step start `m`.
public struct Archive: Equatable, Sendable {
    public let step: Int
    public private(set) var rows: [Int: Row] = [:]

    public init(step: Int, rows: [Int: Row] = [:]) { self.step = step; self.rows = rows }

    /// Whether the step at `m` can get no more results by `now`, so its Row is written.
    public static func written(_ m: Int, step: Int, now: Int, g: Int) -> Bool { now >= m + step + g }

    /// Whether an Archive keeping `rows` steps still holds the step at `m`.
    public static func kept(_ m: Int, step: Int, rows: Int, now: Int) -> Bool { m + step > now - rows * step }

    /// The Row of `values` in `[m, m + step)`: by `at`, then arrival order, which `sum` adds in.
    public static func row(_ raw: [RawResult], from m: Int, width: Int) -> Row {
        Row(values: raw.enumerated()
            .filter { $0.element.at >= m && $0.element.at < m + width }
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element.rttMs))
    }

    public mutating func set(_ m: Int, _ row: Row) {
        if row.n + row.lost > 0 { rows[m] = row }
    }

    /// This Archive's Rows merged into steps of `step`, ascending, as the next Archive builds them.
    public func merged(into step: Int) -> Archive {
        var out = Archive(step: step)
        for m in rows.keys.sorted() {
            let start = Self.floor(m, step)
            out.rows[start] = Row.merge([out.rows[start] ?? Row(), rows[m]!])
        }
        return out
    }

    /// Drops Rows with `m + step ≤ now − rows × step`.
    public mutating func retain(now: Int, rows keep: Int) {
        rows = rows.filter { Self.kept($0.key, step: step, rows: keep, now: now) }
    }

    /// Paused seconds per step merged into steps of `step`: they add.
    public static func mergedPaused(_ paused: [Int: Double], into step: Int) -> [Int: Double] {
        var out: [Int: Double] = [:]
        for m in paused.keys.sorted() { out[floor(m, step), default: 0] += paused[m]! }
        return out
    }

    static func floor(_ t: Int, _ step: Int) -> Int { t >= 0 ? t / step * step : (t - step + 1) / step * step }
}
