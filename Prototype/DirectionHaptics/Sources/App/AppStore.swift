import Foundation
import SwiftUI
import UIKit

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var archive = AppArchive()
    @Published var error: String?
    @Published var message: String?
    private let file: URL
    private var loadBlocked = false

    var sets: [PatternSet] { Presets.all + archive.userSets.sorted { $0.updatedAt > $1.updatedAt } }

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let isTest = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let folder = base.appendingPathComponent(isTest ? "DirectionHapticsUITests" : "DirectionHaptics", isDirectory: true)
        file = folder.appendingPathComponent("archive.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if isTest && ProcessInfo.processInfo.arguments.contains("--ui-reset") { try? FileManager.default.removeItem(at: file) }
            if FileManager.default.fileExists(atPath: file.path) {
                let decoded = try JSONDecoder().decode(AppArchive.self, from: Data(contentsOf: file))
                guard decoded.schemaVersion == 1 else { throw PatternError.invalid("지원하지 않는 저장 파일 버전입니다.") }
                archive = decoded
            }
        } catch {
            loadBlocked = true
            self.error = "기존 기록을 읽지 못했습니다. 원본 파일은 보존했습니다. \(error.localizedDescription)"
        }
    }

    private func commit(_ next: AppArchive) -> Bool {
        guard !loadBlocked else { error = "기록 파일을 읽지 못해 저장을 잠시 막았습니다. 기존 데이터를 확인해 주세요."; return false }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(next).write(to: file, options: .atomic)
            archive = next
            return true
        } catch { self.error = "저장하지 못했습니다. 다시 시도해 주세요. \(error.localizedDescription)"; return false }
    }

    @discardableResult
    func saveSet(_ draft: PatternSet, original: PatternSet, asCopy: Bool = false) -> PatternSet? {
        if let issue = draft.validationIssue { error = issue; return nil }
        var saved = draft
        if original.isBuiltIn || asCopy {
            saved = draft.userCopy(named: draft.name)
            saved.sourceID = original.id
        } else if archive.userSets.contains(where: { $0.id == original.id }) {
            saved.id = original.id
            saved.revision = original.revision + 1
            saved.isBuiltIn = false
        } else {
            saved.revision = 1
            saved.isBuiltIn = false
        }
        saved.updatedAt = Date()
        var next = archive
        next.userSets.removeAll { $0.id == saved.id }
        next.userSets.append(saved)
        guard commit(next) else { return nil }
        message = "\(saved.name) · v\(saved.revision) 저장됨"
        return saved
    }
    func toggleFavorite(_ id: UUID) {
        var next = archive
        if next.favorites.contains(id) { next.favorites.remove(id) } else { next.favorites.insert(id) }
        _ = commit(next)
    }
    func deleteSet(_ set: PatternSet) {
        guard !set.isBuiltIn else { return }
        var next = archive
        next.userSets.removeAll { $0.id == set.id }; next.favorites.remove(set.id)
        _ = commit(next)
    }
    func export(_ pattern: PatternSet, name: String) -> URL? {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try writeExport(encoder.encode(pattern), name: name + ".json")
        }
        catch { self.error = "내보내기 실패: \(error.localizedDescription)"; return nil }
    }
    private func writeExport(_ data: Data, name: String) throws -> URL {
        // Unique folders prevent a later export from changing an already-presented share item.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }
}

enum DeviceInfo {
    static var model: String {
        var system = utsname(); uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
    @MainActor static func context(_ context: StudyContext, preview: Bool) -> StudyContext {
        var result = context
        result.device = model; result.os = UIDevice.current.systemVersion; result.isPreview = preview
        return result
    }
}

struct SharedFile: Identifiable { let id = UUID(); let url: URL }
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
