import XCTest
@testable import HearIAmCore

final class DiagnosticLogRetentionTests: XCTestCase {
    private let fm = FileManager.default
    private func root() throws -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("diagnostic-retention-test-" + UUID().uuidString)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func date(_ text: String) -> Date {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)!
    }
    private func file(_ root: URL, folder: String = "Trials", name: String? = nil, text: String) throws -> URL {
        let directory = root.appendingPathComponent(folder)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name ?? "trial-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return url
    }
    private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    private func stamp(_ url: URL, created: Date, modified: Date? = nil) throws {
        try fm.setAttributes([.creationDate: created, .modificationDate: modified ?? created], ofItemAtPath: url.path)
        let actual = try fm.attributesOfItem(atPath: url.path)[.creationDate] as? Date
        XCTAssertEqual(try XCTUnwrap(actual).timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.01)
    }
    private func row(_ time: String, field: String = "wallTime", detail: String = "pose") -> String {
        "{\"\(field)\":\"\(time)\",\"event\":\"\(detail)\"}\n"
    }

    func testOnlyAllowlistedFoldersAndFilenamesArePruned() throws {
        let root = try root(); defer { try? fm.removeItem(at: root) }
        let expired = row("2026-01-01T00:00:00Z")
        let a = try file(root, text: expired)
        let b = try file(root, folder: "SoundTests", text: expired)
        let c = try file(root, folder: "VoiceLogs", name: "voice-2026-01-01.jsonl", text: row("2026-01-01T00:00:00.123Z", field: "time"))
        var protected: [URL] = []
        for folder in ["Scans", "Performances", "PerformancePlans", "GuidanceRecords", "PlaceFolders", "VoiceTest", "Trials/nested"] {
            protected.append(try file(root, folder: folder, text: expired))
        }
        for name in ["trial-invalid.jsonl", "trial-\(UUID().uuidString).json", "personal.jsonl", ".personal.jsonl"] {
            protected.append(try file(root, name: name, text: expired))
        }
        for name in ["voice-2026-02-30.jsonl", "voice-2026-1-01.jsonl", "voice-2026-01-01.json", "voice-invalid.jsonl"] {
            protected.append(try file(root, folder: "VoiceLogs", name: name, text: expired))
        }
        let pins = root.appendingPathComponent("stage-pins.json")
        try Data(expired.utf8).write(to: pins); protected.append(pins)
        let report = DiagnosticLogRetention.prune(documents: root, now: date("2026-05-01T00:00:00Z"))
        XCTAssertEqual(report.failureCount, 0, report.summary)
        XCTAssertEqual(report.deletedFiles, 3)
        for url in [a,b,c] { XCTAssertFalse(fm.fileExists(atPath: url.path)) }
        for url in protected { XCTAssertEqual(try read(url), expired) }
    }

    func testThreeCalendarMonthsAtExactBoundaryIncludingLeapDay() throws {
        let cases = [
            ("2026-01-31T12:34:56Z", "2026-04-30T12:34:56Z"),
            ("2023-11-30T00:00:00Z", "2024-02-29T00:00:00Z"),
            ("2026-08-31T00:00:00Z", "2026-11-30T00:00:00Z"),
            ("2026-01-08T23:01:02.123+09:00", "2026-04-08T14:01:02.123Z")
        ]
        for (recorded, boundary) in cases {
            let root = try root(); defer { try? fm.removeItem(at: root) }
            let content = row(recorded, field: "time")
            let url = try file(root, text: content)
            let before = DiagnosticLogRetention.prune(documents: root, now: date(boundary).addingTimeInterval(-0.001))
            XCTAssertEqual(before.deletedFiles, 0, "recorded \(recorded)")
            XCTAssertEqual(try read(url), content)
            let exact = DiagnosticLogRetention.prune(documents: root, now: date(boundary))
            XCTAssertEqual(exact.deletedFiles, 1, "recorded \(recorded)")
        }
    }

    func testMixedRowsRemoveExpiredHeaderAndKeepRecentBytesWithoutFinalNewline() throws {
        let root = try root(); defer { try? fm.removeItem(at: root) }
        let header = "{\"event\":\"header\",\"createdAt\":\"2026-07-01T00:00:00Z\",\"metadata\":{\"source\":\"test\"}}\n"
        let old = row("2026-07-01T01:00:00Z")
        let recent = row("2026-08-01T01:00:00Z").trimmingCharacters(in: .newlines)
        let url = try file(root, text: header + old + recent)
        let report = DiagnosticLogRetention.prune(documents: root, now: date("2026-10-02T00:00:00Z"))
        XCTAssertEqual(report.failureCount, 0, report.summary)
        XCTAssertEqual(report.rewrittenFiles, 1)
        XCTAssertEqual(report.removedRecords, 2)
        XCTAssertEqual(try read(url), recent)
        let repeated = DiagnosticLogRetention.prune(documents: root, now: date("2026-10-02T00:00:00Z"))
        XCTAssertEqual(repeated.rewrittenFiles, 0)
        XCTAssertEqual(repeated.deletedFiles, 0)
    }

    func testLegacyHeaderAndTruncatedLineUseCreationDateAndKeepItAcrossRewrite() throws {
        let root = try root(); defer { try? fm.removeItem(at: root) }
        let legacy = "{\"event\":\"header\",\"metadata\":{\"source\":\"legacy\"}}\n"
        let broken = "{\"event\":\"partially_written\"\n"
        let recent = row("2026-10-15T00:00:00Z")
        let url = try file(root, text: row("2026-01-01T00:00:00Z") + legacy + broken + recent)
        let created = date("2026-08-08T00:00:00Z"), modified = date("2026-11-01T00:00:00Z")
        try stamp(url, created: created, modified: modified)
        let first = DiagnosticLogRetention.prune(documents: root, now: date("2026-11-07T00:00:00Z"))
        XCTAssertEqual(first.failureCount, 0)
        XCTAssertEqual(try read(url), legacy + broken + recent)
        let attributes = try fm.attributesOfItem(atPath: url.path)
        XCTAssertEqual(try XCTUnwrap(attributes[.creationDate] as? Date).timeIntervalSince1970, created.timeIntervalSince1970, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(attributes[.modificationDate] as? Date).timeIntervalSince1970, modified.timeIntervalSince1970, accuracy: 0.01)
        let next = DiagnosticLogRetention.prune(documents: root, now: date("2026-11-08T00:00:00Z"))
        XCTAssertEqual(next.failureCount, 0)
        XCTAssertEqual(next.removedRecords, 2)
        XCTAssertEqual(try read(url), recent)
    }

    func testHeaderOnlyEmptyAndMalformedFilesExpireByTheirRecordedOrFallbackDate() throws {
        let root = try root(); defer { try? fm.removeItem(at: root) }
        let header = try file(root, text: "{\"event\":\"header\",\"time\":\"2026-01-01T00:00:00Z\"}\n")
        let legacy = try file(root, text: "{\"event\":\"header\",\"metadata\":{}}\n")
        let empty = try file(root, text: "")
        let broken = try file(root, text: "{broken")
        for url in [legacy, empty, broken] { try stamp(url, created: date("2026-01-01T00:00:00Z")) }
        let future = try file(root, text: row("2030-01-01T00:00:00Z"))
        let report = DiagnosticLogRetention.prune(documents: root, now: date("2026-04-01T00:00:00Z"))
        XCTAssertEqual(report.failureCount, 0)
        XCTAssertEqual(report.deletedFiles, 4)
        for url in [header,legacy,empty,broken] { XCTAssertFalse(fm.fileExists(atPath: url.path)) }
        XCTAssertTrue(fm.fileExists(atPath: future.path))
    }

    func testSymlinkedFilesFoldersAndDocumentsRootAreNeverFollowed() throws {
        let root = try root(), external = try self.root(); defer {try? fm.removeItem(at: root);try? fm.removeItem(at: external)}
        let contents = row("2026-01-01T00:00:00Z")
        let target = try file(external, text: contents)
        let trialDirectory = root.appendingPathComponent("Trials")
        try fm.createDirectory(at: trialDirectory, withIntermediateDirectories: true)
        let linkedFile = trialDirectory.appendingPathComponent("trial-\(UUID().uuidString).jsonl")
        try fm.createSymbolicLink(at: linkedFile, withDestinationURL: target)
        let linkedDirectory = root.appendingPathComponent("SoundTests")
        try fm.createSymbolicLink(at: linkedDirectory, withDestinationURL: target.deletingLastPathComponent())
        let documentsLink = root.appendingPathComponent("linked-documents")
        try fm.createSymbolicLink(at: documentsLink, withDestinationURL: external)
        let report = DiagnosticLogRetention.prune(documents: root, now: date("2026-05-01T00:00:00Z"))
        let rootReport = DiagnosticLogRetention.prune(documents: documentsLink, now: date("2026-05-01T00:00:00Z"))
        XCTAssertEqual(report.deletedFiles + rootReport.deletedFiles, 0)
        XCTAssertEqual(try read(target), contents)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: linkedFile.path), target.path)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: linkedDirectory.path), target.deletingLastPathComponent().path)
    }

    func testOnlyReservedAbandonedScratchFilesAreDiscarded() throws {
        let root = try root(), external = try self.root(); defer {try? fm.removeItem(at: root);try? fm.removeItem(at: external)}
        let abandoned = try file(root, name: ".retention-\(UUID().uuidString).tmp", text: "partial private diagnostic copy")
        let unknown = try file(root, name: ".retention-user-notes.tmp", text: "keep")
        let otherFolder = try file(root, folder: "Scans", name: ".retention-\(UUID().uuidString).tmp", text: "keep")
        let externalFile = try file(external, text: "keep")
        let link = abandoned.deletingLastPathComponent().appendingPathComponent(".retention-\(UUID().uuidString).tmp")
        try fm.createSymbolicLink(at: link, withDestinationURL: externalFile)
        let report = DiagnosticLogRetention.prune(documents: root)
        XCTAssertEqual(report.removedTemporaryFiles, 1)
        XCTAssertFalse(fm.fileExists(atPath: abandoned.path))
        for url in [unknown,otherFolder,externalFile] {XCTAssertEqual(try read(url), "keep")}
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link.path), externalFile.path)
    }

    func testActiveTrialIsSkippedUntilCloseAndHeaderContainsCreationTime() async throws {
        let root = try root(); defer {try? fm.removeItem(at: root)}
        let log = try TrialLog(directory: root.appendingPathComponent("Trials"), metadata: ["source":"active-test"])
        let contents = try read(log.url)
        let header = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contents.utf8)) as? [String: Any])
        XCTAssertNotNil(header["time"] as? String)
        let future = Date().addingTimeInterval(400 * 86400)
        let active = DiagnosticLogRetention.prune(documents: root, now: future)
        XCTAssertEqual(active.skippedActiveFiles, 1)
        XCTAssertEqual(try read(log.url), contents)
        let closed: URL = try await withCheckedThrowingContinuation {continuation in log.close {continuation.resume(with: $0)}}
        let completed = DiagnosticLogRetention.prune(documents: root, now: future)
        XCTAssertEqual(completed.deletedFiles, 1)
        XCTAssertFalse(fm.fileExists(atPath: closed.path))
    }

    func testClosingTrialTriggersPruningOfExpiredSiblings() async throws {
        let root = try root(); defer {try? fm.removeItem(at: root)}
        let old = try file(root, text: row("2000-01-01T00:00:00Z"))
        let active = try TrialLog(directory: root.appendingPathComponent("Trials"), metadata: [:])
        let _: URL = try await withCheckedThrowingContinuation {continuation in active.close {continuation.resume(with: $0)}}
        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: active.url.path))
    }

    func testLargeFileAndCrossChunkRowsAreRewrittenWithoutLosingRecentBytes() throws {
        let root = try root(); defer {try? fm.removeItem(at: root)}
        let old = row("2026-01-01T00:00:00Z")
        let recent = row("2026-10-01T00:00:00.001+09:00", field: "time", detail: String(repeating: "가", count: 100_000))
        let source = String(repeating: old, count: 25_000) + recent + String(repeating: old, count: 25_000)
        let url = try file(root, text: source)
        let report = DiagnosticLogRetention.prune(documents: root, now: date("2026-11-08T00:00:00Z"))
        XCTAssertEqual(report.failureCount, 0)
        XCTAssertEqual(report.removedRecords, 50_000)
        XCTAssertEqual(try read(url), recent)
    }

    func testCleanupWaitsForWriterAndPreservesItsNewlyAppendedRow() throws {
        let root = try root(); defer {try? fm.removeItem(at: root)}
        let url = try file(root, text: row("2000-01-01T00:00:00Z"))
        let recent = row("2030-01-01T00:00:00Z")
        let writerEntered = DispatchSemaphore(value: 0), releaseWriter = DispatchSemaphore(value: 0)
        let cleanupStarted = DispatchSemaphore(value: 0), cleanupFinished = DispatchSemaphore(value: 0)
        let writerFinished = expectation(description: "writer closed its file")
        DispatchQueue.global().async {
            DiagnosticLogRetention.withFileAccess {
                writerEntered.signal()
                _ = releaseWriter.wait(timeout: .now() + 5)
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    defer {try? handle.close()}
                    try handle.seekToEnd();try handle.write(contentsOf: Data(recent.utf8))
                } catch {XCTFail("writer failed: \(error)")}
            }
            writerFinished.fulfill()
        }
        XCTAssertEqual(writerEntered.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            cleanupStarted.signal()
            _ = DiagnosticLogRetention.prune(documents: root, now: self.date("2026-11-08T00:00:00Z"))
            cleanupFinished.signal()
        }
        XCTAssertEqual(cleanupStarted.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(cleanupFinished.wait(timeout: .now() + 0.05), .timedOut)
        releaseWriter.signal()
        wait(for: [writerFinished], timeout: 5)
        XCTAssertEqual(cleanupFinished.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(try read(url), recent)
    }

    func testAppendDuringStreamingIsNotBlockedOrLostAndCleanupRetriesLater() throws {
        let root = try root(); defer {try? fm.removeItem(at: root)}
        let old = row("2000-01-01T00:00:00Z"), recent = row("2030-01-01T00:00:00Z")
        let source = String(repeating: old, count: 50_000) + recent
        let url = try file(root, text: source)
        let done = expectation(description: "changed file skipped")
        let now = date("2026-11-08T00:00:00Z")
        DispatchQueue.global().async {
            let report = DiagnosticLogRetention.prune(documents: root, now: now)
            XCTAssertEqual(report.failureCount, 0)
            XCTAssertEqual(report.skippedChangedFiles, 1)
            XCTAssertEqual(report.rewrittenFiles, 0)
            done.fulfill()
        }
        // The scratch file appears only after the initial scan, while the second streaming pass runs.
        let directory = url.deletingLastPathComponent()
        let deadline = Date().addingTimeInterval(10)
        var preparingReplacement = false
        repeat {
            preparingReplacement = (try fm.contentsOfDirectory(atPath: directory.path)).contains {$0.hasPrefix(".retention-")}
            if !preparingReplacement {Thread.sleep(forTimeInterval: 0.001)}
        } while !preparingReplacement && Date() < deadline
        XCTAssertTrue(preparingReplacement, "Expected a streaming rewrite before appending")
        let appended = expectation(description: "writer remained responsive")
        let latest = row("2030-02-01T00:00:00Z")
        DispatchQueue.global().async {
            DiagnosticLogRetention.withFileAccess {
                do {
                    let handle = try FileHandle(forWritingTo: url)
                    defer {try? handle.close()}
                    try handle.seekToEnd();try handle.write(contentsOf: Data(latest.utf8))
                } catch {XCTFail("append failed: \(error)")}
            }
            appended.fulfill()
        }
        wait(for: [appended], timeout: 1)
        wait(for: [done], timeout: 10)
        XCTAssertEqual(try read(url), source + latest)
        let retry = DiagnosticLogRetention.prune(documents: root, now: now)
        XCTAssertEqual(retry.failureCount, 0)
        XCTAssertEqual(retry.rewrittenFiles, 1)
        XCTAssertEqual(try read(url), recent + latest)
        XCTAssertFalse(try fm.contentsOfDirectory(atPath: directory.path).contains {$0.hasPrefix(".retention-")})
    }

    func testWriteFailurePreservesOriginalAndReportsFailure() throws {
        let root = try root(); defer {try? fm.removeItem(at: root)}
        let source = row("2000-01-01T00:00:00Z") + row("2030-01-01T00:00:00Z")
        let url = try file(root, text: source)
        let directory = url.deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)}
        guard !fm.isWritableFile(atPath: directory.path) else {throw XCTSkip("Filesystem user bypasses directory write permissions.")}
        let report = DiagnosticLogRetention.prune(documents: root, now: date("2026-11-08T00:00:00Z"))
        XCTAssertEqual(report.failureCount, 1)
        XCTAssertEqual(report.rewrittenFiles, 0)
        XCTAssertEqual(try read(url), source)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: directory.path), [url.lastPathComponent])
    }
}
