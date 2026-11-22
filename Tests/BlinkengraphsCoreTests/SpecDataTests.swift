import Testing
import BlinkengraphsCore

@Test func decodesDefaults() throws {
    let d = try Defaults.decode(Spec.file("defaults.json"))
    #expect(d.probeGroup.name == "Default")
    #expect(d.probeGroup.targets.map(\.target) == ["gateway", "1.1.1.1", "9.9.9.9", "system-dns"])
    #expect(d.probeTimeoutMs(intervalMs: 1000) == 1000)
    #expect(d.probeGroup.probes.contains(Probe(target: "1.1.1.1", protocol: "tcp:443")))
}

@Test func decodesTokens() throws {
    let t = try Tokens.decode(Spec.file("tokens/blinkengraphs.tokens.json"))
    #expect(t.color("color.severity.crit") == RGB(hex: "#ff5a5a"))
    #expect(t.number("threshold.meter-warn").map { abs($0 - 0.6) < 1e-6 } == true)
}
