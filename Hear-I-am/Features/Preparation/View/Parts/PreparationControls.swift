import SwiftUI
import HearIAmCore

/// Bottom-right action buttons for the current step.
struct PreparationControls: View {
    @ObservedObject var model: PreparationViewModel
    var hasPlans=false
    var body: some View {
        let draft=model.draft
        switch model.step {
        case .scan:
            ActionButton(title:"공간 확정하기",enabled:model.canConfirmScan) {model.confirmingScan=true}
        case .boundary:
            if let last=model.lastCapturedCorner {
                ActionButton(title:"마지막 점 삭제",primary:false,enabled:!model.busy) {model.undoCorner(last)}
            }
            if let next=model.nextCorner {ActionButton(title:"모서리 지정",enabled:model.canPlacePoint) {model.captureCorner(next)}}
            if draft.area != nil {
                ActionButton(title:"위험 구역",primary:false,enabled:!model.busy) {model.editingDangerZones=true}
                if let plan=model.selectedPlan {
                    ActionButton(title:"‘\(plan.name)’ 동선 적용") {model.applyPlan(plan)}
                } else {
                    if hasPlans {
                        ActionButton(title:"사전 저장 동선 불러오기",primary:false) {model.choosingPlan=true}
                    }
                    ActionButton(title:"직접 입력") {model.advance()}
                }
            }
        case .objects:
            if model.objectEditing {
                Button("취소") {model.cancelObject()}.padding(8).background(.regularMaterial,in:Capsule())
                ActionButton(title:"마지막 점 삭제",primary:false,enabled:!model.pendingObjectWorld.isEmpty) {model.undoObjectVertex()}
                ActionButton(title:"둘레 점 추가",enabled:model.canPlacePoint && model.pendingObjectWorld.count<8) {model.addObjectVertex()}
                ActionButton(title:"기물 등록",enabled:model.pendingObjectWorld.count>=3) {model.commitObject()}
            } else {
                ActionButton(title:"기물 추가",primary:false,enabled:draft.area != nil) {model.beginObject()}
                ActionButton(title:draft.objects.isEmpty ? "건너뛰기" : "다음 단계",enabled:draft.objectErrors.isEmpty) {model.advance()}
            }
        case .route:
            if !draft.route.isEmpty {ActionButton(title:"마지막 점 삭제",primary:false) {model.undoRoutePoint()}}
            if draft.routeFinished {
                ActionButton(title:"다음 단계",enabled:draft.routeErrors.isEmpty) {model.advance()}
            } else {
                if draft.route.count<StageRoute.maxPointCount-1 {ActionButton(title:draft.route.isEmpty ? "출발점 지정" : "P\(draft.route.count) 지정",enabled:model.canPlacePoint && draft.area != nil) {model.addRoutePoint()}}
                if draft.route.count>=2 {ActionButton(title:"도착점 지정",enabled:model.canPlacePoint && draft.area != nil) {model.addRoutePoint(destination:true)}}
            }
        case .checkpoint:
            ActionButton(title:draft.checkpoint == nil ? "확인점 지정" : "다시 찍기",primary:draft.checkpoint == nil,enabled:model.canPlacePoint && draft.area != nil) {model.placeCheckpoint()}
            if draft.checkpoint != nil {ActionButton(title:"검토하기",enabled:draft.checkpointErrors.isEmpty) {model.review=true}}
        }
    }
}

/// Wrap controls at their intrinsic width; long labels receive the available row width.
struct WrappingControlsLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width:proposal.width ?? 600,subviews:subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result=arrangement(width:bounds.width,subviews:subviews)
        for (index,item) in result.items.enumerated() {
            subviews[index].place(at:CGPoint(x:bounds.minX+item.origin.x,y:bounds.minY+item.origin.y),anchor:.topLeading,
                                  proposal:ProposedViewSize(item.size))
        }
    }
    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, items: [CGRect]) {
        let width=max(1,width)
        var x: CGFloat=0, y: CGFloat=0, rowHeight: CGFloat=0
        var items: [CGRect]=[]
        for view in subviews {
            let ideal=view.sizeThatFits(.unspecified)
            let size=view.sizeThatFits(ProposedViewSize(width:min(width,ideal.width),height:nil))
            if x>0 && x+size.width>width {x=0;y+=rowHeight+spacing;rowHeight=0}
            items.append(CGRect(origin:CGPoint(x:x,y:y),size:size))
            x+=size.width+spacing;rowHeight=max(rowHeight,size.height)
        }
        return (CGSize(width:width,height:y+rowHeight),items)
    }
}
