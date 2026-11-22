import Testing
import BlinkengraphsCore

private let probe = Probe(target: "1.1.1.1", protocol: "icmp")
private let wifi = Link(interface: "en0", gateway: nil)

@Test func shortSpansReadRawSamplesInEpochBuckets() {
    let results = (0..<120).map { ProbeResult(at: Double($0), rttMs: $0 % 2 == 0 ? 10 : nil) }
    let line = HistoryLine.make(span: 60, now: 119, aggregate: .max, results: results, rollups: nil, probe: probe, link: wifi)
    #expect(line?.points.count == 61)
    #expect(line?.points.first?.start == 59 && line?.points.last?.start == 119)
    #expect(line?.summary == 10)
    #expect(line?.bucketWidth == 1)
}

@Test func storageServesBeforeTheHandoverAndRamAfter() {
    var rollups = Rollups(keepDays: 1, maxTimeoutMs: 1000)
    var ram: [ProbeResult] = []
    for at in stride(from: 0.0, to: 7200, by: 1) {
        let r = ProbeResult(at: at, rttMs: at < 3600 ? 99 : 5)
        _ = rollups.record(probe, r, on: wifi)
        if at > 7200 - 900 { ram.append(r) }
    }
    let line = HistoryLine.make(span: 7200, now: 7199, aggregate: .max, results: ram, rollups: rollups, probe: probe, link: wifi)
    #expect(line?.points.first?.value == 99)
    #expect(line?.points.last?.value == 5)
    #expect(line?.summary == 99)
}

@Test func nothingToShowIsNil() {
    #expect(HistoryLine.make(span: 60, now: 100, aggregate: .p50, results: [], rollups: nil, probe: probe, link: wifi) == nil)
}
