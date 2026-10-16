import SwiftUI
import PoC4Core

/// Home: entry to preparation and guidance, plus renaming and deleting saved stages.
@MainActor
final class HomeViewModel: ObservableObject {
    @Published var preparing=false
    @Published var guiding=false
    @Published var notice: String?
    @Published var selection=LibrarySelectionState()
    @Published var renameTarget: ScanManifest?
    @Published var editedName=""
    @Published var showingRename=false
    @Published var renaming=false

    func showSettingsNotice() { notice="설정은 준비 중입니다." }

    // 이름 변경
    func startRename(_ record: ScanManifest) { renameTarget=record;editedName=record.name;showingRename=true }
    func cancelRename() { renameTarget=nil }
    var canSaveName: Bool {
        let trimmed=editedName.trimmingCharacters(in:.whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count<=80
    }
    func rename(in library: StageLibrary) {
        guard let target=renameTarget, !renaming else {return}
        let name=editedName
        renaming=true
        Task {
            defer {renaming=false;renameTarget=nil}
            do {try await library.renameStage(target.id,to:name)}
            catch {notice="이름을 변경하지 못했어요. 다시 시도해주세요. " + error.localizedDescription}
        }
    }

    // 선택 삭제
    func deleteSelected(in library: StageLibrary) {
        guard !selection.deleting else {return}
        selection.deleting=true
        let ids=selection.ids
        Task {
            var failures:[String]=[]
            for id in ids {
                do {try await library.deleteStage(id)} catch {failures.append(error.localizedDescription)}
            }
            selection.finishDeleting(remaining:Set(library.records.map(\.id)))
            if !failures.isEmpty {notice="일부 무대를 삭제하지 못했어요. 다시 시도해주세요. " + failures.joined(separator:"\n")}
        }
    }
}
