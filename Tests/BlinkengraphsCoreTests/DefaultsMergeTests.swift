import Foundation
import Testing
import BlinkengraphsCore

private func canonical(_ value: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
}

@Test func defaultsMergeVector() throws {
    let v = try JSONSerialization.jsonObject(with: Spec.file("vectors/defaults/merge.json")) as! [String: Any]
    let cases = v["cases"] as! [[String: Any]]
    #expect(!cases.isEmpty)
    for c in cases {
        let got = DefaultsMerge.merge(c["base"]!, c["override"]!)
        #expect(try canonical(got) == canonical(c["expected"]!), "\(c["name"]!)")
    }
}

@Test func decodesSharedDefaultsWithAnOverride() throws {
    let override = Data(#"{"probe_group": {"latency_ms": 2000}, "system_interval_ms": null}"#.utf8)
    let d = try Defaults.decode(Spec.file("defaults.json"), override: override)
    #expect(d.probeGroup.latencyMs == 2000)
    #expect(d.probeGroup.dnsMs == 1000)
}
