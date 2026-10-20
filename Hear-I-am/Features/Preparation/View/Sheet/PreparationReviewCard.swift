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
                VStack(alignment:.leading,spacing:12) {
                    Text("무대 정보를 확인해주세요").font(.title3.bold())
                    TextField("무대 이름",text:$model.scanName).textFieldStyle(.roundedBorder)
                    if model.nameTooLong {Text("무대 이름은 80자 이내로 입력해주세요.").font(.caption).foregroundStyle(.red)}
                    Text("경로 \(draft.route.count)점 · 기물 \(draft.objects.count)개 · 사진 \(model.session.photoSources.count)장").font(.subheadline)
                    Text(StageDangerZone.summary(draft.dangerZones)).font(.caption).foregroundStyle(.orange)
                    if draft.errors.isEmpty {Text("저장 준비가 끝났어요. 공간 지도가 안정되면 저장할 수 있습니다.").font(.caption).foregroundStyle(.secondary)}
                    else {ScrollView {Text(Array(Set(draft.errors)).sorted().joined(separator:"\n")).font(.caption).foregroundStyle(.red)}.frame(maxHeight:70)}
                    HStack {
                        ActionButton(title:"돌아가기",primary:false,enabled:!model.busy) {model.review=false}
                        ActionButton(title:"저장하기",enabled:model.canSave) {model.save()}
                    }
                }.frame(maxWidth:350)
            }.padding(24).frame(maxWidth:720,maxHeight:260).background(.regularMaterial,in:RoundedRectangle(cornerRadius:24)).padding(16)
        }
    }
}
