import Testing
import BlinkengraphsCore

private let gateway = Probe(target: "gateway", protocol: "icmp")
private let cloudflare = Probe(target: "1.1.1.1", protocol: "icmp")
private let wifi = Link(interface: "en0", gateway: "192.168.1.1")
private let cell = Link(interface: "pdp_ip0", gateway: nil)
private let t0 = 1_800_000_000.0

/// Measuring since `t0`, settled by `t0 + 2`.
private func measurements(on link: Link = wifi) throws -> Measurements {
    var m = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")), settle: 2)
    m.setPath(link: link, up: true, viaVPN: false)
    m.resume(at: t0)
    return m
}

private func round(_ at: Double, on link: Link = wifi, _ outcomes: [(Probe, Measurements.Outcome)]) -> Measurements.Round {
    .init(start: at + 0.2, end: at + 0.6, link: link, outcomes: outcomes)
}

@Test func resultsBelongToTheLinkTheyWereSentOn() throws {
    var m = try measurements()
    m.setPath(link: cell, up: true, viaVPN: false)
    // Sent on Wi-Fi before the switch, answered after it.
    let r1 = m.commit(round(t0 + 3, on: wifi, [(cloudflare, .lost)]))
    #expect(r1)
    #expect(m.snapshot(now: t0 + 4).stats[cloudflare] == nil)
    m.setPath(link: wifi, up: true, viaVPN: false)
    #expect(m.snapshot(now: t0 + 4).stats[cloudflare]?.loss == 1)
}

@Test func deniedIsNotALossAndClearsOnReplyOrLinkChange() throws {
    var m = try measurements()
    m.commit(round(t0 + 3, [(gateway, .denied)]))
    #expect(m.snapshot(now: t0 + 4).denied == [gateway])
    #expect(m.snapshot(now: t0 + 4).stats[gateway] == nil)
    m.commit(round(t0 + 4, [(gateway, .reply(ms: 3))]))
    #expect(m.snapshot(now: t0 + 5).denied.isEmpty)
    m.commit(round(t0 + 5, [(gateway, .denied)]))
    let r2 = m.setPath(link: cell, up: true, viaVPN: false)
    #expect(r2)
    #expect(m.snapshot(now: t0 + 6).denied.isEmpty)
}

@Test func unreachableRecordsNothing() throws {
    var m = try measurements()
    m.commit(round(t0 + 3, [(cloudflare, .unreachable)]))
    #expect(m.snapshot(now: t0 + 4).stats.isEmpty)
}

@Test func aRoundCutByAPauseRecordsNothing() throws {
    var m = try measurements()
    // Started before the app left, ended after: nothing, not a loss.
    m.pause(at: t0 + 10.5)
    let r3 = m.commit(.init(start: t0 + 10.2, end: t0 + 11.2, link: wifi, outcomes: [(cloudflare, .lost)]))
    #expect(!r3)
    m.resume(at: t0 + 100)
    // Inside the settle time: still Paused.
    let r4 = m.commit(round(t0 + 101, [(cloudflare, .reply(ms: 9))]))
    #expect(!r4)
    let r5 = m.commit(round(t0 + 102, [(cloudflare, .reply(ms: 9))]))
    #expect(r5)
    #expect(m.history.pauses.last == Pause(begin: t0 + 10.5, end: t0 + 102))
}

@Test func afterAPauseTheVerdictSaysResumingUntilStatsArrive() throws {
    var m = try measurements()
    m.commit(round(t0 + 3, [(gateway, .reply(ms: 3)), (cloudflare, .reply(ms: 12))]))
    m.pause(at: t0 + 10)
    m.resume(at: t0 + 600)
    // Pre-pause results have aged out of the window: no stats, and no fault.
    let early = m.snapshot(now: t0 + 603)
    #expect(early.stats.isEmpty)
    #expect(early.findings == [Finding(domain: .paused, severity: .ok, headline: "Resuming measurements")])
    m.commit(round(t0 + 603, [(gateway, .reply(ms: 3)), (cloudflare, .reply(ms: 12))]))
    #expect(m.snapshot(now: t0 + 604).findings.first?.domain == .clear)
}

@Test func theFirstLaunchIsAPause() throws {
    let m = try measurements()
    #expect(m.history.pauses == [Pause(begin: t0, end: t0 + 2)])
    #expect(m.snapshot(now: t0 + 3).findings.first?.domain == .paused)
}

@Test func aKillLeavesAPauseFromTheNewestRecordToTheSettledLaunch() throws {
    var first = try measurements()
    first.commit(round(t0 + 37, [(cloudflare, .reply(ms: 9))]))
    var m = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")), settle: 2)
    m.restore(first.history, launch: t0 + 400.5)
    m.resume(at: t0 + 400.5)
    #expect(m.history.pauses.last == Pause(begin: t0 + 38, end: t0 + 402.5))
}

@Test func theVerdictSeesPathAndCaptivePortal() throws {
    var m = try measurements()
    m.commit(round(t0 + 3, [(gateway, .reply(ms: 3)), (cloudflare, .lost)]))
    m.setCaptivePortal(true, checkedOn: wifi)
    #expect(m.snapshot(now: t0 + 4).findings.first?.domain == .captivePortal)
    // A check from a Link we've left says nothing about this one.
    m.setPath(link: cell, up: true, viaVPN: false)
    m.setCaptivePortal(true, checkedOn: wifi)
    #expect(m.snapshot(now: t0 + 4).captivePortal == false)
    m.setPath(link: cell, up: false, viaVPN: false)
    #expect(m.snapshot(now: t0 + 4).findings.first?.domain == .offline)
}

@Test func publicAddressIsDroppedOnALinkChange() throws {
    var m = try measurements()
    m.setPublicAddress([.ipv4: PublicAddressReading(state: .none)], lookedUpOn: wifi)
    #expect(m.snapshot(now: t0).publicAddress.count == 1)
    m.setPath(link: cell, up: true, viaVPN: false)
    #expect(m.snapshot(now: t0).publicAddress.isEmpty)
    m.setPublicAddress([.ipv4: PublicAddressReading(state: .none)], lookedUpOn: wifi)
    #expect(m.snapshot(now: t0).publicAddress.isEmpty)
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
    #expect(m.snapshot(now: t0).hops["1.1.1.1"]?.map(\.ttl) == [1, 2, 3])
    m.setPath(link: cell, up: true, viaVPN: false)
    #expect(m.snapshot(now: t0).hops.isEmpty)
    m.setPath(link: wifi, up: true, viaVPN: false)
    #expect(m.snapshot(now: t0).hops["1.1.1.1"]?.count == 3)
}
