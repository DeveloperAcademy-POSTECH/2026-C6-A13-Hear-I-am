import HearIAmCore

/// Step 2 · 무대 범위
extension PreparationViewModel {
    /// The corner the next capture fills: the one picked by name, else the first empty one in capture order.
    var nextCorner: Int? { selectedCorner ?? PreparationDraft.captureOrder.first(where:{draft.corners[$0] == nil}) }
    var lastCapturedCorner: Int? { PreparationDraft.captureOrder.last(where:{draft.corners[$0] != nil}) }
    var allCornersCaptured: Bool { draft.corners.allSatisfy {$0 != nil} }

    func captureCorner(_ index: Int) {
        guard draft.corners.indices.contains(index) else {return}
        place { draft,point in try draft.captureCorner(index,at:point) }
        selectedCorner=nil
    }
    func undoCorner(_ index: Int) {
        guard !busy, draft.corners.indices.contains(index) else {return}
        draft.corners[index]=nil; synchronize()
        selectedCorner=nil
    }
}
