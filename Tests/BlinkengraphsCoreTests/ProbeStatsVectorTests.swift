import Testing
import BlinkengraphsCore

struct ProbeStatsVector: Decodable {
    let ram_s: Double
    let results: [ProbeResult]
    let expected: ProbeStats
}

@Test func probeStatsVectors() throws {
    for (name, v) in try Spec.vectors("probe-stats", as: ProbeStatsVector.self) {
        let s = ProbeHistory(results: v.results, ramSeconds: v.ram_s).stats(windowSeconds: 30)
        #expect(close(s.loss, v.expected.loss), "\(name) loss")
        #expect(close(s.rttMs, v.expected.rttMs), "\(name) rtt_ms")
        #expect(close(s.baselineMs, v.expected.baselineMs), "\(name) baseline_ms")
        #expect(close(s.jitterMs, v.expected.jitterMs), "\(name) jitter_ms")
    }
}

@Test func historyDropsResultsOlderThanRam() {
    var h = ProbeHistory(ramSeconds: 10)
    h.record(ProbeResult(at: 0, rttMs: 5))
    h.record(ProbeResult(at: 20, rttMs: 7))
    #expect(h.results.count == 1)
}
