import Foundation
import Testing
import BlinkengraphsCore

// spec rules/history.md, vectors/history/*.json

private struct File<Case: Decodable>: Decodable { var cases: [Case] }

private func file<T: Decodable>(_ name: String, as: T.Type) throws -> T {
    try JSONDecoder().decode(T.self, from: Spec.file("vectors/history/\(name).json"))
}

@Test func timingVectors() throws {
    struct Case: Decodable {
        struct Round: Decodable { var at: Double; var start: Double }
        var name: String; var start: Double; var interval_s: Double; var durations_s: [Double]; var expected: [Round]
    }
    for c in try file("timing", as: File<Case>.self).cases {
        var clock = RoundClock(start: c.start, interval: c.interval_s)
        for (i, duration) in c.durations_s.enumerated() {
            #expect(abs(clock.start - c.expected[i].start) < 1e-6 && clock.at == c.expected[i].at, "\(c.name) round \(i)")
            clock.finished(at: clock.start + duration)
        }
    }
}

@Test func minutesVectors() throws {
    struct Case: Decodable { var name: String; var max_timeout_ms: Int; var arrivals: [Double]; var expected: [[Int]] }
    let probe = Probe(target: "1.1.1.1", protocol: "icmp"), link = Link(interface: "en0", gateway: nil)
    for c in try file("minutes", as: File<Case>.self).cases {
        var r = Rollups(keepDays: 7, maxTimeoutMs: c.max_timeout_ms)
        for (i, at) in c.arrivals.enumerated() {
            let written = r.record(probe, ProbeResult(at: at, rttMs: 1), on: link).map { $0.minute * 60 }
            #expect(written == c.expected[i], "\(c.name) after arrival \(i)")
        }
    }
}

@Test func rangeVectors() throws {
    struct Range: Decodable { var range: String; var span_s: Double; var ram_bucket_s: Double; var storage_bucket_s: Double }
    struct File: Decodable { var ranges: [Range] }
    for r in try file("ranges", as: File.self).ranges {
        let w = HistoryBuckets.widths(span: r.span_s)
        #expect(w.ram == r.ram_bucket_s && w.storage == r.storage_bucket_s, "\(r.range)")
    }
}

@Test func bucketVectors() throws {
    struct Stored: Decodable { var m: Double; var n: Int; var lost: Int; var max: Double }
    struct Ram: Decodable { var at: Double; var v: Double? }
    struct Point: Decodable { var at: Double; var loss: Double; var max: Double? }
    struct Case: Decodable { var range: String; var span_s: Double; var now: Double; var expected: [Point] }
    struct File: Decodable {
        var aggregate: Aggregate; var written_through: Double; var stored: [Stored]; var ram: [Ram]; var cases: [Case]
    }
    let f = try file("buckets", as: File.self)
    let stored = f.stored.map { (m: $0.m, data: Minute(n: $0.n, lost: $0.lost, max: $0.max)) }
    let ram = f.ram.map { ProbeResult(at: $0.at, rttMs: $0.v) }
    for c in f.cases {
        let points = HistoryBuckets.points(span: c.span_s, now: c.now, aggregate: f.aggregate, ram: ram,
                                           stored: stored, writtenThrough: f.written_through)
        #expect(points.count == c.expected.count, "\(c.range) count")
        for (p, e) in zip(points, c.expected) {
            #expect(p.start == e.at && close(p.value, e.max) && abs(p.loss - e.loss) < 0.006, "\(c.range) at \(e.at)")
        }
    }
}
