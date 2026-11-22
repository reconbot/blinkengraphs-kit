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
