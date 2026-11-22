// CONTEXT.md: the Gateway is the first-hop router on the Followed Adapter's default route.

public enum Gateway {
    /// Whether an IPv4 gateway address is a router worth probing. 192.0.0.0/29 is the
    /// 464XLAT translator on IPv6-only cellular (RFC 7335, https://www.rfc-editor.org/rfc/rfc7335),
    /// which iOS reports as the gateway although it lives on the device.
    public static func isRouter(_ ipv4: String) -> Bool {
        let octets = ipv4.split(separator: ".").compactMap { UInt8($0) }
        guard octets.count == 4 else { return false }
        return !(octets[0] == 192 && octets[1] == 0 && octets[2] == 0 && octets[3] < 8)
    }
}
