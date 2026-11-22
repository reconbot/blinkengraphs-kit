// One history graph line for a span: its points (rules/history.md, "Graph buckets") and a summary
// for the legend.

public struct HistoryLine: Equatable, Sendable {
    /// One per bucket with results, oldest first. A gap between points is an empty bucket, and the
    /// line breaks there (rules/history.md, "Drawing").
    public var points: [GraphPoint]
    /// The RAM bucket width, for spotting gaps.
    public var bucketWidth: Double
    /// The aggregate over the whole span, for a legend.
    public var summary: Double?
    public var loss: Double

    /// Nil when the span holds nothing for this Probe.
    public static func make(span: Double, now: Double, aggregate: Aggregate, results: [ProbeResult]?,
                            rollups: Rollups?, probe: Probe, link: Link) -> HistoryLine? {
        let c = rollups?.writtenThrough ?? 0
        let stored = rollups?.minutes(probe, on: link, from: now - span, before: c) ?? []
        let ram = results ?? []
        let points = HistoryBuckets.points(span: span, now: now, aggregate: aggregate, ram: ram,
                                           stored: stored, writtenThrough: c)
        guard !points.isEmpty else { return nil }
        let recent = ram.filter { max(now - span, c) <= $0.at && $0.at <= now }
        // Raw samples rank exactly; once Minutes are involved everything goes through their histogram.
        var whole = Minute.merge(stored.map(\.data))
        let summary: Double?
        if stored.isEmpty {
            summary = aggregate.value(ofSamples: recent.compactMap(\.rttMs))
        } else {
            var tail = Minute()
            for r in recent { tail.record(r.rttMs) }
            whole = Minute.merge([whole, tail])
            summary = whole.value(aggregate)
        }
        let lost = stored.isEmpty ? recent.filter { $0.rttMs == nil }.count : whole.lost
        let total = stored.isEmpty ? recent.count : whole.n + whole.lost
        return HistoryLine(points: points, bucketWidth: HistoryBuckets.widths(span: span).ram, summary: summary,
                           loss: total == 0 ? 0 : Double(lost) / Double(total))
    }
}
