import Foundation
import Testing
import BlinkengraphsCore

/// An f64 carried with its exact bits: `{"value": …, "bits": "<16 hex>"}`.
struct Bits: Decodable, Equatable {
    let bits: String
    var double: Double { Double(bitPattern: UInt64(bits, radix: 16)!) }
}

private func hex(_ d: Double) -> String { String(format: "%016llx", d.bitPattern) }

struct IndexVector: Decodable {
    struct Case: Decodable { let value: Bits; let index: Int?; let rep: Bits? }
    let cases: [Case]
}

struct MinuteJSON: Decodable {
    let n: Int, lost: Int, sk: String
    let sum: Bits?, min: Bits?, max: Bits?
}

struct MinutesVector: Decodable {
    struct Case: Decodable { let values: [Double?]; let minute: MinuteJSON }
    let cases: [Case]
}

struct MergeVector: Decodable {
    let merged: MinuteJSON
    let loss: Double
    let aggregates: [String: Bits]
}

private func load<T: Decodable>(_ name: String, as: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Spec.file("vectors/sketch/\(name).json"))
}

private func rollups() throws -> [Minute] {
    try load("minutes", as: MinutesVector.self).cases.map { c in
        var m = Minute()
        for v in c.values { m.record(v) }
        return m
    }
}

@Test func sketchIndexVector() throws {
    for c in try load("index", as: IndexVector.self).cases {
        let idx = Sketch.index(c.value.double)
        #expect(idx == c.index, "\(c.value.bits)")
        if let i = idx, let rep = c.rep { #expect(hex(Sketch.representative(i)) == rep.bits, "rep \(i)") }
    }
}

@Test func sketchMinutesVector() throws {
    let v = try load("minutes", as: MinutesVector.self)
    for (m, c) in zip(try rollups(), v.cases) {
        #expect(m.n == c.minute.n && m.lost == c.minute.lost)
        #expect(m.sketch.encoded.hex == c.minute.sk)
        #expect(c.minute.sum.map { hex(m.sum) == $0.bits } ?? true)
        #expect(c.minute.min.map { hex(m.min) == $0.bits } ?? true)
        #expect(c.minute.max.map { hex(m.max) == $0.bits } ?? true)
    }
}

@Test func sketchMergeVector() throws {
    let v = try load("merge", as: MergeVector.self)
    let minutes = try rollups()
    let merged = Minute.merge(minutes)
    #expect(merged.n == v.merged.n && merged.lost == v.merged.lost)
    #expect(merged.sketch.encoded.hex == v.merged.sk)
    #expect(hex(merged.sum) == v.merged.sum?.bits)
    #expect(abs(merged.loss - v.loss) <= 0.01)
    // Any merge order gives the same histogram.
    #expect(Minute.merge(minutes.reversed()).sketch.encoded == merged.sketch.encoded)
    let aggregates: [String: Aggregate] = ["avg": .avg, "max": .max, "p50": .p50, "p95": .p95, "p99": .p99]
    for (name, bits) in v.aggregates {
        #expect(merged.value(aggregates[name]!).map(hex) == bits.bits, "\(name)")
    }
}

private extension Array where Element == UInt8 {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}

@Test func zeroBucketRankIsZeroEvenAboveTheMinimum() {
    var m = Minute()
    for v in [0.0005, 0.0005, 0.0005, 50] { m.record(v) } // 0.0005 < 2⁻¹⁰: zero bucket
    #expect(m.value(.p50) == 0)
}

@Test func rawSamplesUseTheSameRank() {
    let samples = [5.0, 1, 4, 2, 3]
    #expect(Aggregate.p50.value(ofSamples: samples) == 3)
    #expect(Aggregate.p95.value(ofSamples: samples) == 4) // ⌊950 · 4 / 1000⌋ = 3
    #expect(Aggregate.max.value(ofSamples: samples) == 5)
    #expect(Aggregate.avg.value(ofSamples: samples) == 3)
}
