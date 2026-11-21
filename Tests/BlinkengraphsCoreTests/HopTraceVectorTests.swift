import Testing
import BlinkengraphsCore

struct HopTraceVector: Decodable {
    let hop_window: Int
    let ticks: [[HopResult]]
    let expected: [HopRow]
}

@Test func hopTraceVectors() throws {
    for (name, v) in try Spec.vectors("hop-trace", as: HopTraceVector.self) {
        var trace = HopTrace(hopWindow: v.hop_window)
        for tick in v.ticks { for r in tick { trace.record(r) } }
        let table = trace.table
        #expect(table.count == v.expected.count, "\(name) row count")
        for (got, want) in zip(table, v.expected) {
            #expect(got.ttl == want.ttl && got.addr == want.addr && got.sent == want.sent, "\(name) ttl \(want.ttl)")
            #expect(close(got.loss, want.loss), "\(name) ttl \(want.ttl) loss")
            #expect(close(got.lastMs, want.lastMs), "\(name) ttl \(want.ttl) last")
            #expect(close(got.bestMs, want.bestMs), "\(name) ttl \(want.ttl) best")
            #expect(close(got.avgMs, want.avgMs), "\(name) ttl \(want.ttl) avg")
            #expect(close(got.worstMs, want.worstMs), "\(name) ttl \(want.ttl) worst")
        }
    }
}
