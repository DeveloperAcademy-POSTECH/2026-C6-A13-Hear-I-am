import Combine
import Foundation
import UIKit
import OrientationCore

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var records: [SessionRecord] = []
    @Published private(set) var storageMessage: String?
    @Published private(set) var completionNotes: [String: String] = [:]

    private let writer = SessionArchiveWriter()
    private var saveRevision: UInt = 0
    private var pendingSave: Task<Void, Never>?
    private let fileURL: URL
    private var readFailed = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrientationHapticsLab", isDirectory: true)
            .appendingPathComponent("sessions.json")
        load()
    }

    func append(_ record: SessionRecord, completionNote: String) {
        guard !records.contains(where: { $0.id == record.id }) else { return }
        records.insert(record, at: 0)
        completionNotes[record.id.uuidString] = completionNote
        persist()
    }

    /// Replaces only an archived record with the same ID; current measurement state is never accessed.
    func reconcile(id: UUID, walk: WalkSnapshot?, completionNote: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        if let walk {
            let old = records[index]
            records[index] = SessionRecord(
                id: old.id, startedAt: old.startedAt, endedAt: old.endedAt, endReason: old.endReason,
                lastAngleDegrees: old.lastAngleDegrees, hapticEvents: old.hapticEvents, walk: walk
            )
        }
        completionNotes[id.uuidString] = completionNote
        persist()
    }

    func completionNote(for id: UUID) -> String {
        completionNotes[id.uuidString] ?? "종료 시 수신값"
    }

    var exportJSON: String {
        guard let data = try? SessionArchive.encoder().encode(SessionArchive(records: records, completionNotes: completionNotes)),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let archive = try decoder.decode(SessionArchive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            records = archive.records.sorted { $0.startedAt > $1.startedAt }
            completionNotes = archive.completionNotes.mapValues { note in
                note == "최종 걸음 조회 중" ? "종료 시 수신값 · 이전 실행의 최종 조회 미완료" : note
            }
        } catch {
            readFailed = true
            storageMessage = "이전 로그를 읽지 못했어요. 원본 파일을 보존하며, 새 기록은 이번 실행 메모리에만 보관합니다. 공유로 내보내 주세요. (\(error.localizedDescription))"
        }
    }

    /// Used when a caller needs a durable checkpoint, without blocking the UI thread.
    func flush() async {
        let task = pendingSave
        await task?.value
    }

    private func persist() {
        guard !readFailed else { return }
        saveRevision &+= 1
        let revision = saveRevision
        let archive = SessionArchive(records: records, completionNotes: completionNotes)
        let url = fileURL
        // Allow a reset/stop archive to finish if the app immediately goes to the background.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Save orientation cycle")
        pendingSave = Task { [weak self, writer] in
            let error = await writer.save(archive, to: url, revision: revision)
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            guard let self, self.saveRevision == revision else { return }
            self.storageMessage = error.map { "로그 저장 실패 · 현재 기록은 메모리에 남아 있어요. 공유로 내보내 주세요. (\($0))" }
        }
    }
}
