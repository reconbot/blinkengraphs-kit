// rules/hop-trace.md
import Foundation

public struct HopResult: Codable, Equatable, Sendable {
    public var ttl: Int
    public var addr: String?
    public var rttMs: Double?
    public var reached: Bool

    public init(ttl: Int, addr: String?, rttMs: Double?, reached: Bool) {
        self.ttl = ttl; self.addr = addr; self.rttMs = rttMs; self.reached = reached
    }

    enum CodingKeys: String, CodingKey { case ttl, addr, rttMs = "rtt_ms", reached }
}

public struct HopRow: Codable, Equatable, Sendable {
    public var ttl: Int
    public var addr: String?
    public var sent: Int
    public var loss: Double
    public var lastMs: Double?
    public var bestMs: Double?
    public var avgMs: Double?
    public var worstMs: Double?

    enum CodingKeys: String, CodingKey {
        case ttl, addr, sent, loss
        case lastMs = "last_ms", bestMs = "best_ms", avgMs = "avg_ms", worstMs = "worst_ms"
    }
}

/// Recording half of a Hop Trace: per-TTL results and the hop table.
/// Sweeping (sending the Probes) is platform code.
public struct HopTrace: Sendable {
    private struct Hop: Sendable { var addr: String?; var results: [HopResult] = [] }

    public let hopWindow: Int
    private var hops: [Int: Hop] = [:]

    public init(hopWindow: Int) { self.hopWindow = hopWindow }

    /// The lowest TTL at which the Target answered, once known.
    public var pathLength: Int? {
        hops.filter { $0.value.results.contains(where: \.reached) }.keys.min()
    }

    public mutating func record(_ r: HopResult) {
        var hop = hops[r.ttl] ?? Hop()
        if let addr = r.addr { hop.addr = addr }
        hop.results.append(r)
        if hop.results.count > hopWindow { hop.results.removeFirst(hop.results.count - hopWindow) }
        hops[r.ttl] = hop
        if r.reached { hops = hops.filter { $0.key <= r.ttl } }
    }

    public var table: [HopRow] {
        hops.keys.sorted().map { ttl in
            let hop = hops[ttl]!
            let replies = hop.results.compactMap(\.rttMs)
            return HopRow(
                ttl: ttl,
                addr: hop.addr,
                sent: hop.results.count,
                loss: hop.results.isEmpty ? 0 : 1 - Double(replies.count) / Double(hop.results.count),
                lastMs: hop.results.last?.rttMs,
                bestMs: replies.min(),
                avgMs: replies.isEmpty ? nil : replies.reduce(0, +) / Double(replies.count),
                worstMs: replies.max()
            )
        }
    }
}
