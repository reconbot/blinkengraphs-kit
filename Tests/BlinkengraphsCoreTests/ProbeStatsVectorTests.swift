import Testing
import BlinkengraphsCore

struct ProbeStatsVector: Decodable {
    let now: Double
    let raw_s: Double
    let window_s: Double?
    let results: [ProbeResult]
    let expected: ProbeStats?
}

@Test func probeStatsVectors() throws {
    for (name, v) in try Spec.vectors("probe-stats", as: ProbeStatsVector.self) {
        let s = ProbeStats.of(v.results, now: v.now, windowSeconds: v.window_s ?? 30, rawSeconds: v.raw_s)
        guard let e = v.expected else {
            #expect(s == nil, "\(name): an empty window has no stats")
            continue
        }
        #expect(close(s?.loss, e.loss), "\(name) loss")
        #expect(close(s?.rttMs, e.rttMs), "\(name) rtt_ms")
        #expect(close(s?.baselineMs, e.baselineMs), "\(name) baseline_ms")
        #expect(close(s?.jitterMs, e.jitterMs), "\(name) jitter_ms")
    }
}
