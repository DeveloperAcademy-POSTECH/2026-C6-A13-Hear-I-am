import XCTest
@testable import HearIAmCore

final class VoiceModelCacheTests: XCTestCase {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("voice-cache-" + UUID().uuidString)
    }
    private func makeFolder(_ root: URL, _ name: String) throws -> URL {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("private vocabulary".utf8).write(to: folder.appendingPathComponent("model"))
        return folder
    }

    func testUnusedHistoricalCachesAreRemovedWithoutTouchingUnknownFiles() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let old = try makeFolder(root, "abc123"), recentFormat = try makeFolder(root, String(repeating: "a", count: 32))
        let unknown = try makeFolder(root, "manual-backup"), invalidLength = try makeFolder(root, String(repeating: "b", count: 20))
        let looseFile = root.appendingPathComponent("def"); try Data([1, 2]).write(to: looseFile)
        let cache = VoiceModelCache(root: root)
        let report = cache.cleanup()
        XCTAssertEqual(report.removed, 2); XCTAssertEqual(report.failures, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: recentFormat.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unknown.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: invalidLength.path))
        XCTAssertEqual(try Data(contentsOf: looseFile), Data([1, 2]))
    }

    func testInvalidationRejectsOldBuildButPreservesLeasedFilesUntilRelease() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = VoiceModelCache(root: root)
        var builder: VoiceModelCache.Lease? = try cache.acquire()
        let folder = try XCTUnwrap(builder).folder
        try Data([1, 2, 3]).write(to: folder.appendingPathComponent("model"))
        XCTAssertTrue(try XCTUnwrap(builder).isCurrent)
        cache.invalidate()
        XCTAssertFalse(try XCTUnwrap(builder).isCurrent)
        cache.cleanup()
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("model")), Data([1, 2, 3]))
        builder = nil
        cache.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testRecognizerLeaseOutlivesPreparedConfigurationAndAsyncCancellation() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = VoiceModelCache(root: root)
        var configuration: VoiceModelCache.Lease? = try cache.acquire()
        var recognitionTask = configuration
        let folder = try XCTUnwrap(configuration).folder
        cache.invalidate()
        configuration = nil
        cache.cleanup()
        XCTAssertNotNil(recognitionTask)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        // Cancellation requested is not completion: the task's reference remains until finished.
        recognitionTask = nil
        cache.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testOverlappingPreparationsHaveDifferentFoldersAndGenerations() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let cache = VoiceModelCache(root: root)
        let first = try cache.acquire()
        cache.invalidate()
        let second = try cache.acquire(), third = try cache.acquire()
        XCTAssertFalse(first.isCurrent); XCTAssertTrue(second.isCurrent); XCTAssertTrue(third.isCurrent)
        XCTAssertEqual(Set([first.folder, second.folder, third.folder]).count, 3)
        cache.cleanup()
        for lease in [first, second, third] { XCTAssertTrue(FileManager.default.fileExists(atPath: lease.folder.path)) }
    }

    func testSymlinkRootAndEntriesNeverDeleteOrWriteOutsideCache() throws {
        let parent = temporaryRoot(); defer { try? FileManager.default.removeItem(at: parent) }
        let outside = try makeFolder(parent, "outside"), root = parent.appendingPathComponent("cache")
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)
        let linked = VoiceModelCache(root: root)
        XCTAssertThrowsError(try linked.acquire()); XCTAssertEqual(linked.cleanup().removed, 0)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("abc"), withDestinationURL: outside)
        XCTAssertEqual(VoiceModelCache(root: root).cleanup().removed, 0)
        XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("model")), Data("private vocabulary".utf8))
    }

    func testFailedCacheRootDoesNotReplaceUserData() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        try Data("unrelated".utf8).write(to: root)
        let cache = VoiceModelCache(root: root)
        XCTAssertThrowsError(try cache.acquire()); XCTAssertEqual(cache.cleanup().removed, 0)
        XCTAssertEqual(try Data(contentsOf: root), Data("unrelated".utf8))
    }

    func testSlowRemovalDoesNotBlockInvalidationOrNewLeases() async throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let oldFolder = try makeFolder(root, "abc")
        let removing = expectation(description: "Old cache removal entered")
        let cleanupFinished = expectation(description: "Old cache removal finished")
        let finishRemoval = DispatchSemaphore(value: 0)
        let cache = VoiceModelCache(root: root, removeDirectory: { url in
            if url.lastPathComponent == "abc" {
                removing.fulfill()
                _ = finishRemoval.wait(timeout: .now() + 5)
            }
            try FileManager.default.removeItem(at: url)
        })
        let oldLease = try cache.acquire()
        DispatchQueue.global(qos: .utility).async {
            let report = cache.cleanup()
            XCTAssertEqual(report.removed, 1)
            cleanupFinished.fulfill()
        }
        await fulfillment(of: [removing], timeout: 2)
        let responsive = expectation(description: "Lease state remains available while disk removal is blocked")
        let probe = Task.detached {
            cache.invalidate()
            XCTAssertFalse(oldLease.isCurrent)
            let newLease = try cache.acquire()
            XCTAssertTrue(newLease.isCurrent)
            try Data([4, 5, 6]).write(to: newLease.folder.appendingPathComponent("model"))
            responsive.fulfill()
            return newLease
        }
        await fulfillment(of: [responsive], timeout: 1)
        finishRemoval.signal()
        let newLease = try await probe.value
        await fulfillment(of: [cleanupFinished], timeout: 2)
        cache.cleanup()
        XCTAssertEqual(try Data(contentsOf: newLease.folder.appendingPathComponent("model")), Data([4, 5, 6]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: oldLease.folder.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldFolder.path))
    }
}
