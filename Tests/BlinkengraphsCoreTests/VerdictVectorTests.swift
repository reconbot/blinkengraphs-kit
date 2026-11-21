import Testing
import BlinkengraphsCore

struct VerdictVector: Decodable {
    let input: VerdictInput
    let expected: [Finding]
}

@Test func verdictVectors() throws {
    for (name, v) in try Spec.vectors("verdict", as: VerdictVector.self) {
        #expect(Verdict.evaluate(v.input) == v.expected, "\(name)")
    }
}

@Test func deniedProbesAreAbsentNotLost() {
    // A denied Gateway Probe never reaches the Verdict, so healthy internet reads as clear.
    let input = VerdictInput(probes: [
        .init(probe: .init(target: "1.1.1.1", protocol: "icmp"),
              stat: .init(loss: 0, rttMs: 12, baselineMs: 12, jitterMs: 1)),
    ])
    #expect(Verdict.evaluate(input) == [Finding(domain: .clear, severity: .ok, headline: "All clear")])
}
