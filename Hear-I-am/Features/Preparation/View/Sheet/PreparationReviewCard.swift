import SwiftUI
import HearIAmCore

/// Final summary and stage name before saving.
struct PreparationReviewCard: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft
        ZStack {
            Color.black.opacity(0.35)
            GeometryReader { geometry in
                let wide=geometry.size.width >= 650
                ScrollView {
                    let layout=wide ? AnyLayout(HStackLayout(spacing:24)) : AnyLayout(VStackLayout(spacing:16))
                    layout {
                PreparationMiniMap(model:model).frame(width:wide ? 260 : nil,height:160)
                VStack(alignment:.leading,spacing:12) {
                    Text("무대 정보를 확인해주세요").font(.title3.bold())
                    TextField("무대 이름",text:$model.scanName).textFieldStyle(.roundedBorder)
                    if model.nameTooLong {Text("무대 이름은 80자 이내로 입력해주세요.").font(.caption).foregroundStyle(.red)}
                    Text("경로 \(draft.route.count)점 · 기물 \(draft.objects.count)개 · 사진 \(model.session.photoSources.count)장 · 확인점 1개").font(.subheadline)
                    Text(StageDangerZone.summary(draft.dangerZones)).font(.caption).foregroundStyle(.orange)
                    if draft.errors.isEmpty {Text(model.saveRecoveryMessage ?? "저장 준비가 끝났어요.").font(.caption).foregroundStyle(.secondary)}
                    else {ScrollView {Text(Array(Set(draft.errors)).sorted().joined(separator:"\n")).font(.caption).foregroundStyle(.red)}.frame(maxHeight:70)}
                    WrappingControlsLayout {
                        ActionButton(title:model.saveRecoveryMessage != nil && !model.session.canSave ? "주변 비추기" : "돌아가기",primary:false,enabled:!model.busy) {model.review=false}
                        ActionButton(title:model.session.saveRecoveryPending ? "다시 저장하기" : "저장하기",enabled:model.canSave) {model.save()}
                    }
                }.frame(maxWidth:wide ? 350 : .infinity)
                    }.padding(24)
                }.scrollBounceBehavior(.basedOnSize)
                    .frame(maxWidth:720,maxHeight:geometry.size.height).fixedSize(horizontal:false,vertical:true)
                    .background(.regularMaterial,in:RoundedRectangle(cornerRadius:24))
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            }.padding(16)
        }
    }
}
