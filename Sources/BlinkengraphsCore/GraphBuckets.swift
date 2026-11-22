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

    /// `count` buckets spanning `span` seconds, with edges on multiples of the bucket width and
    /// the last bucket holding `now`. Edges anchored to `now` would slide every refresh, moving
    /// samples between buckets and redrawing the whole line.
    public static func alignedRange(now: Double, span: Double, count: Int) -> ClosedRange<Double> {
        let width = span / Double(count)
        let end = ((now / width).rounded(.down) + 1) * width
        return (end - span)...end
    }

    /// The smallest of 1, 1.5, 2, 2.5, 5 or 7.5 times a power of ten that is at least `value`,
    /// so a graph's scale changes only when its data crosses a round number.
    public static func niceCeiling(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        var magnitude = 1.0
        while magnitude * 10 <= value { magnitude *= 10 }
        while magnitude > value { magnitude /= 10 }
        for step in [1, 1.5, 2, 2.5, 5, 7.5, 10] where step * magnitude >= value { return step * magnitude }
        return 10 * magnitude
    }
}

