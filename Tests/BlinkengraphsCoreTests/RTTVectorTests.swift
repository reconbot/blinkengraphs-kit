import BlinkengraphsCore
import Testing

private struct WholeMs: Decodable {
    struct Case: Decodable { var measured_ms: Double; var rtt_ms: Double }
    var cases: [Case]
}

@Test func rttVectors() throws {
    for (name, file) in try Spec.vectors("rtt", as: WholeMs.self) {
        for c in file.cases {
            #expect(RTT.recorded(c.measured_ms) == c.rtt_ms, "\(name): \(c.measured_ms)")
        }
    }
}

@Test func probeAndHopResultsAreRecordedInWholeMilliseconds() throws {
    var m = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")))
    let link = Link(interface: "en0", gateway: nil)
    _ = m.setPath(link: link, up: true, viaVPN: false)
    let probe = Probe(target: "1.1.1.1", protocol: "icmp")
    #expect(m.record(probe, .reply(ms: 12.5), sentOn: link, at: 0)?.rttMs == 13)
    m.recordSweep([HopResult(ttl: 1, addr: "192.0.2.1", rttMs: 0.4, reached: true)], target: "1.1.1.1", sentOn: link)
    #expect(m.snapshot().hops["1.1.1.1"]?.first?.lastMs == 0)
}

@Test func displaysShowWholeMilliseconds() {
    #expect(RTT.display(0) == "< 1")
    #expect(RTT.display(0.49) == "< 1")
    #expect(RTT.display(0.5) == "1")
    #expect(RTT.display(1.25) == "1")
    #expect(RTT.display(12.5) == "13")
}
