import SwiftUI
import HearIAmCore

/// Final summary and stage name before saving.
struct PreparationReviewCard: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing:24) {
                PreparationMiniMap(model:model).frame(width:260)
                ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text(model.isBaseRegistration ? "기본 공간을 확인해주세요" : "무대 정보를 확인해주세요").font(.title3.bold())
                    TextField("무대 이름",text:$model.scanName).textFieldStyle(.roundedBorder)
                    if model.nameTooLong {Text("무대 이름은 80자 이내로 입력해주세요.").font(.caption).foregroundStyle(.red)}
                    if model.isBaseRegistration {
                        TextField("확인점 설명 (예: 입구 오른쪽 고정 표식)",text:$model.checkpointNote).textFieldStyle(.roundedBorder)
                        if model.checkpointNote.count>160 {Text("확인점 설명은 160자 이내로 입력해주세요.").font(.caption).foregroundStyle(.red)}
                        Text("새 버전으로 저장됩니다. 이전 기본 공간과 공연은 유지돼요.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("경로 \(draft.route.count)점 · 기물 \(draft.objects.count)개 · 사진 \(model.session.photoSources.count)장 · 확인점 1개").font(.subheadline)
                    Text(StageDangerZone.summary(draft.dangerZones)).font(.caption).foregroundStyle(.orange)
                    if model.preparationErrors.isEmpty {Text(model.saveRecoveryMessage ?? "저장 준비가 끝났어요.").font(.caption).foregroundStyle(.secondary)}
                    else {ScrollView {Text(Array(Set(model.preparationErrors)).sorted().joined(separator:"\n")).font(.caption).foregroundStyle(.red)}.frame(maxHeight:70)}
                    HStack {
                        ActionButton(title:model.saveRecoveryMessage != nil && !model.session.canSave ? "주변 비추기" : "돌아가기",primary:false,enabled:!model.busy) {model.review=false}
                        ActionButton(title:model.session.saveRecoveryPending ? "다시 저장하기" : "저장하기",enabled:model.canSave) {model.save()}
                    }
                }.frame(maxWidth:.infinity,alignment:.leading)
                }.frame(maxWidth:350)
            }.padding(24).frame(maxWidth:720,maxHeight:320).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)).padding(16)
        }
    }
}
