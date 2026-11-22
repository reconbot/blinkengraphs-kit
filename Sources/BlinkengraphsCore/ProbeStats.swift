// rules/probe-stats.md
import Foundation

/// One Probe result. `rttMs` is nil when no reply arrived before the timeout.
/// A `denied` Probe produces no result at all.
public struct ProbeResult: Codable, Equatable, Sendable {
    public var at: Double
    public var rttMs: Double?

    public init(at: Double, rttMs: Double?) { self.at = at; self.rttMs = rttMs }

    enum CodingKeys: String, CodingKey { case at, rttMs = "rtt_ms" }
}

public struct ProbeStats: Codable, Equatable, Sendable {
    public var loss: Double
    public var rttMs: Double?
    public var baselineMs: Double?
    public var jitterMs: Double?

    public init(loss: Double, rttMs: Double?, baselineMs: Double?, jitterMs: Double?) {
        self.loss = loss; self.rttMs = rttMs; self.baselineMs = baselineMs; self.jitterMs = jitterMs
    }

    enum CodingKeys: String, CodingKey {
        case loss, rttMs = "rtt_ms", baselineMs = "baseline_ms", jitterMs = "jitter_ms"
    }
}

extension ProbeStats {
    /// A Probe's stats at `now`: its window is the results with `at > now − window_s`, measured
    /// back from now so results from before a Pause age out. Nil when the window is empty.
    /// The baseline spans every RTT Raw keeps, `at > now − raw_s`.
    public static func of(_ results: [ProbeResult], now: Double, windowSeconds: Double, rawSeconds: Double) -> ProbeStats? {
        let window = results.filter { $0.at > now - windowSeconds && $0.at <= now }
        guard !window.isEmpty else { return nil }
        let replies = window.compactMap(\.rttMs)
        let loss = 1 - Double(replies.count) / Double(window.count)

        let sorted = replies.sorted()
        // One percentile rank everywhere: index ⌊(n − 1) × X / 100⌋, so the lower median.
        let rtt = sorted.isEmpty ? nil : sorted[(sorted.count - 1) / 2]

        let all = results.filter { $0.at > now - rawSeconds && $0.at <= now }.compactMap(\.rttMs).sorted()
        let baseline = all.isEmpty ? nil : all[(all.count - 1) * 10 / 100]

        let jitter: Double? = replies.count < 2 ? nil
            : zip(replies, replies.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(replies.count - 1)

        return ProbeStats(loss: loss, rttMs: rtt, baselineMs: baseline, jitterMs: jitter)
    }
}
