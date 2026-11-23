import Foundation

/// The Metrics the Verdict reads, with the same meaning on every platform (spec rules/verdict.md,
/// "Local rules"). Each platform maps its own counters to them.
public struct Sample: Codable, Sendable, Equatable {
    public enum MemPressure: String, Codable, Sendable { case normal, warn, critical }

    public struct Disk: Codable, Sendable, Equatable {
        /// Share of time with at least one request in flight, in %.
        public var busy: Double
        /// Mean time per completed request, in ms.
        public var responseMs: Double
        public init(busy: Double, responseMs: Double) { self.busy = busy; self.responseMs = responseMs }
        enum CodingKeys: String, CodingKey { case busy = "DiskBusy", responseMs = "DiskResponse" }
    }

    /// 1000 pages/s of 4 KiB.
    public static let heavyPageInsBps = 4_096_000.0

    /// Non-idle share of all logical CPUs, in %.
    public var cpuBusy: Double?
    public var memPressure: MemPressure?
    /// Bytes read from disk into memory per second.
    public var memPageIns: Double?
    public var disks: [Disk]
    /// Bytes/s on the Followed Adapter.
    public var netUp: Double?
    public var netDown: Double?

    public init(cpuBusy: Double? = nil, memPressure: MemPressure? = nil, memPageIns: Double? = nil,
                disks: [Disk] = [], netUp: Double? = nil, netDown: Double? = nil) {
        self.cpuBusy = cpuBusy; self.memPressure = memPressure; self.memPageIns = memPageIns
        self.disks = disks; self.netUp = netUp; self.netDown = netDown
    }

    enum CodingKeys: String, CodingKey {
        case cpuBusy = "CpuBusy", memPressure = "MemPressure", memPageIns = "MemPageIns", disks = "Disks"
        case netUp = "NetUp", netDown = "NetDown"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cpuBusy = try c.decodeIfPresent(Double.self, forKey: .cpuBusy)
        memPressure = try c.decodeIfPresent(MemPressure.self, forKey: .memPressure)
        memPageIns = try c.decodeIfPresent(Double.self, forKey: .memPageIns)
        disks = try c.decodeIfPresent([Disk].self, forKey: .disks) ?? []
        netUp = try c.decodeIfPresent(Double.self, forKey: .netUp)
        netDown = try c.decodeIfPresent(Double.self, forKey: .netDown)
    }
}
