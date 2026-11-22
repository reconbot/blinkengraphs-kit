import Testing
import BlinkengraphsCore

private let gateway = Probe(target: "gateway", protocol: "icmp")
private let cell = Link(interface: "pdp_ip0", gateway: nil)
private let wifi = Link(interface: "en0", gateway: "192.168.1.1")

@Test func lossOnOneLinkDoesNotFollowToTheNext() {
    var h = LinkHistories(ramSeconds: 900)
    for t in 0..<10 { h.record(gateway, ProbeResult(at: Double(t), rttMs: nil), on: cell) }
    for t in 10..<20 { h.record(gateway, ProbeResult(at: Double(t), rttMs: 5), on: wifi) }
    #expect(h.stats(on: wifi, windowSeconds: 30)[gateway]?.loss == 0)
    #expect(h.stats(on: cell, windowSeconds: 30)[gateway]?.loss == 1)
}

@Test func returningToALinkRestoresItsHistory() {
    var h = LinkHistories(ramSeconds: 900)
    h.record(gateway, ProbeResult(at: 0, rttMs: 4), on: wifi)
    h.record(gateway, ProbeResult(at: 1, rttMs: nil), on: cell)
    h.record(gateway, ProbeResult(at: 2, rttMs: 6), on: wifi)
    // Both Wi-Fi replies, none of cellular's loss: the lower median of [4, 6].
    #expect(h.stats(on: wifi, windowSeconds: 30)[gateway]?.rttMs == 4)
    #expect(h.stats(on: wifi, windowSeconds: 30)[gateway]?.loss == 0)
    #expect(h.stats(on: wifi, windowSeconds: 30)[gateway]?.baselineMs == 4)
}

@Test func linksIdleLongerThanRamAreForgotten() {
    var h = LinkHistories(ramSeconds: 900)
    h.record(gateway, ProbeResult(at: 0, rttMs: 4), on: cell)
    h.record(gateway, ProbeResult(at: 1000, rttMs: 5), on: wifi)
    #expect(h.stats(on: cell, windowSeconds: 30).isEmpty)
}
