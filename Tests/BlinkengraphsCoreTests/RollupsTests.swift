import Foundation
import Testing
import BlinkengraphsCore

private let icmp = Probe(target: "1.1.1.1", protocol: "icmp")
private let wifi = Link(interface: "en0", gateway: "192.168.1.1")
private let cell = Link(interface: "pdp_ip0", gateway: nil)

@Test func sketchDecodesWhatItEncodes() throws {
    var s = Sketch()
    for v in [0.0, 0.0005, 1, 12.5, 12.6, 300, 300, 9000] { s.add(v) }
    #expect(try Sketch(encoded: s.encoded) == s)
    #expect(try Sketch(encoded: Sketch().encoded) == Sketch())
}

@Test func storedMinutesRoundTripThroughJSON() throws {
    var m = Minute()
    for v in [12.0, nil, 14.5, 13] { m.record(v) }
    let stored = StoredMinute(link: wifi, probe: icmp, minute: 29_000_000, data: m)
    let back = try JSONDecoder().decode(StoredMinute.self, from: JSONEncoder().encode(stored))
    #expect(back == stored)
}

@Test func aMinuteClosesWhenTheNextOneStarts() {
    var r = Rollups(keepDays: 7)
    #expect(r.record(icmp, ProbeResult(at: 60, rttMs: 10), on: wifi).isEmpty)
    #expect(r.record(icmp, ProbeResult(at: 119, rttMs: nil), on: wifi).isEmpty)
    let closed = r.record(icmp, ProbeResult(at: 120, rttMs: 12), on: wifi)
    #expect(closed.count == 1)
    #expect(closed.first?.minute == 1 && closed.first?.data.n == 1 && closed.first?.data.lost == 1)
    #expect(r.record(icmp, ProbeResult(at: 130, rttMs: 12), on: wifi).isEmpty)
}

@Test func graphPointsMergeWholeMinutesPerBucket() {
    var r = Rollups(keepDays: 7)
    for minute in 0..<4 {
        for s in 0..<10 { _ = r.record(icmp, ProbeResult(at: Double(minute * 60 + s), rttMs: Double(minute + 1)), on: wifi) }
    }
    _ = r.record(icmp, ProbeResult(at: 125, rttMs: nil), on: wifi)
    let points = r.points(icmp, on: wifi, from: 0, to: 240, count: 2, aggregate: .max)
    #expect(points.map(\.start) == [0, 120])
    #expect(points.map(\.value) == [2, 4])
    #expect(points[0].loss == 0)
    #expect(abs(points[1].loss - 1.0 / 21) < 1e-12)
    #expect(r.points(icmp, on: cell, from: 0, to: 240, count: 2, aggregate: .max).allSatisfy { $0.count == 0 })
}

@Test func summaryCoversTheWholeRange() {
    var r = Rollups(keepDays: 7)
    for (i, v) in [5.0, 1, 3].enumerated() { _ = r.record(icmp, ProbeResult(at: Double(i * 60), rttMs: v), on: wifi) }
    _ = r.record(icmp, ProbeResult(at: 200, rttMs: nil), on: wifi)
    let s = r.summary(icmp, on: wifi, from: 0, to: 240, aggregate: .max)
    #expect(s.value == 5 && s.loss == 0.25)
}

@Test func insertedMinutesMergeWithLiveOnes() {
    var r = Rollups(keepDays: 7)
    _ = r.record(icmp, ProbeResult(at: 61, rttMs: 10), on: wifi)
    var earlier = Minute()
    earlier.record(30)
    r.insert(StoredMinute(link: wifi, probe: icmp, minute: 1, data: earlier))
    #expect(r.points(icmp, on: wifi, from: 60, to: 120, count: 1, aggregate: .max).first?.value == 30)
    #expect(r.points(icmp, on: wifi, from: 60, to: 120, count: 1, aggregate: .max).first?.count == 2)
}

@Test func minutesOlderThanTheKeepAreDropped() {
    var r = Rollups(keepDays: 1)
    _ = r.record(icmp, ProbeResult(at: 0, rttMs: 10), on: wifi)
    _ = r.record(icmp, ProbeResult(at: 86_400 + 120, rttMs: 10), on: cell)
    #expect(r.points(icmp, on: wifi, from: 0, to: 60, count: 1, aggregate: .max).first?.count == 0)
}
