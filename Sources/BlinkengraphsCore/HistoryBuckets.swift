// spec rules/history.md, "Graph buckets".

public enum HistoryBuckets {
    /// Up to 240 points: RAM buckets of `w = max(⌊span / 240⌋, 1)` seconds, storage buckets of
    /// whole minutes `W = ⌈w / 60⌉ × 60`.
    public static func widths(span: Double) -> (ram: Double, storage: Double) {
        let w = max((span / 240).rounded(.down), 1)
        return (w, (w / 60).rounded(.up) * 60)
    }

    /// A graph's points over `[now − span, now]`, oldest first, one per bucket that has results.
    /// Minutes before `writtenThrough` (`c`) come from storage, results from `c` on from RAM, so
    /// nothing is counted twice or missed. Buckets align to the Unix epoch; a point's time is
    /// its bucket's start.
    public static func points(span: Double, now: Double, aggregate: Aggregate, ram: [ProbeResult],
                              stored: [(m: Double, data: Minute)], writtenThrough c: Double) -> [GraphPoint] {
        let (w, W) = widths(span: span)
        let from = now - span
        var minutes: [Double: [Minute]] = [:]
        for (m, data) in stored where from <= m + 59 && m < c {
            minutes[(m / W).rounded(.down) * W, default: []].append(data)
        }
        var replies: [Double: [Double]] = [:], lost: [Double: Int] = [:]
        for r in ram where max(from, c) <= r.at && r.at <= now {
            let start = (r.at / w).rounded(.down) * w
            if let rtt = r.rttMs { replies[start, default: []].append(rtt) } else { lost[start, default: 0] += 1 }
        }
        var points = minutes.map { start, group in
            // Ascending minute order: the merged sum depends on it (graph-aggregate.md, "Merge").
            let m = Minute.merge(group)
            return GraphPoint(start: start, value: m.value(aggregate), loss: m.loss, count: m.n + m.lost)
        }
        for start in Set(replies.keys).union(lost.keys) {
            let values = replies[start] ?? [], n = values.count + (lost[start] ?? 0)
            points.append(GraphPoint(start: start, value: aggregate.value(ofSamples: values),
                                     loss: Double(lost[start] ?? 0) / Double(n), count: n))
        }
        return points.sorted { $0.start < $1.start }
    }
}
