// spec rules/probe-stats.md, "Results": a round trip is recorded in whole milliseconds, so
// every platform stores, ranks and rolls up the same numbers.

public enum RTT {
    /// A measured round trip `d` ms as recorded: ⌊d + 0.5⌋.
    public static func recorded(_ measuredMs: Double) -> Double { (measuredMs + 0.5).rounded(.down) }
}

extension RTT {
    /// Milliseconds as displayed, without the unit: whole numbers, and "< 1" below half a
    /// millisecond. Stats such as jitter can be fractional; displays still show whole ms.
    public static func display(_ ms: Double) -> String {
        ms < 0.5 ? "< 1" : String(Int(recorded(ms)))
    }
}
