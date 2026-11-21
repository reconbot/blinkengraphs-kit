import Testing
import Foundation
import BlinkengraphsCore

struct CubeRootVector: Decodable {
    struct Point: Decodable { let max: Double; let value: Double; let normalized: Double }
    let points: [Point]
}

struct LatencyScaleVector: Decodable {
    struct Sample: Decodable { let rtt_ms: Double; let value: Double }
    struct Point: Decodable { let baseline_ms: Double?; let scale_ms: Double; let normalized: [Sample] }
    let points: [Point]
}

@Test func cubeRootVector() throws {
    let v = try JSONDecoder().decode(CubeRootVector.self, from: Spec.file("vectors/meters/cube-root.json"))
    for p in v.points {
        #expect(close(Meter.cubeRoot(p.value, max: p.max), p.normalized, within: 1e-6), "\(p.value)/\(p.max)")
    }
}

@Test func latencyScaleVector() throws {
    let v = try JSONDecoder().decode(LatencyScaleVector.self, from: Spec.file("vectors/meters/latency-scale.json"))
    for p in v.points {
        #expect(close(Meter.latencyScaleMs(baselineMs: p.baseline_ms), p.scale_ms))
        for s in p.normalized {
            #expect(close(Meter.latency(s.rtt_ms, baselineMs: p.baseline_ms), s.value))
        }
    }
}
