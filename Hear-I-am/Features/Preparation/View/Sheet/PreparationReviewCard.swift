import SwiftUI
import HearIAmCore

/// Confirm the scan first. Performance and venue classification follows a durable save.
struct PreparationReviewCard: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing:24) {
                PreparationMiniMap(model:model).frame(width:260)
                VStack(alignment:.leading,spacing:12) {
                    Text("무대 정보를 확인해주세요").font(.title3.bold())
                    Text("먼저 무대를 저장한 뒤 공연과 공연장을 선택해요.").font(.subheadline).foregroundStyle(.secondary)
                    Text("경로 \(draft.route.count)점 · 기물 \(draft.objects.count)개 · 사진 \(model.session.photoSources.count)장 · 확인점 2개").font(.subheadline)
                    Text(StageDangerZone.summary(draft.dangerZones)).font(.caption).foregroundStyle(.orange)
                    if draft.errors.isEmpty {Text(model.saveRecoveryMessage ?? "저장 준비가 끝났어요.").font(.caption).foregroundStyle(.secondary)}
                    else {ScrollView {Text(Array(Set(draft.errors)).sorted().joined(separator:"\n")).font(.caption).foregroundStyle(.red)}.frame(maxHeight:70)}
                    HStack {
                        ActionButton(title:model.saveRecoveryMessage != nil && !model.session.canSave ? "주변 비추기" : "돌아가기",primary:false,enabled:!model.busy) {model.review=false}
                        ActionButton(title:model.session.saveRecoveryPending ? "다시 저장하기" : "저장하기",enabled:model.canSave) {model.save()}
                    }
                }.frame(maxWidth:350)
            }.padding(24).frame(maxWidth:720,maxHeight:320).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)).padding(16)
        }
    }
}
