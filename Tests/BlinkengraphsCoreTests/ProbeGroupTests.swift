import Foundation
import Testing
import BlinkengraphsCore

@Test func targetsAreAddressesNamesOrTheSpecialOnes() {
    for valid in ["gateway", "system-dns", "1.1.1.1", "2606:4700:4700::1111", "example.com", "dns.quad9.net", "my-host.lan"] {
        #expect(Defaults.Target.isValid(valid), "\(valid)")
    }
    for invalid in ["", " ", "1.1.1", "exa mple.com", "-bad.com", "a..b", "http://example.com", String(repeating: "a", count: 64) + ".com"] {
        #expect(!Defaults.Target.isValid(invalid), "\(invalid)")
    }
}

@Test func aProbeGroupRoundTripsThroughJSON() throws {
    let d = try Defaults.decode(Spec.file("defaults.json"))
    var group = d.probeGroup
    group.targets.append(Defaults.Target(target: "example.com", icmp: true, dns: false, trace: true, tcp: 443, udp: nil))
    let back = try JSONDecoder().decode(Defaults.ProbeGroup.self, from: JSONEncoder().encode(group))
    #expect(back == group)
    #expect(back.probes.contains(Probe(target: "example.com", protocol: "tcp:443")))
}

@Test func onlyConfiguredProbesReachTheSnapshot() throws {
    let d = try Defaults.decode(Spec.file("defaults.json"))
    let removed = Probe(target: "9.9.9.9", protocol: "icmp"), kept = Probe(target: "1.1.1.1", protocol: "icmp")
    let wifi = Link(interface: "en0", gateway: nil)
    var m = Measurements(defaults: d)
    m.setPath(link: wifi, up: true, viaVPN: false)
    _ = m.record(removed, .lost, sentOn: wifi, at: 1)
    _ = m.record(kept, .reply(ms: 10), sentOn: wifi, at: 1)
    var group = d.probeGroup
    group.targets.removeAll { $0.target == "9.9.9.9" }
    m.setProbeGroup(group)
    #expect(m.snapshot().stats.keys.sorted { $0.target < $1.target } == [kept])
    #expect(m.snapshot().findings.first?.domain == .clear)
}
