import SwiftUI
import PoC4Core

/// 공연 사전 저장 목록: opening the editor and deleting selected plans.
@MainActor
final class PlanLibraryViewModel: ObservableObject {
    @Published var editing: PerformancePlan?
    @Published var selection=LibrarySelectionState()

    func create() { editing=PerformancePlan() }
    func open(_ plan: PerformancePlan) { editing=plan }
    func deleteSelected(in library: StageLibrary) {
        guard !selection.deleting else {return}
        selection.deleting=true
        let ids=selection.ids
        Task {
            var failures:[String]=[]
            for id in ids {
                do {try await library.deletePlan(id)} catch {failures.append(error.localizedDescription)}
            }
            selection.finishDeleting(remaining:Set(library.plans.map(\.id)))
            if !failures.isEmpty {library.error="일부 공연 동선을 삭제하지 못했어요. 다시 시도해주세요. " + failures.joined(separator:"\n")}
        }
    }
}
