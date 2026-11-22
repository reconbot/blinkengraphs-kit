// Wire formats for the Probes the platform sends. Pure bytes, so they test on Linux.

/// ICMPv4 echo (RFC 792).
public enum ICMP {
    public struct Reply: Equatable, Sendable {
        public enum Kind: Sendable { case echoReply, timeExceeded, unreachable }
        public var kind: Kind
        /// The sequence of the echo request this answers. Match on it, not the identifier:
        /// unprivileged datagram ICMP sockets may rewrite the identifier.
        public var sequence: UInt16

        public init(kind: Kind, sequence: UInt16) { self.kind = kind; self.sequence = sequence }
    }

    public static func echoRequest(identifier: UInt16, sequence: UInt16, payload: [UInt8]) -> [UInt8] {
        var p: [UInt8] = [8, 0, 0, 0, UInt8(identifier >> 8), UInt8(identifier & 0xff),
                          UInt8(sequence >> 8), UInt8(sequence & 0xff)] + payload
        let c = checksum(p)
        p[2] = UInt8(c >> 8); p[3] = UInt8(c & 0xff)
        return p
    }

    /// Internet checksum (RFC 1071). Zero over a packet whose checksum is correct.
    public static func checksum(_ b: [UInt8]) -> UInt16 {
        var sum: UInt32 = 0
        var i = 0
        while i + 1 < b.count { sum += UInt32(b[i]) << 8 | UInt32(b[i + 1]); i += 2 }
        if i < b.count { sum += UInt32(b[i]) << 8 }
        while sum >> 16 != 0 { sum = (sum & 0xffff) + (sum >> 16) }
        return ~UInt16(sum)
    }

    /// Darwin's datagram ICMP sockets deliver the IPv4 header in front of the ICMP message.
    public static func parse(_ bytes: [UInt8], includesIPHeader: Bool) -> Reply? {
        var b = bytes[...]
        if includesIPHeader {
            guard let ihl = ipHeaderLength(b) else { return nil }
            b = b.dropFirst(ihl)
        }
        guard b.count >= 8 else { return nil }
        let type = b[b.startIndex]
        switch type {
        case 0:
            return Reply(kind: .echoReply, sequence: be16(b, 6))
        case 11, 3:
            // The error quotes our IPv4 header and the first 8 bytes of our echo request.
            let quoted = b.dropFirst(8)
            guard let ihl = ipHeaderLength(quoted), quoted.count >= ihl + 8 else { return nil }
            let echo = quoted.dropFirst(ihl)
            guard echo[echo.startIndex] == 8 else { return nil }
            return Reply(kind: type == 11 ? .timeExceeded : .unreachable, sequence: be16(echo, 6))
        default:
            return nil
        }
    }

    private static func ipHeaderLength(_ b: ArraySlice<UInt8>) -> Int? {
        guard let first = b.first, first >> 4 == 4 else { return nil }
        let ihl = Int(first & 0x0f) * 4
        return ihl >= 20 && b.count >= ihl ? ihl : nil
    }
}

/// DNS over UDP (RFC 1035): one query, just enough of the answer to time it, and TXT answers
/// for the Public Address lookup.
public enum DNS {
    public static let a: UInt16 = 1
    public static let txt: UInt16 = 16

    public struct Response: Equatable, Sendable {
        public var rcode: UInt8
        public init(rcode: UInt8) { self.rcode = rcode }
    }

    public static func query(id: UInt16, name: String, type: UInt16 = a) -> [UInt8] {
        var q: [UInt8] = [UInt8(id >> 8), UInt8(id & 0xff), 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            q.append(UInt8(label.utf8.count))
            q += label.utf8
        }
        return q + [0, UInt8(type >> 8), UInt8(type & 0xff), 0, 1] // root, type, class IN
    }

    /// The strings of every TXT answer in a response to query `id`, in order; nil when the bytes
    /// aren't such a response or are cut short.
    public static func txtRecords(_ bytes: [UInt8], id: UInt16) -> [String]? {
        guard bytes.count >= 12, be16(bytes[...], 0) == id, bytes[2] & 0x80 != 0 else { return nil }
        let questions = Int(be16(bytes[...], 4)), answers = Int(be16(bytes[...], 6))
        var i = 12
        /// Skips a name: labels, ending at the root or at a compression pointer.
        func skipName() -> Bool {
            while i < bytes.count {
                let len = Int(bytes[i])
                if len == 0 { i += 1; return true }
                if len & 0xC0 == 0xC0 { i += 2; return i <= bytes.count }
                i += 1 + len
            }
            return false
        }
        for _ in 0..<questions {
            guard skipName(), i + 4 <= bytes.count else { return nil }
            i += 4
        }
        var out: [String] = []
        for _ in 0..<answers {
            guard skipName(), i + 10 <= bytes.count else { return nil }
            let type = be16(bytes[...], i)
            let length = Int(be16(bytes[...], i + 8))
            i += 10
            guard i + length <= bytes.count else { return nil }
            if type == txt {
                var j = i
                while j < i + length {
                    let n = Int(bytes[j])
                    guard j + 1 + n <= i + length else { return nil }
                    out.append(String(decoding: bytes[(j + 1)..<(j + 1 + n)], as: UTF8.self))
                    j += 1 + n
                }
            }
            i += length
        }
        return out
    }

    /// Nil unless `bytes` is a response to query `id`. Any rcode counts as an answer:
    /// the server replied, which is what the Probe measures.
    public static func parseResponse(_ bytes: [UInt8], id: UInt16) -> Response? {
        guard bytes.count >= 12, be16(bytes[...], 0) == id, bytes[2] & 0x80 != 0 else { return nil }
        return Response(rcode: bytes[3] & 0x0f)
    }
}

private func be16(_ b: ArraySlice<UInt8>, _ offset: Int) -> UInt16 {
    let i = b.startIndex + offset
    return UInt16(b[i]) << 8 | UInt16(b[i + 1])
}

/// ICMPv6 echo (RFC 4443). Datagram ICMPv6 sockets carry no IPv6 header in either direction,
/// and the kernel computes the checksum over the pseudo-header.
public enum ICMP6 {
    public static func echoRequest(identifier: UInt16, sequence: UInt16, payload: [UInt8]) -> [UInt8] {
        [128, 0, 0, 0, UInt8(identifier >> 8), UInt8(identifier & 0xff),
         UInt8(sequence >> 8), UInt8(sequence & 0xff)] + payload
    }

    public static func parse(_ bytes: [UInt8]) -> ICMP.Reply? {
        let b = bytes[...]
        guard b.count >= 8 else { return nil }
        switch b[b.startIndex] {
        case 129:
            return ICMP.Reply(kind: .echoReply, sequence: be16(b, 6))
        case 3, 1:
            // The error quotes our IPv6 header (40 bytes) and the start of our echo request.
            let quoted = b.dropFirst(8)
            guard quoted.count >= 40 + 8, quoted[quoted.startIndex] >> 4 == 6 else { return nil }
            let echo = quoted.dropFirst(40)
            guard echo[echo.startIndex] == 128 else { return nil }
            return ICMP.Reply(kind: b[b.startIndex] == 3 ? .timeExceeded : .unreachable, sequence: be16(echo, 6))
        default:
            return nil
        }
    }
}
