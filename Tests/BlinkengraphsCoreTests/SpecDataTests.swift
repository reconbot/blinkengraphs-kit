import Testing
import BlinkengraphsCore

@Test func decodesDefaults() throws {
    let d = try Defaults.decode(Spec.file("defaults.json"))
    #expect(d.probeGroup.name == "Default")
    #expect(d.probeGroup.targets.map(\.target) == ["gateway", "1.1.1.1", "9.9.9.9", "2606:4700:4700::1111", "2620:fe::fe", "system-dns"])
    #expect(d.probeTimeoutMs(intervalMs: 1000) == 1000)
    #expect(d.hopTrace.reverseDns)
    #expect(d.appearance == .system)
    #expect(d.graphAggregate == .p95)
    #expect(d.readoutAggregate == .p95)
    #expect(d.history.rollupDays == 7)
    #expect(d.captivePortalURL == "http://cp.cloudflare.com/generate_204")
    #expect(d.publicAddress.dnsServer == "ns3.cloudflare.com" && d.publicAddress.refreshS == 300)
    #expect(d.probeGroup.probes.contains(Probe(target: "1.1.1.1", protocol: "tcp:443")))
}

@Test func lightPaletteSharesTheBasePaths() throws {
    let base = try Tokens.decode(Spec.file("tokens/blinkengraphs.tokens.json"))
    let light = try Tokens.decode(Spec.file("tokens/blinkengraphs.light.tokens.json"))
    for path in ["color.surface.background", "color.surface.text", "color.severity.crit", "color.loss"] {
        #expect(base.color(path) != nil && light.color(path) != nil && base.color(path) != light.color(path))
    }
}

@Test func decodesTokens() throws {
    let t = try Tokens.decode(Spec.file("tokens/blinkengraphs.tokens.json"))
    #expect(t.color("color.severity.crit") == RGB(hex: "#ff5a5a"))
    #expect(t.number("threshold.meter-warn").map { abs($0 - 0.6) < 1e-6 } == true)
}
