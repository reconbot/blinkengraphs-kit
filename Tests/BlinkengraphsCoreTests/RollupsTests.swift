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

@Test func aWrittenMinuteIsNeverWrittenAgain() {
    var r = Rollups(keepDays: 7, maxTimeoutMs: 1000)
    _ = r.record(icmp, ProbeResult(at: 10, rttMs: 1), on: wifi)
    let first = r.record(icmp, ProbeResult(at: 62, rttMs: 1), on: wifi)
    #expect(first.map(\.minute) == [0] && r.writtenThrough == 60)
    // A straggler for minute 0, after it was written: kept out of storage, not merged.
    let late = r.record(icmp, ProbeResult(at: 30, rttMs: 9), on: wifi)
    #expect(late.isEmpty)
    #expect(r.minutes(icmp, on: wifi, from: 0, before: 60).map(\.data.n) == [1])
}

@Test func shutdownWritesEveryPendingMinute() {
    var r = Rollups(keepDays: 7, maxTimeoutMs: 1000)
    _ = r.record(icmp, ProbeResult(at: 10, rttMs: 1), on: wifi)
    _ = r.record(icmp, ProbeResult(at: 40, rttMs: 1), on: cell)
    #expect(r.flush().map(\.minute) == [0, 0])
    #expect(r.writtenThrough == 60)
    #expect(r.flush().isEmpty)
}

@Test func insertedMinutesMoveTheHandover() {
    var r = Rollups(keepDays: 7, maxTimeoutMs: 1000)
    var m = Minute()
    m.record(30)
    r.insert(StoredMinute(link: wifi, probe: icmp, minute: 2, data: m))
    #expect(r.writtenThrough == 180)
    #expect(r.minutes(icmp, on: wifi, from: 0, before: 180).map(\.m) == [120])
    #expect(r.oldest == 120)
}

@Test func minutesOlderThanTheKeepAreDropped() {
    var r = Rollups(keepDays: 1, maxTimeoutMs: 1000)
    _ = r.record(icmp, ProbeResult(at: 0, rttMs: 10), on: wifi)
    _ = r.record(icmp, ProbeResult(at: 70, rttMs: 10), on: wifi)
    _ = r.record(icmp, ProbeResult(at: 86_400 + 200, rttMs: 10), on: cell)
    #expect(r.minutes(icmp, on: wifi, from: 0, before: 86_400).isEmpty)
}

@Test func aMinuteReadBackAfterRecordingBeganStands() {
    var r = Rollups(keepDays: 7, maxTimeoutMs: 1000)
    _ = r.record(icmp, ProbeResult(at: 10, rttMs: 1), on: wifi)
    var stored = Minute()
    stored.record(30)
    r.insert(StoredMinute(link: wifi, probe: icmp, minute: 0, data: stored))
    #expect(r.flush().isEmpty)
    #expect(r.minutes(icmp, on: wifi, from: 0, before: 60).map(\.data) == [stored])
}

@Test func pausingWritesOnlyMinutesThatHaveEnded() {
    var r = Rollups(keepDays: 7, maxTimeoutMs: 1000)
    _ = r.record(icmp, ProbeResult(at: 10, rttMs: 1), on: wifi)
    // Within the grace, so minute 0 is still pending.
    _ = r.record(icmp, ProbeResult(at: 61, rttMs: 2), on: wifi)
    // Paused at 62 s: minute 0 has ended; minute 60 is still open and stays pending.
    #expect(r.flushEnded(at: 62).map(\.minute) == [0])
    #expect(r.writtenThrough == 60)
    _ = r.record(icmp, ProbeResult(at: 80, rttMs: 3), on: wifi)
    let later = r.record(icmp, ProbeResult(at: 122, rttMs: 4), on: wifi)
    var minute = Minute()
    minute.record(2); minute.record(3)
    #expect(later.map(\.minute) == [1] && later.first?.data == minute)
}
