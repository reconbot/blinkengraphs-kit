// defaults.json and tokens/*.json, bundled from the pinned spec.
// rules/defaults.md: platform overrides merge over the shared defaults.
import Foundation

public struct Defaults: Decodable, Sendable {
    /// One row of a Probe Group: a Target and what to measure on it (CONTEXT.md "Probe Group").
    public struct Target: Codable, Equatable, Hashable, Sendable {
        public var target: String
        public var icmp: Bool
        public var dns: Bool
        public var trace: Bool
        public var tcp: Int?
        public var udp: Int?

        public init(target: String, icmp: Bool, dns: Bool, trace: Bool, tcp: Int?, udp: Int?) {
            self.target = target; self.icmp = icmp; self.dns = dns; self.trace = trace; self.tcp = tcp; self.udp = udp
        }

        /// `gateway`, `system-dns`, an IPv4 or IPv6 address, or a host name (RFC 1123 labels).
        public static func isValid(_ text: String) -> Bool {
            if text == Probe.gateway || text == Probe.systemDNS || PublicAddress.canonical(text) != nil { return true }
            let labels = text.split(separator: ".", omittingEmptySubsequences: false)
            guard text.count <= 253, !labels.isEmpty, labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 }) else { return false }
            // An all-numeric name would be a malformed address, not a host.
            guard labels.contains(where: { $0.contains { !$0.isNumber } }) else { return false }
            return labels.allSatisfy { label in
                label.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
                    && label.first != "-" && label.last != "-"
            }
        }

        /// The Gateway and the system resolver have no route to trace.
        public var traceable: Bool { target != Probe.gateway && target != Probe.systemDNS }
    }

    public struct ProbeGroup: Codable, Equatable, Sendable {
        public var name: String
        public var targets: [Target]
        public var latencyMs: Int
        public var dnsMs: Int
        public var traceMs: Int

        public init(name: String, targets: [Target], latencyMs: Int, dnsMs: Int, traceMs: Int) {
            self.name = name; self.targets = targets; self.latencyMs = latencyMs; self.dnsMs = dnsMs; self.traceMs = traceMs
        }

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
        public struct ArchiveDefaults: Decodable, Sendable {
            public var stepS: Int
            public var rows: Int
            enum CodingKeys: String, CodingKey { case stepS = "step_s", rows }
        }
        public var rawMinutes: Int
        public var recentWindowS: Int
        /// A1, A2 and A3, finest first (rules/history.md, "Archives").
        public var archives: [ArchiveDefaults]
        enum CodingKeys: String, CodingKey {
            case rawMinutes = "raw_minutes", recentWindowS = "recent_window_s", archives
        }
    }

    public struct HopTraceDefaults: Decodable, Sendable {
        public var maxTtl: Int
        public var hopWindow: Int
        public var fullSweepEveryS: Int
        /// Show Hop names from reverse DNS (rules/hop-trace.md, "Names").
        public var reverseDns: Bool
        enum CodingKeys: String, CodingKey {
            case maxTtl = "max_ttl", hopWindow = "hop_window", fullSweepEveryS = "full_sweep_every_s"
            case reverseDns = "reverse_dns"
        }
    }

    /// spec rules/public-address.md
    public struct PublicAddressDefaults: Decodable, Sendable {
        public var dnsName: String
        public var dnsServer: String
        /// One URL per IP version; each host has addresses of that version only, so DNS picks it.
        public var httpsURLIPv4: String
        public var httpsURLIPv6: String
        public var refreshS: Int
        enum CodingKeys: String, CodingKey {
            case dnsName = "dns_name", dnsServer = "dns_server", httpsURLIPv4 = "https_url_ipv4",
                 httpsURLIPv6 = "https_url_ipv6", refreshS = "refresh_s"
        }
        public func httpsURL(_ family: IPFamily) -> String { family == .ipv6 ? httpsURLIPv6 : httpsURLIPv4 }
    }

    public var probeGroup: ProbeGroup
    public var history: History
    public var hopTrace: HopTraceDefaults
    public var maxTimeoutMs: Int
    public var dnsQueryName: String
    /// The Appearance until the user picks one in Settings.
    public var appearance: Appearance
    /// What a history graph point shows until the user picks one in Settings (rules/graph-aggregate.md).
    public var graphAggregate: Aggregate
    /// What a Probe's latency readout shows until the user picks one (rules/probe-stats.md, "Readouts").
    public var readoutAggregate: Aggregate
    /// Plain HTTP on purpose: a portal can intercept it (rules/verdict.md, "Captive Portal").
    public var captivePortalURL: String
    public var publicAddress: PublicAddressDefaults

    enum CodingKeys: String, CodingKey {
        case probeGroup = "probe_group", history, hopTrace = "hop_trace"
        case maxTimeoutMs = "max_timeout_ms", dnsQueryName = "dns_query_name", appearance
        case graphAggregate = "graph_aggregate", readoutAggregate = "readout_aggregate"
        case captivePortalURL = "captive_portal_url", publicAddress = "public_address"
    }

    /// The spec's shared defaults with this platform's `defaults.override.json` merged over them.
    public static func decode(_ shared: Data, override: Data = Data("{}".utf8)) throws -> Defaults {
        let merged = DefaultsMerge.merge(try JSONSerialization.jsonObject(with: shared),
                                         try JSONSerialization.jsonObject(with: override))
        return try JSONDecoder().decode(Defaults.self, from: JSONSerialization.data(withJSONObject: merged))
    }

    public func probeTimeoutMs(intervalMs: Int) -> Int { min(intervalMs, maxTimeoutMs) }
}

/// CONTEXT.md "Appearance": the color set the app draws with. `system` follows the OS.
public enum Appearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark
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

public enum DefaultsMerge {
    /// Objects merge key by key, a `null` member removes the key, anything else replaces whole.
    public static func merge(_ base: Any, _ override: Any) -> Any {
        guard var b = base as? [String: Any], let o = override as? [String: Any] else { return override }
        for (k, v) in o {
            if v is NSNull { b[k] = nil } else { b[k] = merge(b[k] ?? NSNull(), v) }
        }
        return b
    }
}
