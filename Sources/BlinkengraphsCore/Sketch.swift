// rules/graph-aggregate.md. Exact arithmetic only, so results match vectors/sketch bit for bit.

/// What a history graph point shows when it covers several samples.
public enum Aggregate: String, CaseIterable, Sendable {
    case p50, p95, p99, avg, max

    /// For raw samples from the recent RAM history: the same rank on the sorted values, no histogram.
    public func value(ofSamples samples: [Double]) -> Double? {
        guard !samples.isEmpty else { return nil }
        switch self {
        case .avg: return samples.reduce(0, +) / Double(samples.count)
        case .max: return samples.max()
        case .p50, .p95, .p99: return samples.sorted()[perMille! * (samples.count - 1) / 1000]
        }
    }

    var perMille: Int? {
        switch self {
        case .p50: 500
        case .p95: 950
        case .p99: 990
        case .avg, .max: nil
        }
    }
}

/// The "BG-LL5" log-linear histogram: 32 buckets per power of two, from 2⁻¹⁰ up.
public struct Sketch: Equatable, Sendable {
    public static let bucketCount = 1600
    private static let zeroBelow = Double(sign: .plus, exponent: -10, significand: 1)

    public private(set) var zero = 0
    public private(set) var counts: [Int: Int] = [:]

    public init() {}

    /// Bucket index, or nil for the zero bucket (below 2⁻¹⁰, zero and negatives).
    public static func index(_ v: Double) -> Int? {
        guard v >= zeroBelow else { return nil }
        let b = v.bitPattern
        let e = Int((b >> 52) & 0x7FF) - 1023
        let m = Int((b >> 47) & 31)
        return min(max((e + 10) * 32 + m, 0), bucketCount - 1)
    }

    /// Harmonic mean of the bucket's bounds; relative error at most 1/65.
    public static func representative(_ index: Int) -> Double {
        let e = index / 32 - 10, m = index % 32
        let step = Double(sign: .plus, exponent: e - 5, significand: 1)
        let lo = Double(32 + m) * step, hi = Double(33 + m) * step
        return 2 * lo * hi / (lo + hi)
    }

    public mutating func add(_ v: Double) {
        if let i = Self.index(v) { counts[i, default: 0] += 1 } else { zero += 1 }
    }

    public mutating func merge(_ other: Sketch) {
        zero += other.zero
        for (i, c) in other.counts { counts[i, default: 0] += c }
    }

    /// `uleb128(zero)`, then per non-empty bucket ascending `uleb128(gap)`, `uleb128(count)`.
    public var encoded: [UInt8] {
        var out: [UInt8] = []
        func uleb(_ x: Int) {
            var x = UInt64(x)
            repeat {
                var byte = UInt8(x & 0x7F)
                x >>= 7
                if x != 0 { byte |= 0x80 }
                out.append(byte)
            } while x != 0
        }
        uleb(zero)
        var previous = -1
        for i in counts.keys.sorted() {
            uleb(i - previous - 1)
            uleb(counts[i]!)
            previous = i
        }
        return out
    }

    /// The value at integer rank `r` (0-based): 0 in the zero bucket, else the bucket's
    /// representative clamped to `[lo, hi]`.
    func value(atRank r: Int, clampedTo lo: Double, _ hi: Double) -> Double {
        if r < zero { return 0 }
        var cumulative = zero
        for i in counts.keys.sorted() {
            cumulative += counts[i]!
            if cumulative > r { return Swift.min(Swift.max(Self.representative(i), lo), hi) }
        }
        return 0
    }
}

/// One key's per-minute storage.
public struct Minute: Equatable, Sendable {
    public private(set) var n = 0
    public private(set) var lost = 0
    public private(set) var sum = 0.0
    public private(set) var min = Double.infinity
    public private(set) var max = -Double.infinity
    public private(set) var sketch = Sketch()

    public init() {}

    /// Records one value; nil is a lost Probe.
    public mutating func record(_ value: Double?) {
        guard let v = value else { lost += 1; return }
        n += 1
        sum += v
        min = Swift.min(min, v)
        max = Swift.max(max, v)
        sketch.add(v)
    }

    /// Merges minutes given in ascending order; the sum depends on that order, the rest doesn't.
    public static func merge<S: Sequence>(_ minutes: S) -> Minute where S.Element == Minute {
        var out = Minute()
        for m in minutes {
            out.n += m.n
            out.lost += m.lost
            out.sum += m.sum
            out.min = Swift.min(out.min, m.min)
            out.max = Swift.max(out.max, m.max)
            out.sketch.merge(m.sketch)
        }
        return out
    }

    public var loss: Double { n + lost == 0 ? 0 : Double(lost) / Double(n + lost) }

    /// Nil when no value was recorded.
    public func value(_ aggregate: Aggregate) -> Double? {
        guard n > 0 else { return nil }
        switch aggregate {
        case .avg: return sum / Double(n)
        case .max: return max
        case .p50, .p95, .p99:
            return sketch.value(atRank: aggregate.perMille! * (n - 1) / 1000, clampedTo: min, max)
        }
    }
}
