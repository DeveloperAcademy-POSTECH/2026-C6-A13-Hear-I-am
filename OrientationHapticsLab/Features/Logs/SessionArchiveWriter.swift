import Foundation
import OrientationCore

struct SessionArchive: Codable, Sendable {
    var version = 1
    var records: [SessionRecord]
    var completionNotes: [String: String]

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

/// Serialization and disk writes run outside MainActor and cannot finish out of order.
actor SessionArchiveWriter {
    private var latestRevision: UInt = 0

    func save(_ archive: SessionArchive, to url: URL, revision: UInt) -> String? {
        guard revision > latestRevision else { return nil }
        latestRevision = revision
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try SessionArchive.encoder().encode(archive)
            try data.write(to: url, options: .atomic)
            return nil
        } catch { return error.localizedDescription }
    }
}
