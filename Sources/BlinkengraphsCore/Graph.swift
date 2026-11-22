// spec rules/history.md, "Graph ranges" and "Drawing": each range draws from exactly one
// source, Raw or one Archive, plus a provisional edge. Closed points never change.

public enum GraphRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case oneMinute = "1m", fifteenMinutes = "15m", oneHour = "1h", oneDay = "24h", sevenDays = "7d", all = "All"
    public var id: Self { self }

    /// Nil for All, which runs from the oldest A3 Row to now.
    public var span: Int? {
        switch self {
        case .oneMinute: 60
        case .fifteenMinutes: 900
        case .oneHour: 3600
        case .oneDay: 86_400
        case .sevenDays: 604_800
        case .all: nil
        }
    }

    /// 0 is Raw; 1, 2 and 3 are A1, A2 and A3.
    public var level: Int {
        switch self {
        case .oneMinute, .fifteenMinutes, .oneHour: 0
        case .oneDay: 1
        case .sevenDays: 2
        case .all: 3
        }
    }

    /// The point width; All's is this times `k`.
    public var width: Int {
        switch self {
        case .oneMinute: 1
        case .fifteenMinutes: 3
        case .oneHour: 15
        case .oneDay: 300
        case .sevenDays: 3600
        case .all: 86_400
        }
    }

    /// All draws at most 240 points, each `k` days.
    public static func allK(oldest: Int, now: Int) -> Int {
        let rows = now / 86_400 - oldest / 86_400 + 1
        return max(1, (rows + 239) / 240)
    }
}

/// One graph bucket `[at, at + width)`.
public struct GraphPoint: Equatable, Sendable {
    public enum State: String, Sendable {
        case value
        /// Every result lost: a loss mark, not a line point.
        case lost
        /// More than half the bucket not measured.
        case paused
    }

    public var at: Int
    public var width: Int
    public var state: State
    /// The aggregate; only for `.value`.
    public var value: Double?
    /// Lost share; nil when Paused.
    public var loss: Double?
    /// Not finished yet, so it can still change.
    public var provisional: Bool

    public init(at: Int, width: Int, state: State, value: Double?, loss: Double?, provisional: Bool) {
        self.at = at; self.width = width; self.state = state; self.value = value; self.loss = loss
        self.provisional = provisional
    }
}

/// What one key's graph can draw from.
public struct GraphSource: Sendable {
    public var raw: [RawResult]
    public var pauses: [Pause]
    /// A1, A2 and A3 for this key.
    public var archives: [Archive]
    /// Paused seconds by step, per Archive.
    public var paused: [[Int: Double]]
    public var g: Int
    /// Whether the Archive at `level` (1-based) has written the step at `m`.
    public var written: @Sendable (_ level: Int, _ m: Int) -> Bool

    public init(raw: [RawResult], pauses: [Pause], archives: [Archive], paused: [[Int: Double]], g: Int,
                written: @escaping @Sendable (Int, Int) -> Bool) {
        self.raw = raw; self.pauses = pauses; self.archives = archives; self.paused = paused; self.g = g
        self.written = written
    }
}

public enum Graph {
    /// The points of `range` at `now`, ascending; buckets with no results and not Paused have none.
    public static func points(_ range: GraphRange, now: Int, source: GraphSource, aggregate: Aggregate) -> [GraphPoint] {
        buckets(range, now: now, source: source).compactMap { bucket in
            let (b, w, row, paused, values) = bucket
            let provisional = now < b + w + source.g
            if paused > Double(w) / 2 {
                return GraphPoint(at: b, width: w, state: .paused, value: nil, loss: nil, provisional: provisional)
            }
            guard row.n + row.lost > 0 else { return nil }
            let loss = Double(row.lost) / Double(row.n + row.lost)
            guard row.n > 0 else {
                return GraphPoint(at: b, width: w, state: .lost, value: nil, loss: loss, provisional: provisional)
            }
            // From Raw, values rank exactly; from an Archive, through the Row's histogram.
            let value = values.map { aggregate.value(ofSamples: $0) } ?? row.value(aggregate)
            return GraphPoint(at: b, width: w, state: .value, value: value, loss: loss, provisional: provisional)
        }
    }

    /// The span's aggregate and loss over the buckets that aren't Paused, for a legend.
    public static func summary(_ range: GraphRange, now: Int, source: GraphSource, aggregate: Aggregate) -> (value: Double?, loss: Double) {
        let kept = buckets(range, now: now, source: source).filter { $0.paused <= Double($0.w) / 2 }
        let row = Row.merge(kept.map(\.row))
        let loss = row.n + row.lost == 0 ? 0 : Double(row.lost) / Double(row.n + row.lost)
        let value = range.level == 0 ? aggregate.value(ofSamples: kept.flatMap { $0.values ?? [] }) : row.value(aggregate)
        return (value, loss)
    }

    private typealias Bucket = (b: Int, w: Int, row: Row, paused: Double, values: [Double]?)

    private static func buckets(_ range: GraphRange, now: Int, source: GraphSource) -> [Bucket] {
        let w: Int, from: Int
        if let span = range.span {
            (w, from) = (range.width, now - span)
        } else {
            guard let oldest = source.archives[2].rows.keys.min() else { return [] }
            (w, from) = (86_400 * GraphRange.allK(oldest: oldest, now: now), oldest)
        }
        var src = source
        // Stable, so equal `at`s keep arrival order; each bucket is then one binary search.
        src.raw = src.raw.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        var out: [Bucket] = []
        // The first bucket with b + w > from.
        var b = Archive.floor(from - w, w) + w
        while b <= now {
            if range.level == 0 {
                let values = rawValues(src, b, w)
                out.append((b, w, Row(values: values), Pause.seconds(in: src.pauses, from: Double(b), to: Double(b + w)),
                            values.compactMap { $0 }))
            } else {
                let (row, paused) = archiveBucket(src, range.level, b, w)
                out.append((b, w, row, paused, nil))
            }
            b += w
        }
        return out
    }

    /// `src.raw` is sorted by `at`, arrival order kept among equals.
    private static func rawValues(_ src: GraphSource, _ b: Int, _ w: Int) -> [Double?] {
        let raw = src.raw
        var lo = 0, hi = raw.count
        while lo < hi { let mid = (lo + hi) / 2; if raw[mid].at < b { lo = mid + 1 } else { hi = mid } }
        var out: [Double?] = []
        var i = lo
        while i < raw.count && raw[i].at < b + w { out.append(raw[i].rttMs); i += 1 }
        return out
    }

    private static func rawBucket(_ src: GraphSource, _ b: Int, _ w: Int) -> (Row, Double) {
        (Row(values: rawValues(src, b, w)), Pause.seconds(in: src.pauses, from: Double(b), to: Double(b + w)))
    }

    /// The merge of an Archive's steps in `[b, b + w)`. A step not yet written is built the way
    /// its Row will be, from the Archive below and, at the bottom, Raw.
    private static func archiveBucket(_ src: GraphSource, _ level: Int, _ b: Int, _ w: Int) -> (Row, Double) {
        let a = src.archives[level - 1]
        var rows: [Row] = [], paused = 0.0
        var m = b
        while m < b + w {
            if src.written(level, m) {
                rows.append(a.rows[m] ?? Row())
                paused += src.paused[level - 1][m] ?? 0
            } else {
                let (r, p) = level == 1 ? rawBucket(src, m, a.step) : archiveBucket(src, level - 1, m, a.step)
                rows.append(r)
                paused += p
            }
            m += a.step
        }
        return (Row.merge(rows), paused)
    }
}

extension History {
    /// The graph source for `key`, as of the last `advance`.
    public func source(_ key: HistoryKey) -> GraphSource {
        let next = self.next
        return GraphSource(raw: raw[key] ?? [], pauses: pauses,
                           archives: levels.indices.map { archives[$0][key] ?? Archive(step: levels[$0].step) },
                           paused: paused, g: g,
                           written: { level, m in next[level - 1].map { m < $0 } ?? false })
    }

    /// The oldest A3 Row of any key, for a shared All span.
    public var oldestDay: Int? { archives.last?.values.compactMap { $0.rows.keys.min() }.min() }
}
