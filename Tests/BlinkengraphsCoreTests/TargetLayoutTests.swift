import Testing
import BlinkengraphsCore

private func group(_ targets: [Defaults.Target]) -> Defaults.ProbeGroup {
    Defaults.ProbeGroup(name: "Default", targets: targets, latencyMs: 1000, dnsMs: 1000, traceMs: 1000)
}
private func row(_ t: String, icmp: Bool = true, dns: Bool = false, trace: Bool = false, tcp: Int? = nil) -> Defaults.Target {
    Defaults.Target(target: t, icmp: icmp, dns: dns, trace: trace, tcp: tcp, udp: nil)
}

@Test func entriesFollowTheGroupWithNamesFamiliesAndProbeOrder() {
    let layout = TargetLayout(group([row("gateway"), row("1.1.1.1", dns: true, tcp: 443), row("2620:fe::fe"),
                                     row("example.com"), row("system-dns", icmp: false, dns: true)]))
    #expect(layout.entries.map(\.name) == ["Gateway", "1.1.1.1", "2620:fe::fe", "example.com", "System DNS"])
    #expect(layout.entries.map(\.family) == [nil, .ipv4, .ipv6, nil, nil])
    #expect(layout.entries[1].probes.map(\.protocol) == ["icmp", "tcp:443", "dns"])
    #expect(layout.entries.map(\.slot) == [0, 1, 2, 3, 4])
}

@Test func theChartedProbeIsICMPElseTCPAndNeverDNS() {
    let layout = TargetLayout(group([row("a.example", icmp: false, tcp: 443), row("system-dns", icmp: false, dns: true),
                                     row("9.9.9.9")]))
    #expect(layout.entries.map(\.charted?.protocol) == ["tcp:443", nil, "icmp"])
    #expect(layout.charted.map(\.target) == ["a.example", "9.9.9.9"])
}

@Test func tracedTargetsListIPv4FirstAndOnlyTraceableOnes() {
    let layout = TargetLayout(group([row("2606:4700:4700::1111", trace: true), row("gateway", trace: true),
                                     row("1.1.1.1", trace: true), row("example.com", trace: true)]))
    #expect(layout.traced.map(\.target) == ["1.1.1.1", "2606:4700:4700::1111", "example.com"])
}

@Test func addressesAreTheLiteralTargets() {
    let layout = TargetLayout(group([row("gateway"), row("1.1.1.1"), row("example.com"), row("2620:fe::fe")]))
    #expect(layout.addresses == ["1.1.1.1", "2620:fe::fe"])
    #expect(layout.targets == ["gateway", "1.1.1.1", "example.com", "2620:fe::fe"])
}
