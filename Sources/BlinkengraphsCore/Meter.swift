// vectors/meters/*.json
import Foundation

public enum Meter {
    /// Network throughput: cbrt(value / max), clamped to 0...1.
    public static func cubeRoot(_ value: Double, max: Double) -> Double {
        guard max > 0 else { return 0 }
        return min(Foundation.cbrt(Swift.max(value, 0) / max), 1)
    }

    /// The Latency Meter's full height: max(4 × baseline, 100 ms); no baseline counts as 20 ms.
    public static func latencyScaleMs(baselineMs: Double?) -> Double {
        Swift.max(4 * (baselineMs ?? 20), 100)
    }

    public static func latency(_ rttMs: Double, baselineMs: Double?) -> Double {
        min(rttMs / latencyScaleMs(baselineMs: baselineMs), 1)
    }
}
