import Testing
import BlinkengraphsCore

private let probe = Probe(target: "1.1.1.1", protocol: "icmp")
private let wifi = Link(interface: "en0", gateway: nil)

@Test func shortSpansReadRawSamples() {
    let results = (0..<120).map { ProbeResult(at: Double($0), rttMs: $0 % 2 == 0 ? 10 : nil) }
    let line = HistoryLine.make(span: 60, buckets: 60, now: 119.5, aggregate: .max, ramSeconds: 900,
                                results: results, rollups: nil, probe: probe, link: wifi)
    #expect(line?.points.count == 61)
    #expect(line?.points.last?.start == 119)
    #expect(line?.summary == 10)
    #expect(line?.loss == 0.5)
}

@Test func longSpansReadRollups() {
    var rollups = Rollups(keepDays: 1)
    for minute in 0..<120 { _ = rollups.record(probe, ProbeResult(at: Double(minute * 60), rttMs: Double(minute)), on: wifi) }
    let line = HistoryLine.make(span: 3600, buckets: 60, now: 7199, aggregate: .max, ramSeconds: 900,
                                results: nil, rollups: rollups, probe: probe, link: wifi)
    #expect(line?.points.count == 61)
    #expect(line?.points.last?.value == 119)
    #expect(line?.summary == 119)
    #expect(HistoryLine.make(span: 3600, buckets: 60, now: 7199, aggregate: .max, ramSeconds: 900,
                             results: nil, rollups: rollups, probe: probe, link: Link(interface: "x", gateway: nil)) == nil)
}

@Test func nothingToShowIsNil() {
    #expect(HistoryLine.make(span: 60, buckets: 60, now: 100, aggregate: .p50, ramSeconds: 900,
                             results: [], rollups: nil, probe: probe, link: wifi) == nil)
}
