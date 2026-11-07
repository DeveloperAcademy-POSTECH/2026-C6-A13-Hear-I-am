import Foundation

/// Owns only custom speech-model caches. A lease protects a builder or recognizer until it has
/// actually finished; invalidation makes its result unusable without deleting files underneath it.
public final class VoiceModelCache: @unchecked Sendable {
    public final class Lease: @unchecked Sendable {
        public let folder: URL
        fileprivate let generation: UInt64
        fileprivate let owner: VoiceModelCache
        fileprivate init(folder: URL, generation: UInt64, owner: VoiceModelCache) {
            self.folder = folder; self.generation = generation; self.owner = owner
        }
        public var isCurrent: Bool { owner.isCurrent(self) }
        deinit { owner.release(folder.lastPathComponent) }
    }

    public struct CleanupReport: Sendable {
        public var removed = 0
        public var failures = 0
    }

    public let root: URL
    private let lock = NSLock()
    private let cleanupQueue = DispatchQueue(label: "VoiceModelCache.cleanup", qos: .utility)
    private var generation: UInt64 = 0
    private var leasedFolders: Set<String> = []
    private let onCleanupFailure: @Sendable (Int) -> Void

    public init(root: URL, onCleanupFailure: @escaping @Sendable (Int) -> Void = { _ in }) {
        self.root = root
        self.onCleanupFailure = onCleanupFailure
    }

    /// Every preparation has its own directory, even if two services request the same phrases.
    /// This prevents an obsolete asynchronous preparation from overwriting a newer vocabulary.
    public func acquire() throws -> Lease {
        lock.lock(); defer { lock.unlock() }
        let manager = FileManager.default
        if manager.fileExists(atPath: root.path) {
            guard try isRealDirectory(root) else { throw CocoaError(.fileWriteInvalidFileName) }
        } else {
            // A dangling link must not be followed when creating the cache root.
            if (try? manager.attributesOfItem(atPath: root.path)[.type]) as? FileAttributeType == .typeSymbolicLink {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
        }
        let identifier = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let folder = root.appendingPathComponent(identifier, isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        leasedFolders.insert(identifier)
        return Lease(folder: folder, generation: generation, owner: self)
    }

    /// Results already being prepared are rejected when delivered after this call.
    public func invalidate() {
        lock.lock(); generation &+= 1; lock.unlock()
        scheduleCleanup()
    }

    public func scheduleCleanup() {
        cleanupQueue.async { [self] in
            let report = cleanup()
            if report.failures > 0 { onCleanupFailure(report.failures) }
        }
    }

    /// Unknown files and symbolic links are preserved. Historical 1–16 hexadecimal hash folders
    /// and this owner's 32-hexadecimal preparation IDs are the only removable entries.
    @discardableResult public func cleanup() -> CleanupReport {
        lock.lock(); defer { lock.unlock() }
        var report = CleanupReport()
        let manager = FileManager.default
        guard manager.fileExists(atPath: root.path) else { return report }
        do {
            guard try isRealDirectory(root) else { return report }
            let entries = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for entry in entries {
                let name = entry.lastPathComponent
                guard Self.ownedName(name), !leasedFolders.contains(name) else { continue }
                do {
                    guard try isRealDirectory(entry) else { continue }
                    try manager.removeItem(at: entry)
                    report.removed += 1
                } catch { report.failures += 1 }
            }
        } catch { report.failures += 1 }
        return report
    }

    private func isCurrent(_ lease: Lease) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return lease.generation == generation && leasedFolders.contains(lease.folder.lastPathComponent)
    }
    private func release(_ identifier: String) {
        lock.lock(); leasedFolders.remove(identifier); lock.unlock()
        scheduleCleanup()
    }
    private static func ownedName(_ name: String) -> Bool {
        ((1...16).contains(name.count) || name.count == 32)
            && name.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func isRealDirectory(_ url: URL) throws -> Bool {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.type] as? FileAttributeType == .typeDirectory
    }
}
