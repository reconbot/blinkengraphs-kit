import Testing
import BlinkengraphsCore

@Test func bucketsSpanTheRangeEvenlyAndAggregateEachOne() {
    let results = (0..<60).map { ProbeResult(at: Double($0), rttMs: Double($0 % 10)) }
    let points = GraphBuckets.points(results, from: 0, to: 60, count: 6, aggregate: .p50)
    #expect(points.map(\.start) == [0, 10, 20, 30, 40, 50])
    // Each bucket holds 0…9; p50 rank ⌊500·9/1000⌋ = 4.
    #expect(points.allSatisfy { $0.value == 4 && $0.loss == 0 && $0.count == 10 })
}

@Test func lossCountsLostProbesAgainstAllInTheBucket() {
    let results = [ProbeResult(at: 0, rttMs: 10), ProbeResult(at: 1, rttMs: nil),
                   ProbeResult(at: 2, rttMs: nil), ProbeResult(at: 3, rttMs: 20)]
    let p = GraphBuckets.points(results, from: 0, to: 4, count: 1, aggregate: .max)[0]
    #expect(p.loss == 0.5)
    #expect(p.value == 20)
}

@Test func aBucketWithOnlyLossHasNoValueAndAnEmptyOneHasNoCount() {
    let results = [ProbeResult(at: 0, rttMs: nil)]
    let points = GraphBuckets.points(results, from: 0, to: 2, count: 2, aggregate: .p50)
    #expect(points[0].value == nil && points[0].loss == 1 && points[0].count == 1)
    #expect(points[1].value == nil && points[1].count == 0)
}

@Test func resultsOutsideTheRangeAreIgnored() {
    let results = [ProbeResult(at: -1, rttMs: 99), ProbeResult(at: 5, rttMs: 1), ProbeResult(at: 10, rttMs: 99)]
    let points = GraphBuckets.points(results, from: 0, to: 10, count: 1, aggregate: .max)
    #expect(points[0].value == 1)
}

@Test func linkHistoriesExposeTheirResultsPerLink() {
    let probe = Probe(target: "1.1.1.1", protocol: "icmp")
    let wifi = Link(interface: "en0", gateway: "192.168.1.1")
    var h = LinkHistories(ramSeconds: 900)
    h.record(probe, ProbeResult(at: 1, rttMs: 3), on: wifi)
    #expect(h.results(on: wifi)[probe] == [ProbeResult(at: 1, rttMs: 3)])
    #expect(h.results(on: Link(interface: "pdp_ip0", gateway: nil)).isEmpty)
}

@Test func alignedBucketsStayPutAsTimePasses() {
    // A bucket's edges are multiples of its width, so a refresh moves no sample to another bucket.
    let a = GraphBuckets.alignedRange(now: 1000.2, span: 60, count: 6)
    let b = GraphBuckets.alignedRange(now: 1009.9, span: 60, count: 6)
    #expect(a == b)
    #expect(a == 950...1010)
    #expect(GraphBuckets.alignedRange(now: 1010.0, span: 60, count: 6) == 960...1020)
}

@Test func niceCeilingOnlyStepsAtRoundNumbers() {
    #expect(GraphBuckets.niceCeiling(9) == 10)
    #expect(GraphBuckets.niceCeiling(21) == 25)
    #expect(GraphBuckets.niceCeiling(24.9) == 25)
    #expect(GraphBuckets.niceCeiling(61) == 75)
    #expect(GraphBuckets.niceCeiling(140) == 150)
    #expect(GraphBuckets.niceCeiling(1300) == 1500)
}

@Test func readoutP50IsTheProbeStatsMedian() {
    let results = [10.0, 30, 20, 40].enumerated().map { ProbeResult(at: Double($0.offset), rttMs: $0.element) }
    let stats = ProbeHistory(results: results, ramSeconds: 900).stats(windowSeconds: 30)
    // rtt_ms takes index ⌊n/2⌋ = 2 of [10, 20, 30, 40]; the graph rank would take index 1.
    #expect(Readout.value(results, stats: stats, aggregate: .p50, windowSeconds: 30) == 30)
}

@Test func readoutOtherAggregatesUseOnlyTheWindowsReplies() {
    let old = ProbeResult(at: 0, rttMs: 500)
    let recent = (100..<110).map { ProbeResult(at: Double($0), rttMs: Double($0 - 99)) } + [ProbeResult(at: 110, rttMs: nil)]
    let results = [old] + recent
    let stats = ProbeHistory(results: results, ramSeconds: 900).stats(windowSeconds: 30)
    #expect(Readout.value(results, stats: stats, aggregate: .max, windowSeconds: 30) == 10)
    #expect(Readout.value(results, stats: stats, aggregate: .p95, windowSeconds: 30) == 9)
    #expect(Readout.value(results, stats: stats, aggregate: .avg, windowSeconds: 30) == 5.5)
}
