import SwiftUI
import HearIAmCore

/// Confirm the scan first (Figma 452:11942 · 452:12063 「무대 정보 확정」): the plan on the left, the name field,
/// the danger-zone chip (green when set, red when not), the counts, then 돌아가기 · 저장하기.
struct PreparationReviewCard: View {
    @ObservedObject var model: PreparationViewModel
    private static let done=Color(red:48/255,green:209/255,blue:88/255)
    private static let missing=Color(red:1,green:69/255,blue:58/255)
    var body: some View {
        let draft=model.draft
        ZStack {
            Color.black.opacity(0.35)
            HStack(spacing:28) {
                PreparationMiniMap(model:model,style:.review).padding(20).frame(width:243,height:230)
                    .background(ScanChrome.illustration,in:RoundedRectangle(cornerRadius:24,style:.continuous))
                VStack(alignment:.leading,spacing:12) {
                    Text("무대 정보 확정").font(.system(size:24,weight:.semibold)).foregroundStyle(.white)
                    TextField("",text:$model.scanName,prompt:Text("공연명을 입력해주세요").foregroundStyle(.white.opacity(0.4)))
                        .font(.system(size:15)).foregroundStyle(.white).tint(.white)
                        .padding(.horizontal,14).frame(height:38)
                        .background(Color.white.opacity(0.08),in:RoundedRectangle(cornerRadius:10,style:.continuous))
                        .overlay(RoundedRectangle(cornerRadius:10,style:.continuous).stroke(.white.opacity(0.25),lineWidth:1))
                        .accessibilityLabel("공연명")
                    let zonesSet = !draft.dangerZones.isEmpty
                    Text(zonesSet ? "위험구역 설정 완료" : "위험구역 설정 미완료").font(.system(size:13,weight:.semibold))
                        .foregroundStyle(zonesSet ? Self.done : Self.missing)
                        .padding(.horizontal,10).padding(.vertical,5).background((zonesSet ? Self.done : Self.missing).opacity(0.18),in:Capsule())
                        .accessibilityLabel(zonesSet ? StageDangerZone.summary(draft.dangerZones) : "위험구역 설정 미완료")
                    Text("경로 \(draft.route.count)점 / 기물 \(draft.objects.count)개 / 사진 \(model.session.photoSources.count)장 / 확인점 \([draft.checkpoint,draft.secondCheckpoint].compactMap {$0}.count)개")
                        .font(.system(size:15)).foregroundStyle(.white.opacity(0.85))
                    if draft.errors.isEmpty {
                        if let message=model.saveRecoveryMessage {Text(message).font(.system(size:13)).foregroundStyle(ScanChrome.secondary)}
                    } else {
                        ScrollView {Text(Array(Set(draft.errors)).sorted().joined(separator:"\n")).font(.system(size:13)).foregroundStyle(Self.missing)}.frame(maxHeight:60)
                    }
                    Spacer(minLength:4)
                    HStack(spacing:6) {
                        ScanCardButton(title:model.saveRecoveryMessage != nil && !model.session.canSave ? "주변 비추기" : "돌아가기",primary:false,enabled:!model.busy) {model.review=false}
                        ScanCardButton(title:model.session.saveRecoveryPending ? "다시 저장하기" : "저장하기",enabled:model.canSave && !model.nameTooLong) {model.save()}
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
