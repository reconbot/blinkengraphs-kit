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

/// One Probe's results, kept for `ramSeconds` behind the newest.
public struct ProbeHistory: Sendable {
    public private(set) var results: [ProbeResult] = []
    public let ramSeconds: Double

    public init(ramSeconds: Double) { self.ramSeconds = ramSeconds }

    public init(results: [ProbeResult], ramSeconds: Double) {
        self.ramSeconds = ramSeconds
        for r in results { record(r) }
    }

    public mutating func record(_ result: ProbeResult) {
        results.append(result)
        let newest = result.at
        if let firstKept = results.firstIndex(where: { $0.at + ramSeconds > newest }), firstKept > 0 {
            results.removeFirst(firstKept)
        }
    }

    public func stats(windowSeconds: Double) -> ProbeStats {
        guard let newest = results.last?.at else {
            return ProbeStats(loss: 0, rttMs: nil, baselineMs: nil, jitterMs: nil)
        }
        let window = results.filter { $0.at + windowSeconds > newest }
        let replies = window.compactMap(\.rttMs)
        let loss = window.isEmpty ? 0 : 1 - Double(replies.count) / Double(window.count)

        let sorted = replies.sorted()
        let rtt = sorted.isEmpty ? nil : sorted[sorted.count / 2]

        let all = results.compactMap(\.rttMs).sorted()
        let baseline = all.isEmpty ? nil : all[Int((Double(all.count - 1) * 0.1).rounded(.down))]

        let jitter: Double? = replies.count < 2 ? nil
            : zip(replies, replies.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(replies.count - 1)

        return ProbeStats(loss: loss, rttMs: rtt, baselineMs: baseline, jitterMs: jitter)
    }
}
