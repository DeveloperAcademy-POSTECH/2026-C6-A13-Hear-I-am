import HearIAmCore

/// Step 5 · 확인점. One floor point used later to verify that the saved space was restored.
extension PreparationViewModel {
    func placeCheckpoint() {
        place { draft,point in
            draft.checkpoint=point
            guard draft.checkpointErrors.isEmpty else {throw LabError.invalid(draft.checkpointErrors.joined(separator:"\n"))}
        }
    }
}
