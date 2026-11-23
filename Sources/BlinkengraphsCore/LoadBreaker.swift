import Foundation

/// Stops a launch crash loop caused by History on disk (ADR 0018). `begin()` before loading,
/// `end()` once loading and the first write are done. When `limit` loads in a row never
/// reached `end()`, the next `begin()` deletes the directory, so the app starts with empty
/// History; on iPhone it is fine to lose. The count lives beside the directory, in
/// `<name>.loading`, so deleting the directory leaves it.
public struct LoadBreaker: Sendable {
    private let directory: URL
    private let limit: Int

    public init(directory: URL, limit: Int = 2) {
        self.directory = directory
        self.limit = limit
    }

    private var counter: URL { directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + ".loading") }

    /// Whether History was deleted. Records this load as unfinished until `end()`.
    @discardableResult
    public func begin() -> Bool {
        let fm = FileManager.default
        let unfinished = (try? Data(contentsOf: counter)).flatMap { Int(String(decoding: $0, as: UTF8.self)) } ?? 0
        let tripped = unfinished >= limit
        if tripped { try? fm.removeItem(at: directory) }
        try? fm.createDirectory(at: counter.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Written before loading starts: a trap mid-load leaves it for the next launch. No fsync
        // needed; a killed process keeps what the kernel has (ADR 0016).
        try? Data(String(tripped ? 1 : unfinished + 1).utf8).write(to: counter)
        return tripped
    }

    public func end() {
        try? FileManager.default.removeItem(at: counter)
    }
}
