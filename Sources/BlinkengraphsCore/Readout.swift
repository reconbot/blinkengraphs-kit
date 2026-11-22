// spec rules/probe-stats.md, "Readouts".

/// The one latency number a Probe's readout shows for its window.
public enum Readout {
    /// `rtt_ms` for p50, so the readout matches what the Verdict uses; otherwise the aggregate of
    /// the window's replies, ranked as for raw samples (rules/graph-aggregate.md). The window is
    /// measured back from now.
    public static func value(_ results: [ProbeResult], stats: ProbeStats, aggregate: Aggregate,
                             now: Double, windowSeconds: Double) -> Double? {
        guard aggregate != .p50 else { return stats.rttMs }
        return aggregate.value(ofSamples: results.filter { $0.at > now - windowSeconds && $0.at <= now }.compactMap(\.rttMs))
    }
}
