// defaults.json and tokens/*.json, bundled from the pinned spec.
import Foundation

public struct Defaults: Decodable, Sendable {
    public struct Target: Decodable, Sendable {
        public var target: String
        public var icmp: Bool
        public var dns: Bool
        public var trace: Bool
        public var tcp: Int?
        public var udp: Int?
    }

    public struct ProbeGroup: Decodable, Sendable {
        public var name: String
        public var targets: [Target]
        public var latencyMs: Int
        public var dnsMs: Int
        public var traceMs: Int

        enum CodingKeys: String, CodingKey {
            case name, targets, latencyMs = "latency_ms", dnsMs = "dns_ms", traceMs = "trace_ms"
        }

        /// Latency and DNS Probes this group runs, in table order.
        public var probes: [Probe] {
            targets.flatMap { t in
                [t.icmp ? "icmp" : nil, t.tcp.map { "tcp:\($0)" }, t.udp.map { "udp:\($0)" }, t.dns ? "dns" : nil]
                    .compactMap { $0 }.map { Probe(target: t.target, protocol: $0) }
            }
        }
    }

    public struct History: Decodable, Sendable {
        public var ramMinutes: Int
        public var recentWindowS: Int
        enum CodingKeys: String, CodingKey { case ramMinutes = "ram_minutes", recentWindowS = "recent_window_s" }
    }

    public struct HopTraceDefaults: Decodable, Sendable {
        public var maxTtl: Int
        public var hopWindow: Int
        public var fullSweepEveryS: Int
        enum CodingKeys: String, CodingKey {
            case maxTtl = "max_ttl", hopWindow = "hop_window", fullSweepEveryS = "full_sweep_every_s"
        }
    }

    public var probeGroup: ProbeGroup
    public var history: History
    public var hopTrace: HopTraceDefaults
    public var maxTimeoutMs: Int
    public var dnsQueryName: String

    enum CodingKeys: String, CodingKey {
        case probeGroup = "probe_group", history, hopTrace = "hop_trace"
        case maxTimeoutMs = "max_timeout_ms", dnsQueryName = "dns_query_name"
    }

    public static func decode(_ data: Data) throws -> Defaults { try JSONDecoder().decode(Defaults.self, from: data) }

    public func probeTimeoutMs(intervalMs: Int) -> Int { min(intervalMs, maxTimeoutMs) }
}

public struct RGB: Equatable, Sendable {
    public var r: Double, g: Double, b: Double

    public init?(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xff) / 255; g = Double((v >> 8) & 0xff) / 255; b = Double(v & 0xff) / 255
    }
}

/// W3C design tokens, looked up by dotted path.
public struct Tokens: Sendable {
    private let colors: [String: RGB]
    private let numbers: [String: Double]

    public static func decode(_ data: Data) throws -> Tokens {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var colors: [String: RGB] = [:], numbers: [String: Double] = [:]
        func walk(_ node: [String: Any], _ path: [String]) {
            if let type = node["$type"] as? String {
                let key = path.joined(separator: ".")
                switch type {
                case "color": colors[key] = (node["$value"] as? String).flatMap(RGB.init(hex:))
                case "number": numbers[key] = (node["$value"] as? NSNumber)?.doubleValue
                default: break
                }
                return
            }
            for (k, v) in node { if let child = v as? [String: Any] { walk(child, path + [k]) } }
        }
        walk(root, [])
        return Tokens(colors: colors, numbers: numbers)
    }

    /// Full dotted path, such as `color.severity.crit` or `threshold.meter-warn`.
    public func color(_ path: String) -> RGB? { colors[path] }
    public func number(_ path: String) -> Double? { numbers[path] }
}
