// spec rules/probe-stats.md, "Readouts".

/// The one latency number a Probe's readout shows for its window.
public enum Readout {
    /// `rtt_ms` for p50, so the readout matches what the Verdict uses; otherwise the aggregate of
    /// the window's replies, ranked as for raw samples (rules/graph-aggregate.md).
    public static func value(_ results: [ProbeResult], stats: ProbeStats, aggregate: Aggregate,
                             windowSeconds: Double) -> Double? {
        guard aggregate != .p50 else { return stats.rttMs }
        guard let newest = results.last?.at else { return nil }
        return aggregate.value(ofSamples: results.filter { $0.at + windowSeconds > newest }.compactMap(\.rttMs))
    }
}
