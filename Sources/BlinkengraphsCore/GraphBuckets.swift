// rules/graph-aggregate.md, "A graph bucket": raw samples from the recent RAM history.

/// One point of a history graph.
public struct GraphPoint: Equatable, Sendable {
    /// Start of the bucket, in the results' clock.
    public var start: Double
    /// The aggregate of the bucket's replies; nil when none arrived.
    public var value: Double?
    /// Lost Probes over all Probes in the bucket; 0 when the bucket is empty.
    public var loss: Double
    /// Probes in the bucket, replied or lost.
    public var count: Int

    public init(start: Double, value: Double?, loss: Double, count: Int) {
        self.start = start; self.value = value; self.loss = loss; self.count = count
    }
}

public enum GraphBuckets {
    /// `count` equal buckets over `[from, to)`. Empty buckets stay, so a graph can show the gap.
    public static func points(_ results: [ProbeResult], from: Double, to: Double, count: Int,
                              aggregate: Aggregate) -> [GraphPoint] {
        guard count > 0, to > from else { return [] }
        let width = (to - from) / Double(count)
        var replies = Array(repeating: [Double](), count: count)
        var lost = Array(repeating: 0, count: count)
        for r in results where r.at >= from && r.at < to {
            let i = min(Int((r.at - from) / width), count - 1)
            if let rtt = r.rttMs { replies[i].append(rtt) } else { lost[i] += 1 }
        }
        return (0..<count).map { i in
            let n = replies[i].count + lost[i]
            return GraphPoint(start: from + Double(i) * width,
                              value: aggregate.value(ofSamples: replies[i]),
                              loss: n == 0 ? 0 : Double(lost[i]) / Double(n), count: n)
        }
    }
}
