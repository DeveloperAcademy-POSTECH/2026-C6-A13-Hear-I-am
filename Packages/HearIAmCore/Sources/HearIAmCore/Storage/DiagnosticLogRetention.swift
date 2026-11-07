import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Only app-owned diagnostic JSONL files are subject to three calendar months of retention.
/// User stages, photos, routes, guidance records, preferences and unknown files are never traversed.
public enum DiagnosticLogRetention {
    public struct Failure: Equatable, Sendable {
        public let url: URL
        public let message: String
    }
    public struct Report: Sendable {
        public internal(set) var scannedFiles = 0
        public internal(set) var deletedFiles = 0
        public internal(set) var rewrittenFiles = 0
        public internal(set) var removedRecords = 0
        public internal(set) var removedTemporaryFiles = 0
        public internal(set) var skippedActiveFiles = 0
        public internal(set) var skippedChangedFiles = 0
        public internal(set) var skippedFiles = 0
        public internal(set) var failures: [Failure] = []
        public var failureCount: Int { failures.count }
        public var summary: String {
            "diagnostic retention: checked=\(scannedFiles) deleted=\(deletedFiles) rewritten=\(rewrittenFiles) removed=\(removedRecords) temporary=\(removedTemporaryFiles) active=\(skippedActiveFiles) changed=\(skippedChangedFiles) failed=\(failureCount)"
        }
    }

    private final class State {
        let lock = NSRecursiveLock()
        let cleanupLock = NSLock()
        var active: Set<String> = []
    }
    private static let state = State()
    private static let folders = ["VoiceLogs", "Trials", "SoundTests"]
    private static let chunkSize = 64 * 1024

    /// Shared by file writers and cleanup commits. The closure must not escape, await or call prune.
    /// Call prune after leaving this closure so its separate cleanup lock cannot invert lock order.
    public static func withFileAccess<T>(_ operation: () throws -> T) rethrows -> T {
        state.lock.lock()
        defer { state.lock.unlock() }
        return try operation()
    }
    static func registerActive(_ url: URL) {
        withFileAccess { _ = state.active.insert(url.standardizedFileURL.path) }
    }
    static func unregisterActive(_ url: URL) {
        withFileAccess { _ = state.active.remove(url.standardizedFileURL.path) }
    }
    /// TrialLog can also be used outside the app's diagnostic directories, for example in tests.
    static func pruneAfterClosing(_ url: URL) {
        let directory = url.deletingLastPathComponent()
        guard ["Trials", "SoundTests"].contains(directory.lastPathComponent) else { return }
        _ = prune(documents: directory.deletingLastPathComponent())
    }

    public static func prune(documents: URL, now: Date = Date()) -> Report {
        state.cleanupLock.lock()
        defer {state.cleanupLock.unlock()}
        var report = Report()
        let root = documents.standardizedFileURL
        let clock = RetentionClock(now: now)
        do {
            guard let rootInfo = try information(root), isDirectory(rootInfo) else { return report }
        } catch {
            report.failures.append(.init(url: root, message: error.localizedDescription))
            return report
        }
        for name in folders {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            do {
                guard let info = try information(directory) else { continue }
                guard isDirectory(info) else { report.skippedFiles += 1; continue }
                let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
                for file in files {
                    let temporary = isTemporary(file.lastPathComponent)
                    guard temporary || recognized(file.lastPathComponent, in: name) else { report.skippedFiles += 1; continue }
                    do {
                        if temporary {
                            try withFileAccess {
                                guard let rootInfo = try information(root), isDirectory(rootInfo),
                                      let directoryInfo = try information(directory), isDirectory(directoryInfo),
                                      let info = try information(file), isRegular(info) else {throw RetentionError.skippedFile}
                                // A terminated rewrite leaves a copy, never the only surviving original.
                                guard unlink(file.path) == 0 else {throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)}
                            }
                            report.removedTemporaryFiles += 1
                            continue
                        }
                        report.scannedFiles += 1
                        let result = try pruneFile(file, directory: directory, root: root, clock: clock)
                        report.deletedFiles += result.deleted ? 1 : 0
                        report.rewrittenFiles += result.rewritten ? 1 : 0
                        report.removedRecords += result.removedRecords
                    } catch RetentionError.activeFile {report.skippedActiveFiles += 1}
                    catch RetentionError.changedFile {report.skippedChangedFiles += 1}
                    catch RetentionError.skippedFile {report.skippedFiles += 1}
                    catch {report.failures.append(.init(url: file, message: error.localizedDescription))}
                }
            } catch { report.failures.append(.init(url: directory, message: error.localizedDescription)) }
        }
        return report
    }

    private static func isTemporary(_ name: String) -> Bool {
        let prefix = ".retention-", suffix = ".tmp"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count == prefix.count + 36 + suffix.count else { return false }
        return UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(suffix.count))) != nil
    }

    private static func recognized(_ name: String, in directory: String) -> Bool {
        if directory == "VoiceLogs" {
            guard name.hasPrefix("voice-"), name.hasSuffix(".jsonl"), name.count == 22 else { return false }
            let date = String(name.dropFirst(6).dropLast(6))
            let parts = date.split(separator: "-", omittingEmptySubsequences: false)
            guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
                  parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
                  let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year > 0 else { return false }
            let calendar = RetentionClock.calendar
            let fields = DateComponents(year: year, month: month, day: day)
            guard let value = calendar.date(from: fields) else { return false }
            return calendar.dateComponents([.year, .month, .day], from: value) == fields
        }
        guard name.hasPrefix("trial-"), name.hasSuffix(".jsonl"), name.count == 48 else { return false }
        return UUID(uuidString: String(name.dropFirst(6).dropLast(6))) != nil
    }

    private final class RetentionClock {
        // Trial rows share second-resolution dates; bound memory while avoiding repeated ISO parsing.
        private var dateDecisions: [String: Bool] = [:]
        let now: Date
        let fractional: ISO8601DateFormatter
        let whole: ISO8601DateFormatter
        static var calendar: Calendar {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(secondsFromGMT: 0)!
            return value
        }
        init(now: Date) {
            self.now = now
            fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
        }
        func expired(_ date: Date) -> Bool {
            guard let expiration = Self.calendar.date(byAdding: .month, value: 3, to: date) else { return false }
            return expiration <= now
        }
        func expired(_ row: Data, fallback: Date) -> Bool {
            guard let object = (try? JSONSerialization.jsonObject(with: row)) as? [String: Any] else {
                return expired(fallback)
            }
            var values = [object["time"], object["wallTime"]]
            if object["event"] as? String == "header" { values.append(object["createdAt"]) }
            for text in values.compactMap({$0 as? String}) {
                if let cached = dateDecisions[text] {return cached}
                let parsed = text.contains(".") ? fractional.date(from: text) : whole.date(from: text)
                guard let date = parsed else {continue}
                let decision = expired(date)
                if dateDecisions.count >= 512 {dateDecisions.removeAll(keepingCapacity: true)}
                dateDecisions[text] = decision
                return decision
            }
            return expired(fallback)
        }
    }
    private struct Pruned {
        var deleted = false
        var rewritten = false
        var removedRecords = 0
    }
    private enum RetentionError: LocalizedError {
        case missingDate, changedFile, activeFile, skippedFile
        var errorDescription: String? {
            switch self {
            case .missingDate: return "The diagnostic file has no usable creation or modification date."
            case .changedFile: return "The diagnostic file or directory changed during cleanup; retry next time."
            case .activeFile: return "The diagnostic file is active."
            case .skippedFile: return "This path is not an eligible regular diagnostic file."
            }
        }
    }

    private static func pruneFile(_ url: URL, directory: URL, root: URL, clock: RetentionClock) throws -> Pruned {
        let snapshot: (FileHandle, stat, [FileAttributeKey: Any]) = try withFileAccess {
            guard let rootInfo = try information(root), isDirectory(rootInfo),
                  let directoryInfo = try information(directory), isDirectory(directoryInfo),
                  let info = try information(url), isRegular(info) else {throw RetentionError.skippedFile}
            guard !state.active.contains(url.standardizedFileURL.path) else {throw RetentionError.activeFile}
            let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW)
            guard descriptor >= 0 else {throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)}
            let input = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            do {
                var opened = stat()
                guard fstat(descriptor, &opened) == 0, sameFile(opened, info) else {throw RetentionError.changedFile}
                return (input, info, try FileManager.default.attributesOfItem(atPath: url.path))
            } catch {try? input.close();throw error}
        }
        let (input, info, attributes) = snapshot
        defer {try? input.close()}
        // Streaming and scratch-file preparation do not block the main thread's TrialLog init or a
        // voice append. Commit rechecks both the active registry and the original file's version.
        // Old TrialLog headers and malformed rows have no date. Do not refresh their age on a rewrite.
        guard let fallback = (attributes[.creationDate] as? Date) ?? (attributes[.modificationDate] as? Date) else { throw RetentionError.missingDate }
        var liveRecords = 0, expiredRecords = 0
        try rows(input) { row in
            if clock.expired(row, fallback: fallback) { expiredRecords += 1 } else { liveRecords += 1 }
        }
        // Headers are diagnostic records too: an explicit expired date never outlives the limit.
        // Undated legacy headers and malformed rows use the same stable file-date fallback.
        let noRows = liveRecords + expiredRecords == 0
        if liveRecords == 0 && (expiredRecords > 0 || (noRows && clock.expired(fallback))) {
            try withFileAccess {
                try verifyUnchanged(url, directory: directory, root: root, original: info)
                guard unlink(url.path) == 0 else {throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)}
            }
            return Pruned(deleted: true, removedRecords: expiredRecords)
        }
        guard expiredRecords > 0 else { return Pruned() }

        let temporary = directory.appendingPathComponent(".retention-\(UUID().uuidString).tmp")
        let outputDescriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard outputDescriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let output = FileHandle(fileDescriptor: outputDescriptor, closeOnDealloc: true)
        defer { try? output.close(); try? FileManager.default.removeItem(at: temporary) }
        try input.seek(toOffset: 0)
        try rows(input) { row in
            if !clock.expired(row, fallback: fallback) { try output.write(contentsOf: row) }
        }
        try output.synchronize()
        try output.close()
        var preserved: [FileAttributeKey: Any] = [:]
        for key in [FileAttributeKey.creationDate, .modificationDate, .posixPermissions] {
            if let value = attributes[key] { preserved[key] = value }
        }
        try FileManager.default.setAttributes(preserved, ofItemAtPath: temporary.path)
        try withFileAccess {
            try verifyUnchanged(url, directory: directory, root: root, original: info)
            // Same-directory rename replaces atomically; a failed rename leaves the original intact.
            guard rename(temporary.path, url.path) == 0 else {throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)}
        }
        return Pruned(rewritten: true, removedRecords: expiredRecords)
    }

    /// Reads in chunks and retains only one JSONL row, never the full multi-session file.
    private static func rows(_ input: FileHandle, visit: (Data) throws -> Void) throws {
        var row = Data()
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let newline = chunk[start...].firstIndex(of: 0x0a)
                let end = newline.map { chunk.index(after: $0) } ?? chunk.endIndex
                row.append(contentsOf: chunk[start..<end])
                if newline != nil { try visit(row); row.removeAll(keepingCapacity: true) }
                start = end
            }
        }
        if !row.isEmpty { try visit(row) }
    }
    private static func information(_ url: URL) throws -> stat? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else {
            if errno == ENOENT { return nil }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return value
    }
    private static func isDirectory(_ value: stat) -> Bool { value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) }
    private static func isRegular(_ value: stat) -> Bool { value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) }
    private static func sameFile(_ a: stat, _ b: stat) -> Bool {
        guard isRegular(a), isRegular(b), a.st_dev == b.st_dev, a.st_ino == b.st_ino, a.st_size == b.st_size else { return false }
        #if canImport(Darwin)
        return a.st_mtimespec.tv_sec == b.st_mtimespec.tv_sec && a.st_mtimespec.tv_nsec == b.st_mtimespec.tv_nsec
        #else
        return a.st_mtim.tv_sec == b.st_mtim.tv_sec && a.st_mtim.tv_nsec == b.st_mtim.tv_nsec
        #endif
    }
    private static func verifyUnchanged(_ url: URL, directory: URL, root: URL, original: stat) throws {
        guard !state.active.contains(url.standardizedFileURL.path) else {throw RetentionError.activeFile}
        guard let rootInfo = try information(root), isDirectory(rootInfo),
              let directoryInfo = try information(directory), isDirectory(directoryInfo),
              let current = try information(url), sameFile(current, original) else { throw RetentionError.changedFile }
    }
}
