import Foundation

/// Locates the pinned spec checkout (the `spec` submodule) and decodes its vectors.
enum Spec {
    static let root: URL = {
        if let path = ProcessInfo.processInfo.environment["BLINKENGRAPHS_SPEC"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BlinkengraphsCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // BlinkengraphsKit
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("spec")
    }()

    static func vectors<T: Decodable>(_ dir: String, as: T.Type) throws -> [(String, T)] {
        let url = root.appendingPathComponent("vectors").appendingPathComponent(dir)
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        precondition(!files.isEmpty, "no vectors in \(url.path); run `git submodule update --init`")
        return try files.map { ($0.lastPathComponent, try JSONDecoder().decode(T.self, from: Data(contentsOf: $0))) }
    }

    static func file(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(path))
    }
}

func close(_ a: Double?, _ b: Double?, within tolerance: Double = 0.01) -> Bool {
    switch (a, b) {
    case (nil, nil): true
    case let (x?, y?): abs(x - y) <= tolerance
    default: false
    }
}
