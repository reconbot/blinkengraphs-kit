import Testing
import BlinkengraphsCore

// rules/hop-trace.md, "Sweeping".
@Test func sweepsToMaxTtlUntilThePathLengthIsKnown() {
    var plan = HopSweepPlan(maxTtl: 30, fullSweepEveryS: 30)
    #expect(plan.ttls(at: 0, pathLength: nil) == 1...30)
    #expect(plan.ttls(at: 1, pathLength: nil) == 1...30)
}

@Test func stopsAtThePathLengthThenGoesFullEveryInterval() {
    var plan = HopSweepPlan(maxTtl: 30, fullSweepEveryS: 30)
    #expect(plan.ttls(at: 0, pathLength: nil) == 1...30)
    #expect(plan.ttls(at: 1, pathLength: 9) == 1...9)
    #expect(plan.ttls(at: 29, pathLength: 9) == 1...9)
    #expect(plan.ttls(at: 30, pathLength: 9) == 1...30)
    #expect(plan.ttls(at: 31, pathLength: 9) == 1...9)
}

@Test func fullSweepRecordedHighestTtlFirstKeepsThePathLength() {
    // Past the Target (TTL 3), every TTL is answered by the Target itself.
    var trace = HopTrace(hopWindow: 60)
    for ttl in (1...30).reversed() {
        let reached = ttl >= 3
        trace.record(HopResult(ttl: ttl, addr: reached ? "1.1.1.1" : "10.0.0.\(ttl)", rttMs: 1, reached: reached))
    }
    #expect(trace.pathLength == 3)
    #expect(trace.table.map(\.ttl) == [1, 2, 3])
}
