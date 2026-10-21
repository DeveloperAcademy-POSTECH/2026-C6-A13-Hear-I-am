import Foundation
import HearIAmCore

/// 검토·저장. Saving needs a stable world map; failures keep every input for another try.
extension PreparationViewModel {
    var nameTooLong: Bool { scanName.count>80 }
    var canSave: Bool { session.canSave && !scanName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !nameTooLong }
    var saveRecoveryMessage: String? {
        guard draft.errors.isEmpty, !busy else { return nil }
        if session.canSave {
            return session.saveRecoveryPending ? "추적과 공간 지도가 안정됐어요. 입력한 내용 그대로 다시 저장할 수 있습니다." : nil
        }
        return "무대·동선·확인점 입력은 유지됩니다. 주변의 무늬나 고정된 기물을 천천히 비춰주세요. 추적과 공간 지도가 안정되면 저장 버튼이 활성화됩니다."
    }
    var isSaving: Bool { busy && review }
    func save() { session.save(name:scanName) }
}
