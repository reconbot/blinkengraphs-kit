// CONTEXT.md "Rollup", rules/graph-aggregate.md "Per-minute storage" and rules/history.md
// "Minutes": one Minute per Probe per minute, written once its minute can get no more results,
// kept `rollup_days`. Per Link, like the RAM History (ADR 0005).

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
    /// `g`: a result is stamped with its round's start and arrives up to a timeout later.
    public let graceSeconds: Double
    /// Written Minutes, by Link, Probe and minute index.
    private var written: [Link: [Probe: [Int: Minute]]] = [:]
    /// Minutes still collecting results, by minute index.
    private var pending: [Int: [Link: [Probe: Minute]]] = [:]
    /// `c`, in seconds: every minute before it is written, none from it on.
    public private(set) var writtenThrough: Double = 0
    private var newest = -Double.infinity

    public init(keepDays: Int, maxTimeoutMs: Int) {
        keepMinutes = keepDays * 24 * 60
        graceSeconds = Double((maxTimeoutMs + 999) / 1000 + 1)
    }

    /// Adds a result and returns the Minutes it lets be written, oldest first. A result for a
    /// minute already written is left out: a Minute is written once and never merged.
    public mutating func record(_ probe: Probe, _ result: ProbeResult, on link: Link) -> [StoredMinute] {
        let minute = Int((result.at / 60).rounded(.down))
        if Double(minute * 60) >= writtenThrough {
            pending[minute, default: [:]][link, default: [:]][probe, default: Minute()].record(result.rttMs)
        }
        // Every minute m with m + 60 + g ≤ at can get no more results.
        let through = ((result.at - graceSeconds) / 60).rounded(.down) * 60
        var out: [StoredMinute] = []
        if through > writtenThrough {
            writtenThrough = through
            out = take { Double($0 * 60) < through }
        }
        if result.at > newest {
            newest = result.at
            prune()
        }
        return out
    }

    /// At shutdown: writes every minute not yet written.
    public mutating func flush() -> [StoredMinute] {
        guard let last = pending.keys.max() else { return [] }
        writtenThrough = max(writtenThrough, Double((last + 1) * 60))
        return take { _ in true }
    }

    /// When measuring pauses but the app may resume (iOS backgrounding): writes the minutes that
    /// ended by `now`, which can get no more results once no round is running. The open minute
    /// stays pending, so a quick return doesn't split it into a written part and a RAM part.
    public mutating func flushEnded(at now: Double) -> [StoredMinute] {
        let through = (now / 60).rounded(.down) * 60
        guard through > writtenThrough else { return [] }
        writtenThrough = through
        return take { Double($0 * 60) < through }
    }

    /// A Minute read back from storage.
    public mutating func insert(_ stored: StoredMinute) {
        guard newest == -.infinity || stored.minute >= Int((newest / 60).rounded(.down)) - keepMinutes else { return }
        written[stored.link, default: [:]][stored.probe, default: [:]][stored.minute] = stored.data
        writtenThrough = max(writtenThrough, Double((stored.minute + 1) * 60))
        // Read back after recording began (a relaunch within the grace): the stored Minute
        // stands, and results collected for its minute or earlier are left out.
        for minute in pending.keys where Double(minute * 60) < writtenThrough { pending[minute] = nil }
    }

    /// Written Minutes for one key with `from ≤ m + 59` and `m < before`, as (m in seconds, Minute), oldest first.
    public func minutes(_ probe: Probe, on link: Link, from: Double, before: Double) -> [(m: Double, data: Minute)] {
        let held = written[link]?[probe] ?? [:]
        let first = Int(((from - 59) / 60).rounded(.up)), last = Int((before / 60).rounded(.up)) - 1
        guard first <= last else { return [] }
        let keys = last - first + 1 > held.count
            ? held.keys.filter { $0 >= first && $0 <= last }.sorted() : Array(first...last).filter { held[$0] != nil }
        return keys.map { (Double($0 * 60), held[$0]!) }
    }

    /// The oldest written minute, in seconds, for the "All" range.
    public var oldest: Double? {
        written.values.flatMap { $0.values.flatMap(\.keys) }.min().map { Double($0 * 60) }
    }

    private mutating func take(_ include: (Int) -> Bool) -> [StoredMinute] {
        var out: [StoredMinute] = []
        for minute in pending.keys.sorted() where include(minute) {
            for (link, probes) in pending.removeValue(forKey: minute) ?? [:] {
                for (probe, data) in probes {
                    written[link, default: [:]][probe, default: [:]][minute] = data
                    out.append(StoredMinute(link: link, probe: probe, minute: minute, data: data))
                }
            }
        }
        return out
    }

    /// Retention: Minutes with m < newest.at − rollup_days.
    private mutating func prune() {
        let oldest = Int(((newest / 60).rounded(.down))) - keepMinutes
        for (link, probes) in written {
            for (probe, held) in probes where held.keys.contains(where: { $0 < oldest }) {
                written[link]?[probe] = held.filter { $0.key >= oldest }
            }
        }
    }
}
