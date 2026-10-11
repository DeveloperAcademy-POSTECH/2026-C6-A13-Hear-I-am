import Foundation
import OrientationCore
import XCTest
@testable import OrientationHapticsLab

@MainActor
final class SessionStoreTests: XCTestCase {
    func testAppendPersistsAndReloadsNewestFirstWithoutLosingRecordFields() async throws {
        try await withTemporaryArchive { url in
            let older = record(startOffset: 0)
            let newer = record(startOffset: 100)
            let store = SessionStore(fileURL: url)
            XCTAssertTrue(store.records.isEmpty)
            XCTAssertNil(store.storageMessage)
            store.append(older, completionNote: "이전 사이클 완료")
            await store.flush()
            store.append(newer, completionNote: "현재 사이클 완료")
            await store.flush()
            XCTAssertNil(store.storageMessage)
            let reloaded = SessionStore(fileURL: url)
            XCTAssertEqual(reloaded.records, [newer, older])
            XCTAssertEqual(reloaded.completionNote(for: older.id), "이전 사이클 완료")
            XCTAssertEqual(reloaded.completionNote(for: newer.id), "현재 사이클 완료")
            XCTAssertNil(reloaded.storageMessage)
        }
    }

    func testDuplicateAppendDoesNotReplaceAnExistingRecordOrItsNote() async throws {
        try await withTemporaryArchive { url in
            let original = record(startOffset: 0)
            let duplicate = record(id: original.id, startOffset: 100)
            let store = SessionStore(fileURL: url)
            store.append(original, completionNote: "원래 기록")
            await store.flush()
            store.append(duplicate, completionNote: "중복 기록")
            await store.flush()
            XCTAssertEqual(store.records, [original])
            XCTAssertEqual(store.completionNote(for: original.id), "원래 기록")
            XCTAssertEqual(SessionStore(fileURL: url).records, [original])
        }
    }

    func testLateFinalReconciliationChangesOnlyMatchingArchivedCycle() async throws {
        try await withTemporaryArchive { url in
            let older = record(startOffset: 0)
            let newer = record(startOffset: 100)
            let store = SessionStore(fileURL: url)
            store.append(older, completionNote: "최종 걸음 조회 중")
            await store.flush()
            store.append(newer, completionNote: "새 사이클 기록")
            await store.flush()
            let finalWalk = WalkSnapshot(
                steps: 7, estimatedDistance: 4.6, forwardDisplacement: 4.1,
                rightDisplacement: -0.5, source: .systemEstimate, isDisplacementUncertain: true
            )
            store.reconcile(id: older.id, walk: finalWalk, completionNote: "최종 걸음 조회 완료")
            await store.flush()
            let corrected = try XCTUnwrap(store.records.first { $0.id == older.id })
            XCTAssertEqual(corrected.walk, finalWalk)
            XCTAssertEqual(corrected.startedAt, older.startedAt)
            XCTAssertEqual(corrected.endedAt, older.endedAt)
            XCTAssertEqual(corrected.endReason, older.endReason)
            XCTAssertEqual(corrected.lastAngleDegrees, older.lastAngleDegrees)
            XCTAssertEqual(corrected.hapticEvents, older.hapticEvents)
            XCTAssertEqual(store.records.first { $0.id == newer.id }, newer)
            XCTAssertEqual(store.completionNote(for: newer.id), "새 사이클 기록")
            let reloaded = SessionStore(fileURL: url)
            XCTAssertEqual(reloaded.records, store.records)
            XCTAssertEqual(reloaded.completionNote(for: older.id), "최종 걸음 조회 완료")
        }
    }

    func testMissingFinalWalkOnlyChangesNoteAndUnknownIDDoesNothing() async throws {
        try await withTemporaryArchive { url in
            let original = record(startOffset: 0)
            let store = SessionStore(fileURL: url)
            store.append(original, completionNote: "최종 걸음 조회 중")
            await store.flush()
            store.reconcile(id: original.id, walk: nil, completionNote: "최종 조회 불가 · 종료 시 수신값")
            await store.flush()
            XCTAssertEqual(store.records, [original])
            XCTAssertEqual(store.completionNote(for: original.id), "최종 조회 불가 · 종료 시 수신값")
            let savedBeforeUnknownID = try Data(contentsOf: url)
            let notesBeforeUnknownID = store.completionNotes
            store.reconcile(id: UUID(), walk: .init(steps: 999), completionNote: "다른 사이클")
            await store.flush()
            XCTAssertEqual(store.records, [original])
            XCTAssertEqual(store.completionNotes, notesBeforeUnknownID)
            XCTAssertEqual(try Data(contentsOf: url), savedBeforeUnknownID)
            let reloaded = SessionStore(fileURL: url)
            XCTAssertEqual(reloaded.records, [original])
            XCTAssertEqual(reloaded.completionNote(for: original.id), "최종 조회 불가 · 종료 시 수신값")
        }
    }

    func testCorruptArchiveIsPreservedWhileNewRecordsRemainExportable() async throws {
        try await withTemporaryArchive { url in
            let corrupt = Data("original unreadable archive".utf8)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try corrupt.write(to: url)
            let store = SessionStore(fileURL: url)
            XCTAssertTrue(store.records.isEmpty)
            XCTAssertNotNil(store.storageMessage)
            let newRecord = record(startOffset: 100)
            store.append(newRecord, completionNote: "이번 실행 기록")
            await store.flush()
            store.reconcile(id: newRecord.id, walk: .init(steps: 7), completionNote: "최종 조회 완료")
            await store.flush()
            XCTAssertEqual(store.records.count, 1)
            XCTAssertEqual(store.records.first?.walk.steps, 7)
            XCTAssertEqual(try Data(contentsOf: url), corrupt, "Unreadable original must never be overwritten.")
            let json = try XCTUnwrap(store.exportJSON.data(using: .utf8))
            let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let records = try XCTUnwrap(archive["records"] as? [[String: Any]])
            XCTAssertEqual(records.count, 1)
            XCTAssertEqual(records.first?["id"] as? String, newRecord.id.uuidString)
        }
    }

    func testFutureArchiveSchemaIsPreservedAndReported() async throws {
        try await withTemporaryArchive { url in
            let payload = Data(#"{"version":999,"records":[],"completionNotes":{}}"#.utf8)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try payload.write(to: url)
            let store = SessionStore(fileURL: url)
            XCTAssertTrue(store.records.isEmpty)
            XCTAssertNotNil(store.storageMessage)
            store.append(record(startOffset: 0), completionNote: "메모리 기록")
            await store.flush()
            XCTAssertEqual(store.records.count, 1)
            XCTAssertEqual(try Data(contentsOf: url), payload)
        }
    }

    func testReloadMarksAnInterruptedFinalQueryAsUnfinished() async throws {
        try await withTemporaryArchive { url in
            let original = record(startOffset: 0)
            let store = SessionStore(fileURL: url)
            store.append(original, completionNote: "최종 걸음 조회 중")
            await store.flush()
            let reloaded = SessionStore(fileURL: url)
            XCTAssertEqual(reloaded.records, [original])
            XCTAssertEqual(reloaded.completionNote(for: original.id), "종료 시 수신값 · 이전 실행의 최종 조회 미완료")
        }
    }

    private func withTemporaryArchive(_ body: (URL) async throws -> Void) async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrientationHapticsLabTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Nested path also verifies that the store creates its archive directory.
        try await body(directory.appendingPathComponent("archive", isDirectory: true).appendingPathComponent("sessions.json"))
    }

    private func record(id: UUID = UUID(), startOffset: TimeInterval) -> SessionRecord {
        // Whole-second dates round-trip exactly through the production ISO-8601 encoder.
        let start = Date(timeIntervalSince1970: 1_700_000_000 + startOffset)
        return SessionRecord(
            id: id, startedAt: start, endedAt: start.addingTimeInterval(12), endReason: .reset,
            lastAngleDegrees: -30,
            hapticEvents: [.init(
                date: start.addingTimeInterval(10), headingDegrees: -29.5,
                triggerAngleDegrees: -30, patternID: "directional"
            )],
            walk: .init(
                steps: 5, estimatedDistance: 3.25, forwardDisplacement: 3.2,
                rightDisplacement: -0.2, source: .strideEstimate, isDisplacementUncertain: false
            )
        )
    }
}
