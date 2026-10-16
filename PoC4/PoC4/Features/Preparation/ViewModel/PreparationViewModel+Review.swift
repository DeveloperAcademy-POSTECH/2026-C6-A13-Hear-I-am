import Foundation
import PoC4Core

/// 검토·저장. Saving needs a stable world map; failures keep every input for another try.
extension PreparationViewModel {
    var nameTooLong: Bool { scanName.count>80 }
    var canSave: Bool { session.canSave && !scanName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !nameTooLong }
    var isSaving: Bool { busy && review }
    func save() { session.save(name:scanName) }
}
