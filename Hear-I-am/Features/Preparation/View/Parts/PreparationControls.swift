import SwiftUI
import HearIAmCore

/// Bottom-centre tools of the current step: undo on its own, then the step's point and option buttons
/// (Figma 452:13140 · 452:13160 · 452:13186). Undo is drawn outlined while there is nothing to undo.
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
                group {
                    tool("plus","무대 \(model.nextCorner.map {PreparationStep.cornerNames[$0]} ?? "") 모서리 지정",enabled:model.nextCorner != nil && model.canPlacePoint) {
                        if let next=model.nextCorner {model.captureCorner(next)}
                    }
                    tool("exclamationmark.triangle.fill","위험 구역",enabled:draft.area != nil && !model.busy) {model.editingDangerZones=true}
                    if hasPlans {
                        tool("folder.fill",model.selectedPlan == nil ? "사전 저장 동선 불러오기" : "참고 동선 변경",enabled:draft.area != nil) {model.choosingPlan=true}
                    }
                }
            case .objects:
                undo(enabled:model.objectEditing && !model.pendingObjectWorld.isEmpty) {model.undoObjectVertex()}
                group {
                    tool("plus","둘레 점 추가",enabled:model.objectEditing && model.canPlacePoint && model.pendingObjectWorld.count<8) {model.addObjectVertex()}
                    if model.objectEditing {
                        tool("xmark","기물 입력 취소") {model.cancelObject()}
                    } else {
                        // Figma 452:13124: the add-object symbol with the count in a 23pt chip at its top right.
                        tool(ScanChrome.addObjectSymbol,"기물 추가, 등록한 기물 \(draft.objects.count)개",enabled:draft.area != nil) {model.beginObject()}
                            .overlay(alignment:.top) {
                                Text("\(draft.objects.count)").font(.system(size:14)).foregroundStyle(.white)
                                    .frame(minWidth:23,minHeight:23).background(Color.black.opacity(0.4),in:Circle())
                                    .offset(y:-30).accessibilityHidden(true)
                            }
                    }
                }
            case .route:
                // Figma 452:13145: undo, add a point, and the bin that clears the whole route.
                undo(enabled:!draft.route.isEmpty && !model.busy) {model.undoRoutePoint()}
                group {
                    tool("plus","\(draft.nextRoutePointLabel(at:model.session.aimPoint)) 지정",
                         enabled:!draft.routeFinished && draft.route.count<StageRoute.maxPointCount-1 && model.canPlacePoint && draft.area != nil) {model.addRoutePoint()}
                    tool("flag.checkered","도착점 지정",enabled:!draft.routeFinished && draft.route.count>=2 && model.canPlacePoint && draft.area != nil) {model.addRoutePoint(destination:true)}
                    tool("trash","동선 전체 지우기",enabled:!draft.route.isEmpty && !model.busy) {model.resetStep()}
                }
            case .checkpoint:
                // Figma 452:13181 · 13178: undo and add.
                undo(enabled:draft.checkpoint != nil && !model.busy) {model.undoCheckpoint()}
                group {
                    let next: Int? = draft.checkpoint == nil ? 0 : (draft.secondCheckpoint == nil ? 1 : nil)
                    tool("plus",next.map {"확인점 \($0+1) 지정"} ?? "확인점 두 개 지정됨",enabled:next != nil && model.canPlacePoint && draft.area != nil) {
                        if let next {model.placeCheckpoint(next)}
                    }
                }
            }
        }
    }
    private func undo(enabled: Bool, action: @escaping () -> Void) -> some View {
        ScanCircleButton(systemImage:enabled ? "arrowshape.turn.up.backward.fill" : "arrowshape.turn.up.backward",label:"마지막 점 삭제",size:50,enabled:enabled,action:action)
    }
    /// 50pt glass capsule of 44pt tools, 10pt in from its ends (Figma 452:12581).
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
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

/// Bottom-right button that finishes the current step.
struct PreparationControls: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        let draft=model.draft
        switch model.step {
        case .scan:
            ScanPrimaryButton(title:"스캔 완료",enabled:model.canConfirmScan) {model.confirmingScan=true}
        case .boundary:
            ScanPrimaryButton(title:"무대 영역 확정",enabled:draft.area != nil && !model.busy) {
                if let plan=model.selectedPlan {model.selectReferencePlan(plan)} else {model.advance()}
            }
        case .objects:
            if model.objectEditing {
                ScanPrimaryButton(title:"기물 등록",enabled:model.pendingObjectWorld.count>=3) {model.commitObject()}
            } else {
                ScanPrimaryButton(title:draft.objects.isEmpty ? "건너뛰기" : "기물 확정",enabled:draft.objectErrors.isEmpty) {model.advance()}
            }
        case .route:
            ScanPrimaryButton(title:"경로 확정",enabled:draft.routeFinished && draft.routeErrors.isEmpty) {model.advance()}
        case .checkpoint:
            ScanPrimaryButton(title:"확인점 확정",enabled:draft.checkpoint != nil && draft.checkpointErrors.isEmpty) {model.review=true}
        }
    }
}
