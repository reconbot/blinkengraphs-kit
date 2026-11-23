import Foundation
import Testing
import BlinkengraphsCore

private let wifi = Link(interface: "en0", gateway: "192.168.1.1")
private let key = HistoryKey(link: wifi, probe: Probe(target: "1.1.1.1", protocol: "icmp"))
private let gw = HistoryKey(link: wifi, probe: Probe(target: "gateway", protocol: "icmp"))
private let t0 = 1_800_000_000

private func history() -> History {
    History(levels: [.init(step: 300, rows: 288), .init(step: 3600, rows: 168), .init(step: 86_400, rows: 365)],
            rawSeconds: 7200, g: 2)
}

@Test func everyRecordKindSurvivesTheRoundTrip() throws {
    var row = Row(values: [10, 17, nil, 0])
    row.record(65_000)
    let records: [HistoryRecord] = [
        .route(at: t0, link: wifi),
        .result(key, RawResult(at: t0, rttMs: 12)),
        .result(gw, RawResult(at: t0, rttMs: nil)),
        .result(key, RawResult(at: t0 + 1, rttMs: 0)),
        .pause(Pause(begin: Double(t0) + 2.5, end: Double(t0) + 40.25)),
        .mark(at: t0 + 41),
        .route(at: t0 + 42, link: nil),
        .row(level: 0, key: key, m: t0, row: row),
        .paused(level: 1, m: t0, seconds: 37.75),
        .written(level: 2, next: t0 + 86_400),
    ]
    var w = HistoryCodec.Writer()
    #expect(HistoryCodec.decode(w.encode(records)) == records)
}

@Test func aResultCostsNineBytesOnceItsKeyIsDefined() {
    var w = HistoryCodec.Writer()
    _ = w.encode([.result(key, RawResult(at: t0, rttMs: 1))])
    #expect(w.encode([.result(key, RawResult(at: t0 + 1, rttMs: 2))]).count == 9)
}

@Test func aTornTailEndsTheFileAndKeepsEverythingBefore() {
    var w = HistoryCodec.Writer()
    let whole: [HistoryRecord] = [.result(key, RawResult(at: t0, rttMs: 5)), .mark(at: t0 + 3)]
    let data = w.encode(whole) + w.encode([.result(key, RawResult(at: t0 + 4, rttMs: 6))])
    for cut in 1...8 { #expect(HistoryCodec.decode(data.dropLast(cut)) == whole, "cut \(cut)") }
}

@Test func appendsFromSeveralWritersToOneFileDecodeInOrder() {
    var a = HistoryCodec.Writer(), b = HistoryCodec.Writer()
    let first: [HistoryRecord] = [.result(gw, RawResult(at: t0, rttMs: 3))]
    let second: [HistoryRecord] = [.result(key, RawResult(at: t0 + 1, rttMs: 9))]
    #expect(HistoryCodec.decode(a.encode(first) + b.encode(second)) == first + second)
}

@Test func replayingWhatWasSavedRestoresTheHistory() {
    var h = history()
    h.route(at: t0, link: wifi)
    for s in 0..<900 { h.record(key, RawResult(at: t0 + s, rttMs: Double(10 + s % 7))) }
    h.add(Pause(begin: Double(t0 + 900), end: Double(t0 + 1500)))
    h.advance(now: t0 + 1500)
    h.mark(at: t0 + 1501)
    var w = HistoryCodec.Writer()
    var restored = history()
    restored.replay(HistoryCodec.decode(w.encode(h.takeUnsaved())))
    #expect(restored.unsaved.isEmpty)
    #expect(restored.raw == h.raw)
    #expect(restored.archives == h.archives)
    #expect(restored.paused == h.paused)
    #expect(restored.next == h.next)
    #expect(restored.pauses == h.pauses)
    #expect(restored.newestAt == t0 + 1501)
    // Restored steps are written: advancing again writes nothing twice.
    restored.advance(now: t0 + 1500)
    #expect(!restored.unsaved.contains { if case .row = $0 { true } else { false } })
}

@Test func compactionKeepsWhatTheArchivesHold() {
    var h = history()
    for s in 0..<600 { h.record(key, RawResult(at: t0 + s, rttMs: 10)) }
    h.add(Pause(begin: Double(t0 + 600), end: Double(t0 + 4000)))
    h.advance(now: t0 + 4000)
    var restored = history()
    restored.replay(h.archiveRecords)
    #expect(restored.archives == h.archives)
    #expect(restored.paused == h.paused)
    #expect(restored.next == h.next)
}

@Test func aKillAfterAMarkPausesFromTheMark() throws {
    var m = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")), settle: 2)
    m.resume(at: Double(t0))
    m.commit(.init(start: Double(t0) + 3.2, end: Double(t0) + 3.5, link: wifi, outcomes: [(key.probe, .reply(ms: 9))]))
    m.mark(at: Double(t0) + 60)
    var w = HistoryCodec.Writer()
    var h = History(defaults: try Defaults.decode(Spec.file("defaults.json")))
    h.replay(HistoryCodec.decode(w.encode(m.takeUnsaved())))
    var next = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")), settle: 2)
    next.restore(h, launch: Double(t0) + 400)
    next.resume(at: Double(t0) + 400)
    #expect(next.history.pauses.last == Pause(begin: Double(t0) + 61, end: Double(t0) + 402))
}

@Test func aFirstLaunchRestoresNothingWithoutTrapping() throws {
    // As Monitor.load() does with no files on disk: Int.min − 1 used to trap here.
    var m = Measurements(defaults: try Defaults.decode(Spec.file("defaults.json")), settle: 2)
    var h = History(defaults: try Defaults.decode(Spec.file("defaults.json")))
    h.replay([])
    m.restore(h, launch: Double(t0))
    m.advance(now: Double(t0))
    #expect(m.history.rawCutoff(now: t0) == .min)
    #expect(m.history.archiveRecords.isEmpty)
}
