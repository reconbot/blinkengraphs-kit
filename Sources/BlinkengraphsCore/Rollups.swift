// CONTEXT.md "Rollup" and rules/graph-aggregate.md, "Per-minute storage": the History older
// than the RAM History, one Minute per Probe per minute, kept `rollup_days`. Per Link, like
// the RAM History (ADR 0005).

/// One Probe's Minute on one Link, as stored on disk. `minute` counts minutes since 1970.
public struct StoredMinute: Codable, Equatable, Sendable {
    public var link: Link
    public var probe: Probe
    public var minute: Int
    public var data: Minute

    public init(link: Link, probe: Probe, minute: Int, data: Minute) {
        self.link = link; self.probe = probe; self.minute = minute; self.data = data
    }
}

public struct Rollups: Sendable {
    public let keepMinutes: Int
    private var minutes: [Link: [Probe: [Int: Minute]]] = [:]
    /// Each key's newest minute, still filling.
    private var open: [Link: [Probe: Int]] = [:]
    private var newest = Int.min

    public init(keepDays: Int) { keepMinutes = keepDays * 24 * 60 }

    /// Returns the minutes this result closed, ready to store. A minute is stored once, when it
    /// closes, so storing never counts a sample twice; a minute open when the app is killed is lost.
    public mutating func record(_ probe: Probe, _ result: ProbeResult, on link: Link) -> [StoredMinute] {
        let minute = Int((result.at / 60).rounded(.down))
        var closed: [StoredMinute] = []
        if let previous = open[link]?[probe], previous < minute,
           let data = minutes[link]?[probe]?[previous] {
            closed.append(StoredMinute(link: link, probe: probe, minute: previous, data: data))
        }
        open[link, default: [:]][probe] = minute
        minutes[link, default: [:]][probe, default: [:]][minute, default: Minute()].record(result.rttMs)
        if minute > newest {
            newest = minute
            prune()
        }
        return closed
    }

    /// A stored minute, merged with any already held for the same key.
    public mutating func insert(_ stored: StoredMinute) {
        guard newest == .min || stored.minute > newest - keepMinutes else { return }
        let existing = minutes[stored.link]?[stored.probe]?[stored.minute]
        minutes[stored.link, default: [:]][stored.probe, default: [:]][stored.minute] =
            existing.map { Minute.merge([stored.data, $0]) } ?? stored.data
    }

    /// `count` equal buckets over `[from, to)`, each merging the whole minutes that start in it.
    /// Bucket widths should be whole minutes.
    public func points(_ probe: Probe, on link: Link, from: Double, to: Double, count: Int,
                       aggregate: Aggregate) -> [GraphPoint] {
        guard count > 0, to > from else { return [] }
        let width = (to - from) / Double(count)
        let held = minutes[link]?[probe] ?? [:]
        return (0..<count).map { i in
            let start = from + Double(i) * width
            let m = merged(held, from: start, to: start + width)
            return GraphPoint(start: start, value: m.value(aggregate), loss: m.loss, count: m.n + m.lost)
        }
    }

    /// The aggregate and loss over `[from, to)`, for a legend.
    public func summary(_ probe: Probe, on link: Link, from: Double, to: Double,
                        aggregate: Aggregate) -> (value: Double?, loss: Double) {
        let m = merged(minutes[link]?[probe] ?? [:], from: from, to: to)
        return (m.value(aggregate), m.loss)
    }

    private func merged(_ held: [Int: Minute], from: Double, to: Double) -> Minute {
        let first = Int((from / 60).rounded(.up)), last = Int((to / 60).rounded(.up)) - 1
        guard first <= last else { return Minute() }
        // Ascending minutes: the merged sum depends on order (rules/graph-aggregate.md).
        if last - first + 1 > held.count {
            return Minute.merge(held.keys.filter { $0 >= first && $0 <= last }.sorted().map { held[$0]! })
        }
        return Minute.merge((first...last).compactMap { held[$0] })
    }

    private mutating func prune() {
        let oldest = newest - keepMinutes
        for (link, probes) in minutes {
            for (probe, held) in probes where held.keys.contains(where: { $0 <= oldest }) {
                minutes[link]?[probe] = held.filter { $0.key > oldest }
            }
        }
    }
}
