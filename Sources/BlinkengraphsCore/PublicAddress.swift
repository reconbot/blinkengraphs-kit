// spec rules/public-address.md
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum IPFamily: String, Codable, Sendable { case ipv4, ipv6 }

/// What one IP version's two lookups say about the Public Address.
public struct PublicAddressReading: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable { case none, nat64, agree, differ, single }
    public enum Source: String, Codable, Sendable { case dns, https }

    public var state: State
    public var address: String?
    public var dns: String?
    public var https: String?
    public var source: Source?
    public var asn: String?

    public init(state: State, address: String? = nil, dns: String? = nil, https: String? = nil,
                source: Source? = nil, asn: String? = nil) {
        self.state = state; self.address = address; self.dns = dns; self.https = https
        self.source = source; self.asn = asn
    }
}

public enum PublicAddress {
    /// `dnsTXT` is the TXT strings of the whoami answer and `httpsBody` the icanhazip body; nil when
    /// that lookup failed.
    public static func read(family: IPFamily, dnsTXT: [String]?, httpsBody: String?) -> PublicAddressReading {
        let fields = (dnsTXT ?? []).compactMap { line -> (String, String)? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return (line[..<colon].trimmingCharacters(in: .whitespaces),
                    line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
        }
        let dns = fields.first { $0.0 == "remote_ip" }.flatMap { canonical($0.1) }
        let asn = fields.first { $0.0 == "asn" }?.1
        let https = httpsBody.flatMap { canonical($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        switch (dns, https) {
        case (nil, nil):
            return PublicAddressReading(state: .none)
        case let (d, h) where family == .ipv6 && [d, h].contains(where: { $0.map(isIPv4) ?? false }):
            return PublicAddressReading(state: .nat64, address: [d, h].compactMap { $0 }.first(where: isIPv4))
        case let (d?, h?) where d == h:
            return PublicAddressReading(state: .agree, address: d, asn: asn)
        case let (d?, h?):
            return PublicAddressReading(state: .differ, dns: d, https: h, asn: asn)
        case let (d?, nil):
            return PublicAddressReading(state: .single, address: d, source: .dns, asn: asn)
        case let (nil, h?):
            return PublicAddressReading(state: .single, address: h, source: .https)
        }
    }

    private static func isIPv4(_ s: String) -> Bool { !s.contains(":") }

    /// The address in canonical text (RFC 5952 for IPv6), or nil when it isn't one.
    public static func canonical(_ text: String) -> String? {
        var v4 = in_addr()
        if inet_pton(AF_INET, text, &v4) == 1 { return ntop(AF_INET, &v4, Int(INET_ADDRSTRLEN)) }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, text, &v6) == 1 { return ntop(AF_INET6, &v6, Int(INET6_ADDRSTRLEN)) }
        return nil
    }

    private static func ntop<T>(_ family: Int32, _ addr: inout T, _ size: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: size)
        guard inet_ntop(family, &addr, &buffer, socklen_t(size)) != nil else { return nil }
        return String(cString: buffer)
    }
}
