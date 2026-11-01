import SwiftUI
import HearIAmCore

/// Confirm the scan first (Figma 452:11942 「무대 정보 확정」). Performance and venue classification
/// follows a durable save, so there is no name field here. Same card as the intro: 42pt glass, 28pt padding.
struct PreparationReviewCard: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing:28) {
                PreparationMiniMap(model:model,dark:true).padding(16).frame(width:280,height:230)
                    .background(ScanChrome.illustration,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                VStack(alignment:.leading,spacing:12) {
                    Text("무대 정보 확정").font(.system(size:24,weight:.semibold)).foregroundStyle(.white)
                    Text("먼저 무대를 저장한 뒤 공연과 공연장을 선택해요.").font(.system(size:16,weight:.medium)).foregroundStyle(ScanChrome.secondary)
                    if !draft.dangerZones.isEmpty {
                        Text("위험구역 설정 완료").font(.system(size:13,weight:.semibold)).foregroundStyle(Color(red:0.42,green:0.86,blue:0.38))
                            .padding(.horizontal,10).padding(.vertical,5).background(Color(red:0.42,green:0.86,blue:0.38).opacity(0.18),in:Capsule())
                            .accessibilityLabel(StageDangerZone.summary(draft.dangerZones))
                    }
                    Text("경로 \(draft.route.count)점 / 기물 \(draft.objects.count)개 / 사진 \(model.session.photoSources.count)장 / 확인점 2개")
                        .font(.system(size:15)).foregroundStyle(.white.opacity(0.85))
                    if draft.errors.isEmpty {
                        if let message=model.saveRecoveryMessage {Text(message).font(.system(size:13)).foregroundStyle(ScanChrome.secondary)}
                    } else {
                        ScrollView {Text(Array(Set(draft.errors)).sorted().joined(separator:"\n")).font(.system(size:13)).foregroundStyle(Color(red:1,green:0.45,blue:0.45))}.frame(maxHeight:70)
                    }
                    Spacer(minLength:4)
                    HStack(spacing:6) {
                        ScanCardButton(title:model.saveRecoveryMessage != nil && !model.session.canSave ? "주변 비추기" : "돌아가기",primary:false,enabled:!model.busy) {model.review=false}
                        ScanCardButton(title:model.session.saveRecoveryPending ? "다시 저장하기" : "저장하기",enabled:model.canSave) {model.save()}
                    }
                }.frame(maxWidth:306,alignment:.leading)
            }.padding(28).frame(maxWidth:670,maxHeight:300)
                .scanCard()
                .overlay(alignment:.topTrailing) {
                    Button {model.review=false} label: {
                        Image(systemName:"xmark").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                            .frame(width:40,height:40).background(ScanChrome.close,in:Circle())
                    }.buttonStyle(.plain).padding(16).disabled(model.busy).accessibilityLabel("닫기")
                }
                .padding(16)
        }
    }
}
