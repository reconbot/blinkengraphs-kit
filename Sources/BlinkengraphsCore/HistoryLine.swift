// One history graph line for a span: its points and a summary, from whichever History holds the
// span. Up to the RAM History's length it reads raw samples; longer, the Rollups
// (rules/graph-aggregate.md, "A graph bucket").

public struct HistoryLine: Equatable, Sendable {
    /// `buckets + 1` points: one more on the left, so a scrolling line runs to the edge.
    public var points: [GraphPoint]
    /// The aggregate over the whole span, for a legend.
    public var summary: Double?
    public var loss: Double

    /// Nil when the span holds nothing for this Probe. Bucket edges sit on multiples of the
    /// bucket width, so only the newest bucket changes as `now` advances.
    public static func make(span: Double, buckets: Int, now: Double, aggregate: Aggregate,
                            ramSeconds: Double, results: [ProbeResult]?,
                            rollups: Rollups?, probe: Probe, link: Link) -> HistoryLine? {
        let window = GraphBuckets.alignedRange(now: now, span: span, count: buckets)
        let width = span / Double(buckets)
        let from = window.lowerBound - width
        if span <= ramSeconds {
            guard let results, !results.isEmpty else { return nil }
            let inSpan = results.filter { $0.at > now - span }
            let replies = inSpan.compactMap(\.rttMs)
            return HistoryLine(
                points: GraphBuckets.points(results, from: from, to: window.upperBound, count: buckets + 1, aggregate: aggregate),
                summary: aggregate.value(ofSamples: replies),
                loss: inSpan.isEmpty ? 0 : 1 - Double(replies.count) / Double(inSpan.count))
        }
        guard let rollups else { return nil }
        let points = rollups.points(probe, on: link, from: from, to: window.upperBound, count: buckets + 1, aggregate: aggregate)
        guard points.contains(where: { $0.count > 0 }) else { return nil }
        // Whole minutes, so the summary holds still within a minute.
        let minuteEnd = ((now / 60).rounded(.down) + 1) * 60
        let summary = rollups.summary(probe, on: link, from: minuteEnd - span, to: minuteEnd, aggregate: aggregate)
        return HistoryLine(points: points, summary: summary.value, loss: summary.loss)
    }
}
