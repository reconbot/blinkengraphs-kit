import Testing
import BlinkengraphsCore

private let gateway = Probe(target: "gateway", protocol: "icmp")
private let cloudflare = Probe(target: "1.1.1.1", protocol: "icmp")
private let wifi = Link(interface: "en0", gateway: "192.168.1.1")
private let cell = Link(interface: "pdp_ip0", gateway: nil)

private func measurements(on link: Link = wifi) throws -> Measurements {
    var m = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")))
    m.setPath(link: link, up: true, viaVPN: false)
    return m
}

@Test func resultsBelongToTheLinkTheyWereSentOn() throws {
    var m = try measurements()
    m.setPath(link: cell, up: true, viaVPN: false)
    // Sent on Wi-Fi before the switch, answered after it.
    let stored = m.record(cloudflare, .lost, sentOn: wifi, at: 1)
    #expect(stored != nil)
    #expect(m.snapshot().stats[cloudflare] == nil)
    m.setPath(link: wifi, up: true, viaVPN: false)
    #expect(m.snapshot().stats[cloudflare]?.loss == 1)
}

@Test func deniedIsNotALossAndClearsOnReplyOrLinkChange() throws {
    var m = try measurements()
    let deniedResult = m.record(gateway, .denied, sentOn: wifi, at: 1)
    #expect(deniedResult == nil)
    #expect(m.snapshot().denied == [gateway])
    #expect(m.snapshot().stats[gateway] == nil)
    _ = m.record(gateway, .reply(ms: 3), sentOn: wifi, at: 2)
    #expect(m.snapshot().denied.isEmpty)
    _ = m.record(gateway, .denied, sentOn: wifi, at: 3)
    let changed = m.setPath(link: cell, up: true, viaVPN: false)
    #expect(changed)
    #expect(m.snapshot().denied.isEmpty)
}

@Test func unreachableRecordsNothing() throws {
    var m = try measurements()
    let unreachable = m.record(cloudflare, .unreachable, sentOn: wifi, at: 1)
    #expect(unreachable == nil)
    #expect(m.snapshot().stats.isEmpty)
}

@Test func theVerdictSeesPathAndCaptivePortal() throws {
    var m = try measurements()
    _ = m.record(gateway, .reply(ms: 3), sentOn: wifi, at: 1)
    _ = m.record(cloudflare, .lost, sentOn: wifi, at: 1)
    m.setCaptivePortal(true, checkedOn: wifi)
    #expect(m.snapshot().findings.first?.domain == .captivePortal)
    // A check from a Link we've left says nothing about this one.
    m.setPath(link: cell, up: true, viaVPN: false)
    m.setCaptivePortal(true, checkedOn: wifi)
    #expect(m.snapshot().captivePortal == false)
    m.setPath(link: cell, up: false, viaVPN: false)
    #expect(m.snapshot().findings.first?.domain == .offline)
}

@Test func publicAddressIsDroppedOnALinkChange() throws {
    var m = try measurements()
    m.setPublicAddress([.ipv4: PublicAddressReading(state: .none)], lookedUpOn: wifi)
    #expect(m.snapshot().publicAddress.count == 1)
    m.setPath(link: cell, up: true, viaVPN: false)
    #expect(m.snapshot().publicAddress.isEmpty)
    m.setPublicAddress([.ipv4: PublicAddressReading(state: .none)], lookedUpOn: wifi)
    #expect(m.snapshot().publicAddress.isEmpty)
}

@Test func hopTracesArePerLinkAndRecordedInAnyOrder() throws {
    var m = try measurements()
    let ttls = m.sweepTTLs("1.1.1.1", at: 0)
    #expect(ttls.first == 1)
    // Arrival order: the Target answers at TTL 3, and again past it at TTL 5.
    m.recordSweep([HopResult(ttl: 1, addr: "192.168.1.1", rttMs: 2, reached: false),
                   HopResult(ttl: 3, addr: "1.1.1.1", rttMs: 12, reached: true),
                   HopResult(ttl: 5, addr: "1.1.1.1", rttMs: 12, reached: true),
                   HopResult(ttl: 2, addr: nil, rttMs: nil, reached: false)],
                  target: "1.1.1.1", sentOn: wifi)
    #expect(m.snapshot().hops["1.1.1.1"]?.map(\.ttl) == [1, 2, 3])
    m.setPath(link: cell, up: true, viaVPN: false)
    #expect(m.snapshot().hops.isEmpty)
    m.setPath(link: wifi, up: true, viaVPN: false)
    #expect(m.snapshot().hops["1.1.1.1"]?.count == 3)
}
