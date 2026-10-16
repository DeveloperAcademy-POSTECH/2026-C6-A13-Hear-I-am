import Foundation

/// Long-press multi-selection used by the stage and plan lists before deleting.
struct LibrarySelectionState {
    var selecting=false
    var ids: Set<UUID> = []
    var confirmingDelete=false
    var deleting=false

    func contains(_ id: UUID) -> Bool { ids.contains(id) }
    mutating func begin(with id: UUID) { selecting=true; ids.insert(id) }
    mutating func toggle(_ id: UUID) { if !ids.insert(id).inserted { ids.remove(id) } }
    mutating func cancel() { selecting=false; ids=[] }
    /// After deleting, keeps only the items that still exist; selection ends when none remain.
    mutating func finishDeleting(remaining: Set<UUID>) {
        ids.formIntersection(remaining)
        selecting = !ids.isEmpty; deleting=false
    }
}
