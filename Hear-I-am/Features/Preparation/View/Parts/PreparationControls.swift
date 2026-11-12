import SwiftUI
import HearIAmCore

/// Bottom-centre tools of the current step, as separate 50pt glass circles 8pt apart with undo first; the row
/// as a whole sits in the middle of the screen (Figma 971:29463 · 971:28541 · 971:29061 · 971:28749).
/// Undo is drawn outlined while there is nothing to undo.
struct PreparationToolGroup: View {
    @ObservedObject var model: PreparationViewModel
    var hasPlans=false
    var body: some View {
        let draft=model.draft
        HStack(spacing:8) {
            switch model.step {
            case .scan:
                EmptyView()
            case .boundary:
                undo(enabled:model.lastCapturedCorner != nil && !model.busy) {if let last=model.lastCapturedCorner {model.undoCorner(last)}}
                // 위험 구역 and, when the performance has saved routes, 동선 불러오기 share one capsule (971:29464).
                capsule {
                    tool("exclamationmark.triangle.fill",L("위험 구역"),enabled:draft.area != nil && !model.busy) {model.editingDangerZones=true}
                    if hasPlans {
                        tool("folder.fill",model.selectedPlan == nil ? L("사전 저장 동선 불러오기") : L("참고 동선 변경"),enabled:draft.area != nil) {model.choosingPlan=true}
                    }
                }
            case .objects:
                undo(enabled:model.objectEditing && !model.pendingObjectWorld.isEmpty) {model.undoObjectVertex()}
                // The add-object symbol with a 23pt count 9pt above it: points of the object being drawn, else the
                // objects registered (971:28573).
                circle(ScanChrome.addObjectSymbol,model.objectEditing ? L("기물 입력 중, 둘레 점 %@개", model.pendingObjectWorld.count) : L("기물 추가, 등록한 기물 %@개", draft.objects.count),
                       enabled:!model.objectEditing && draft.area != nil && !model.busy) {model.beginObject()}
                    .overlay(alignment:.top) {
                        Text("\(model.objectEditing ? model.pendingObjectWorld.count : draft.objects.count)").font(HearFont.pretendard(.regular,size:14)).foregroundStyle(.white)
                            .frame(minWidth:23,minHeight:23).background(Color.black.opacity(0.4),in:Circle())
                            .offset(y:-32).accessibilityHidden(true)
                    }
            case .route:
                // Undo, the bin that clears the whole route and, rightmost, the destination flag (971:29061 plus the
                // flag, 11/07: + places the start and the points between, the flag the last point).
                undo(enabled:!draft.route.isEmpty && !model.busy) {model.undoRoutePoint()}
                circle("trash",L("동선 전체 지우기"),enabled:!draft.route.isEmpty && !model.busy) {model.resetStep()}
                circle("flag.checkered",L("도착점 지정"),enabled:!draft.routeFinished && draft.route.count>=2 && model.canPlacePoint && draft.area != nil) {model.addRoutePoint(destination:true)}
            case .checkpoint:
                undo(enabled:draft.checkpoint != nil && !model.busy) {model.undoCheckpoint()}
            }
        }
    }
    private func undo(enabled: Bool, action: @escaping () -> Void) -> some View {
        ScanCircleButton(systemImage:enabled ? "arrowshape.turn.up.backward.fill" : "arrowshape.turn.up.backward",label:L("마지막 점 삭제"),size:50,enabled:enabled,action:action)
    }
    private func circle(_ systemImage: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        ScanCircleButton(systemImage:systemImage,label:label,size:50,enabled:enabled,action:action)
    }
    /// 50pt glass capsule of 44pt tools, 10pt in from its ends (971:29465).
    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing:4) {content()}.padding(.horizontal,10).frame(height:50)
            .liquidGlass(Capsule(),tint:ScanChrome.buttonTint)
    }
    private func tool(_ systemImage: String, _ label: String, enabled: Bool=true, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Image(systemName:systemImage).font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                .frame(width:44,height:44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4).accessibilityLabel(label)
    }
}

/// Bottom right: the + that places the step's next point, 10pt left of
/// the 140pt 「지정 완료」 that finishes the step (Figma 971:28541 · 971:30334). Scanning has only 「스캔 완료」.
struct PreparationControls: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft
        HStack(spacing:10) {
            if model.step != .scan {
                ScanCircleButton(systemImage:"plus",label:plusLabel,size:50,enabled:model.canPressPlus) {model.plusPressed()}
            }
            switch model.step {
            case .scan:
                ScanPrimaryButton(title:L("스캔 완료"),enabled:model.canConfirmScan) {model.confirmingScan=true}
            case .boundary:
                ScanPrimaryButton(title:L("지정 완료"),enabled:draft.area != nil && !model.busy) {
                    if let plan=model.selectedPlan {model.selectReferencePlan(plan)} else {model.advance()}
                }
            case .objects:
                // While an object's points are being placed this registers it. With no point placed it ends the
                // step: 「건너뛰기」 while no object is registered, 「지정 완료」 once one is (11/07).
                if model.objectEditing && !model.pendingObjectWorld.isEmpty {
                    ScanPrimaryButton(title:L("지정 완료"),enabled:model.pendingObjectWorld.count>=3) {model.commitObject()}
                        .accessibilityHint(L("그린 기물을 등록해요"))
                } else {
                    ScanPrimaryButton(title:draft.objects.isEmpty ? L("건너뛰기") : L("지정 완료"),enabled:draft.objectErrors.isEmpty && !model.busy) {
                        if model.objectEditing {model.cancelObject()}
                        model.advance()
                    }.accessibilityHint(draft.objects.isEmpty ? L("기물 없이 다음 단계로 넘어가요") : L("기물 단계를 마쳐요"))
                }
            case .route:
                ScanPrimaryButton(title:L("지정 완료"),enabled:draft.routeFinished ? draft.routeErrors.isEmpty : draft.route.count>=2) {model.finishRoute()}
                    .accessibilityHint(L("마지막 점을 도착점으로 하고 경로를 마쳐요"))
            case .checkpoint:
                ScanPrimaryButton(title:L("지정 완료"),enabled:draft.checkpoint != nil && draft.checkpointErrors.isEmpty) {model.review=true}
            }
        }
    }
    private var plusLabel: String {
        let draft=model.draft
        switch model.step {
        case .scan: return ""
        case .boundary: return L("무대 %@ 모서리 지정", model.nextCorner.map {PreparationStep.cornerNames[$0]} ?? "")
        case .objects: return model.objectEditing ? L("둘레 점 추가") : L("기물 추가")
        case .route: return L("%@ 지정", draft.nextRoutePointLabel(at:model.session.aimPoint))
        case .checkpoint: return model.nextCheckpoint.map {L("확인점 %@ 지정", $0+1)} ?? L("확인점 두 개 지정됨")
        }
    }
}
