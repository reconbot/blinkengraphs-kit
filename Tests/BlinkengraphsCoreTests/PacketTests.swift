import Testing
import BlinkengraphsCore

@Test func echoRequestChecksumVerifies() {
    let pkt = ICMP.echoRequest(identifier: 0x1234, sequence: 7, payload: Array("blinkengraphs".utf8))
    #expect(pkt[0] == 8 && pkt[1] == 0)
    #expect(Array(pkt[6...7]) == [0, 7])
    // A correct checksum makes the whole packet sum to zero.
    #expect(ICMP.checksum(pkt) == 0)
}

/// An IPv4 header (20 bytes, no options) from `src`, followed by `body`.
private func ipv4(from src: [UInt8], _ body: [UInt8]) -> [UInt8] {
    [0x45, 0, 0, UInt8(20 + body.count), 0, 0, 0, 0, 64, 1, 0, 0] + src + [192, 168, 1, 50] + body
}

@Test func parsesEchoReplyWithAndWithoutIPHeader() {
    var reply = ICMP.echoRequest(identifier: 1, sequence: 42, payload: [])
    reply[0] = 0
    #expect(ICMP.parse(reply, includesIPHeader: false) == ICMP.Reply(kind: .echoReply, sequence: 42))
    #expect(ICMP.parse(ipv4(from: [1, 1, 1, 1], reply), includesIPHeader: true) == ICMP.Reply(kind: .echoReply, sequence: 42))
}

@Test func timeExceededCarriesTheOriginalSequence() {
    // A router quotes our IP header and the first 8 bytes of our echo request.
    let original = ipv4(from: [192, 168, 1, 50], ICMP.echoRequest(identifier: 1, sequence: 9, payload: []))
    let timeExceeded: [UInt8] = [11, 0, 0, 0, 0, 0, 0, 0] + original
    #expect(ICMP.parse(ipv4(from: [10, 0, 0, 1], timeExceeded), includesIPHeader: true)
        == ICMP.Reply(kind: .timeExceeded, sequence: 9))
    #expect(ICMP.parse([3, 3, 0, 0, 0, 0, 0, 0] + original, includesIPHeader: false)
        == ICMP.Reply(kind: .unreachable, sequence: 9))
}

@Test func rejectsTruncatedPackets() {
    #expect(ICMP.parse([0, 0, 0], includesIPHeader: false) == nil)
    #expect(ICMP.parse([11, 0, 0, 0, 0, 0, 0, 0, 0x45], includesIPHeader: false) == nil)
}

@Test func dnsQueryEncodesName() {
    let q = DNS.query(id: 0xbeef, name: "cloudflare.com")
    #expect(Array(q[0...1]) == [0xbe, 0xef])
    #expect(Array(q[2...3]) == [0x01, 0x00]) // recursion desired
    #expect(Array(q[4...5]) == [0, 1])
    #expect(Array(q[12...]) == [10] + Array("cloudflare".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1])
}

@Test func dnsResponseMatchesIdAndReadsRcode() {
    var r = DNS.query(id: 0xbeef, name: "cloudflare.com")
    r[2] = 0x81; r[3] = 0x80 // response, no error
    #expect(DNS.parseResponse(r, id: 0xbeef) == DNS.Response(rcode: 0))
    #expect(DNS.parseResponse(r, id: 0x0001) == nil)
    r[3] = 0x83
    #expect(DNS.parseResponse(r, id: 0xbeef) == DNS.Response(rcode: 3))
    #expect(DNS.parseResponse(DNS.query(id: 0xbeef, name: "a.b"), id: 0xbeef) == nil) // a query, not a response
}

// ICMPv6 (RFC 4443). Datagram ICMPv6 sockets deliver no IPv6 header and the kernel fills the checksum.
@Test func icmp6EchoRequestLayout() {
    let pkt = ICMP6.echoRequest(identifier: 0x1234, sequence: 7, payload: [1, 2])
    #expect(pkt == [128, 0, 0, 0, 0x12, 0x34, 0, 7, 1, 2])
}

/// An IPv6 header (40 bytes) quoted inside an ICMPv6 error.
private func ipv6Header() -> [UInt8] { [0x60] + [UInt8](repeating: 0, count: 39) }

@Test func icmp6RepliesCarryTheSequence() {
    var reply = ICMP6.echoRequest(identifier: 1, sequence: 42, payload: [])
    reply[0] = 129
    #expect(ICMP6.parse(reply) == ICMP.Reply(kind: .echoReply, sequence: 42))

    let quoted = ipv6Header() + ICMP6.echoRequest(identifier: 1, sequence: 9, payload: [])
    #expect(ICMP6.parse([3, 0, 0, 0, 0, 0, 0, 0] + quoted) == ICMP.Reply(kind: .timeExceeded, sequence: 9))
    #expect(ICMP6.parse([1, 4, 0, 0, 0, 0, 0, 0] + quoted) == ICMP.Reply(kind: .unreachable, sequence: 9))
    #expect(ICMP6.parse([3, 0, 0, 0, 0, 0, 0, 0, 0x60]) == nil)
    #expect(ICMP6.parse([135, 0, 0, 0, 0, 0, 0, 0]) == nil) // neighbour solicitation
}
