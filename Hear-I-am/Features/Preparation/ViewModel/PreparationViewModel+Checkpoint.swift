import HearIAmCore

/// Two ordered floor landmarks, independently replaceable before saving.
extension PreparationViewModel {
    func placeCheckpoint(_ index: Int) {
        place { draft,point in
            let errors=draft.checkpointPointErrors(point)
            guard errors.isEmpty else { throw LabError.invalid(errors.joined(separator:"\n")) }
            if index == 0 { draft.checkpoint=point } else { draft.secondCheckpoint=point }
            if draft.checkpoint != nil && draft.secondCheckpoint != nil {
                guard draft.checkpointErrors.isEmpty else {throw LabError.invalid(draft.checkpointErrors.joined(separator:"\n"))}
            }
        }
    }
}
