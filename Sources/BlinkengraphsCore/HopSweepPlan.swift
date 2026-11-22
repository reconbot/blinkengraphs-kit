// rules/hop-trace.md, "Sweeping".

/// Which TTLs the next Hop Trace sweep sends.
public struct HopSweepPlan: Sendable {
    public let maxTtl: Int
    public let fullSweepEveryS: Double
    private var lastFullSweepAt: Double?

    public init(maxTtl: Int, fullSweepEveryS: Double) {
        self.maxTtl = maxTtl
        self.fullSweepEveryS = fullSweepEveryS
    }

    /// Up to the known path length, except a full sweep every `fullSweepEveryS` in case the path grew.
    public mutating func ttls(at now: Double, pathLength: Int?) -> ClosedRange<Int> {
        if let length = pathLength, let last = lastFullSweepAt, now - last < fullSweepEveryS {
            return 1...min(length, maxTtl)
        }
        lastFullSweepAt = now
        return 1...maxTtl
    }
}
