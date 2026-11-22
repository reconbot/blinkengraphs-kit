import Foundation
import Testing
import BlinkengraphsCore

private let targets: Set<String> = ["1.1.1.1", "2606:4700:4700::1111"]

@Test func redactionKeepsTargetsAndPrivateAddresses() {
    let r = Redactor(targets: targets)
    #expect(r.address("1.1.1.1") == "1.1.1.1")
    #expect(r.address("2606:4700:4700::1111") == "2606:4700:4700::1111")
    #expect(r.address("192.168.1.1") == "192.168.1.1")
    #expect(r.address("100.64.12.7") == "100.64.12.7") // carrier-grade NAT space
    #expect(r.address("fd00:976a:d5d3:38::4") == "fd00:976a:d5d3:38::4")
}

@Test func redactionMasksOtherPublicAddresses() {
    let r = Redactor(targets: targets)
    #expect(r.address("96.246.46.1") == "96.246.46.x")
    #expect(r.address("100.41.67.198") == "100.41.67.x") // public, just below 100.64/10
    #expect(r.address("2600:4041:78f9:4000::1") == "2600:4041::x")
}

@Test func redactionHidesNamesExceptTargets() {
    let r = Redactor(targets: targets)
    #expect(r.name("one.one.one.one", of: "1.1.1.1") == "one.one.one.one")
    #expect(r.name("unifi.rbrtr.net", of: "192.168.1.1") == nil)
}

private func input() -> ReportInput {
    ReportInput(
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
        header: ["app 0.1.0", "spec 1.4.0"],
        verdict: [Finding(domain: .clear, severity: .ok, headline: "All clear")],
        connection: [("Via", "Wi-Fi"), ("Gateway", "192.168.1.1")],
        probes: [
            Probe(target: "1.1.1.1", protocol: "icmp"): ProbeStats(loss: 0.04, rttMs: 15, baselineMs: 14, jitterMs: 1.25),
        ],
        denied: [Probe(target: "gateway", protocol: "icmp")],
        hops: ["1.1.1.1": [
            HopRow(ttl: 1, addr: "192.168.1.1", sent: 10, loss: 0, lastMs: 10, bestMs: 9, avgMs: 10, worstMs: 12),
            HopRow(ttl: 2, addr: "96.246.46.1", sent: 10, loss: 0.1, lastMs: 14, bestMs: 13, avgMs: 14, worstMs: 20),
            HopRow(ttl: 3, addr: nil, sent: 10, loss: 1, lastMs: nil, bestMs: nil, avgMs: nil, worstMs: nil),
        ]],
        names: ["192.168.1.1": "unifi.rbrtr.net", "96.246.46.1": "lo0-100.nycm.verizon-gni.net"],
        targets: targets
    )
}

@Test func reportHasEverySection() {
    let text = Report.text(input(), redact: false)
    for needle in ["Verdict", "Ok  Clear  All clear", "Connection", "Via", "Probes", "1.1.1.1 icmp",
                   "4%", "denied", "Hop Trace to 1.1.1.1", "unifi.rbrtr.net (192.168.1.1)", "lo0-100.nycm.verizon-gni.net"] {
        #expect(text.contains(needle), "missing \(needle)")
    }
}

@Test func redactedReportHidesIdentity() {
    let text = Report.text(input(), redact: true)
    #expect(!text.contains("rbrtr"))
    #expect(!text.contains("verizon-gni"))
    #expect(!text.contains("96.246.46.1"))
    #expect(text.contains("96.246.46.x"))
    #expect(text.contains("redacted"))
}

@Test func longHostnamesKeepColumnsApart() {
    var i = input()
    i.names["96.246.46.1"] = "lo0-100.nycmny-vfttp-369.verizon-gni.net"
    let line = Report.text(i, redact: false).split(separator: "\n").first { $0.contains("verizon-gni") }!
    #expect(line.contains("(96.246.46.1)  "), "\(line)")
}

@Test func noProbesSaysPaused() {
    var i = input()
    i.probes = [:]
    i.denied = []
    #expect(Report.text(i, redact: false).contains("paused: no network path"))
}
