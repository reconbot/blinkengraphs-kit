import Testing
import BlinkengraphsCore

@Test func niceCeilingOnlyStepsAtRoundNumbers() {
    #expect(GraphScale.niceCeiling(9) == 10)
    #expect(GraphScale.niceCeiling(21) == 25)
    #expect(GraphScale.niceCeiling(24.9) == 25)
    #expect(GraphScale.niceCeiling(61) == 75)
    #expect(GraphScale.niceCeiling(140) == 150)
    #expect(GraphScale.niceCeiling(1300) == 1500)
}

@Test func readoutP50IsTheProbeStatsMedian() throws {
    let results = [10.0, 30, 20, 40].enumerated().map { ProbeResult(at: Double($0.offset), rttMs: $0.element) }
    let stats = try #require(ProbeStats.of(results, now: 3, windowSeconds: 30, rawSeconds: 7200))
    // One rank everywhere: index ⌊(n − 1) / 2⌋ = 1 of [10, 20, 30, 40].
    #expect(Readout.value(results, stats: stats, aggregate: .p50, now: 3, windowSeconds: 30) == 20)
}

@Test func readoutOtherAggregatesUseOnlyTheWindowMeasuredBackFromNow() throws {
    let old = ProbeResult(at: 0, rttMs: 500)
    let recent = (100..<110).map { ProbeResult(at: Double($0), rttMs: Double($0 - 99)) } + [ProbeResult(at: 110, rttMs: nil)]
    let results = [old] + recent
    let stats = try #require(ProbeStats.of(results, now: 110, windowSeconds: 30, rawSeconds: 7200))
    #expect(Readout.value(results, stats: stats, aggregate: .max, now: 110, windowSeconds: 30) == 10)
    #expect(Readout.value(results, stats: stats, aggregate: .p95, now: 110, windowSeconds: 30) == 9)
    #expect(Readout.value(results, stats: stats, aggregate: .avg, now: 110, windowSeconds: 30) == 5.5)
    // Twenty seconds on, half the window has aged out.
    #expect(Readout.value(results, stats: stats, aggregate: .max, now: 130, windowSeconds: 30) == 10)
    #expect(Readout.value(results, stats: stats, aggregate: .avg, now: 135, windowSeconds: 30) == 8.5)
}
