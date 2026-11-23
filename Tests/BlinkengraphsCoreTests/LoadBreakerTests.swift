import Foundation
import Testing
import BlinkengraphsCore

private func scratch() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("history"), withIntermediateDirectories: true)
    try Data([1, 2, 3]).write(to: dir.appendingPathComponent("history/archives.bin"))
    return dir
}

private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

@Test func aLoadThatFinishesLeavesHistoryInPlace() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    for _ in 0..<5 {
        #expect(!breaker.begin())
        breaker.end()
    }
    #expect(exists(history.appendingPathComponent("archives.bin")))
}

@Test func oneUnfinishedLoadIsForgiven() throws {
    // A user can swipe the app away mid-load; that alone must not cost them their History.
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    #expect(!breaker.begin())
    #expect(!breaker.begin())
    #expect(exists(history.appendingPathComponent("archives.bin")))
}

@Test func twoUnfinishedLoadsInARowDeleteHistory() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    _ = breaker.begin()
    _ = breaker.begin()
    #expect(breaker.begin())
    #expect(!exists(history))
    // The fresh start loads normally.
    breaker.end()
    #expect(!breaker.begin())
}

@Test func aFinishedLoadResetsTheCount() throws {
    let dir = try scratch(), history = dir.appendingPathComponent("history")
    let breaker = LoadBreaker(directory: history)
    _ = breaker.begin()
    _ = breaker.begin()
    breaker.end()
    #expect(!breaker.begin())
    #expect(!breaker.begin())
    #expect(exists(history.appendingPathComponent("archives.bin")))
}
