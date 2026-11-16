import SwiftUI
import HearIAmCore

/// Right-edge panel with the floor plan and the item being checked (Figma 971:29463 · 971:28541 · 971:29061 ·
/// 971:28749). The handle folds it away (452:11435). While an object is drafted it holds the object's inputs
/// instead of the plan. Points are placed with the + beside 「지정 완료」; clearing or editing one item is in its
/// dropdown, as the design has no buttons along the panel's foot.
struct PreparationGuideCard: View {
    @ObservedObject var model: PreparationViewModel
    let maxHeight: CGFloat
    @State private var selectedObject: UUID?
    /// How far a finger has pulled the panel sideways, before it lets go. The first few points decide whether the
    /// drag is sideways (it moves the panel) or up and down (it scrolls), and that holds to the end, so a wobbly
    /// finger does not make the panel jump between the two. Letting go eases the panel back instead of snapping.
    @GestureState(resetTransaction:Transaction(animation:.snappy(duration:0.35))) private var drag=PanelDrag()
    struct PanelDrag { var x: CGFloat=0; var sideways: Bool?=nil }
    /// Figma 971:29463: the 289×237 panel runs 29pt past the screen's right edge, so 260pt of it shows.
    static let width: CGFloat=289
    static let height: CGFloat=237
    static let bleed: CGFloat=29
    /// Folded, only a 24pt strip with the handle stays on screen (452:11435).
    private static let foldedOffset: CGFloat=width-bleed-24
    var body: some View {
        // Figma 452:12618: a 289pt glass panel (radius 34, black 20%) with the 4×34 handle on its left edge.
        // Folded, the whole panel slides to the right edge and only its handle strip stays in view (452:11435);
        // unfolded it comes back as one piece, glass and contents together (452:11526). A sideways swipe
        // anywhere on it folds or unfolds it, following the finger; a tap on the handle still works (11/07).
        HStack(spacing:0) {
            // A tap, not a Button: a drag that began on a Button never reached the panel's swipe, and folded, the
            // handle is all that shows, so the panel could be pushed away but not pulled back (11/07).
            Capsule().fill(.white).frame(width:4,height:34).frame(width:22,height:64).contentShape(Rectangle())
                .onTapGesture {withAnimation(.snappy(duration:0.35)) {model.guideCollapsed.toggle()}}
                .accessibilityElement().accessibilityAddTraits(.isButton)
                .accessibilityLabel(model.guideCollapsed ? L("평면도 펼치기") : L("평면도 접기"))
                .accessibilityAction {withAnimation(.snappy(duration:0.35)) {model.guideCollapsed.toggle()}}
            VStack(spacing:10) {
                header
                ScrollView {
                    VStack(alignment:.leading,spacing:10) {
                        if model.step == .objects && model.objectEditing {objectForm}
                        else {
                            PreparationMiniMap(model:model,selectedObject:model.step == .objects ? currentObject : nil,
                                               selectedPoint:model.step == .route ? currentRoutePoint : nil).frame(height:118)
                        }
                        notes
                    }
                }.frame(maxHeight:.infinity)
            }.padding(.leading,6).padding(.trailing,14+Self.bleed).padding(.vertical,19)
                .allowsHitTesting(!model.guideCollapsed)
                .accessibilityHidden(model.guideCollapsed)
        }.frame(width:Self.width,height:min(Self.height,maxHeight))
            .background {
                Color.clear.liquidGlass(RoundedRectangle(cornerRadius:34,style:.continuous),tint:ScanChrome.panelTint)
            }
            // The whole panel, its clear gaps included, takes the swipe.
            .contentShape(RoundedRectangle(cornerRadius:34,style:.continuous))
            // Folded, the 24pt strip is narrow for a thumb at the screen's edge: a clear 30pt more to its left
            // also catches the pull.
            .background(alignment:.leading) {
                if model.guideCollapsed {Color.clear.frame(width:30).frame(maxHeight:.infinity).contentShape(Rectangle()).offset(x:-30)}
            }
            .simultaneousGesture(swipe)
            .offset(x:min(max((model.guideCollapsed ? Self.foldedOffset : 0)+drag.x,0),Self.foldedOffset))
            .environment(\.colorScheme,.dark)
    }
    /// Read in global coordinates and attached under the offset: measured in the panel's own space, the panel moving
    /// with the finger shrank each step of the drag, so it shook and sprang back (11/07).
    private var swipe: some Gesture {
        DragGesture(minimumDistance:12,coordinateSpace:.global)
            .updating($drag) {value,state,_ in
                if state.sideways == nil {state.sideways=abs(value.translation.width) > abs(value.translation.height)}
                if state.sideways == true {state.x=value.translation.width}
            }
            .onEnded {value in
                let dx=value.translation.width, flick=value.predictedEndTranslation.width
                guard abs(dx) > abs(value.translation.height)*0.7 else {return}
                let fold=model.guideCollapsed ? dx+flick*0.2 > -60 : dx+flick*0.2 > 60
                withAnimation(.snappy(duration:0.35)) {model.guideCollapsed=fold}
            }
    }

    // MARK: Header dropdowns (452:13173)
    @ViewBuilder private var header: some View {
        let draft=model.draft
        HStack {
            switch model.step {
            case .boundary:
                // Picking a corner makes + place (or replace) it; the corner shown can be cleared here, as the
                // panel's old 삭제하기 did (971:29655).
                dropdown(model.nextCorner.map {PreparationStep.cornerNames[$0]} ?? L("모서리")) {
                    ForEach(PreparationDraft.captureOrder,id:\.self) {i in
                        Button {model.selectedCorner=i} label: {
                            Label(PreparationStep.cornerNames[i],systemImage:draft.corners[i] == nil ? "circle" : "checkmark.circle.fill")
                        }
                    }
                    if let corner=model.nextCorner, draft.corners[corner] != nil {
                        Divider()
                        Button(L("%@ 지우기", PreparationStep.cornerNames[corner]),role:.destructive) {model.undoCorner(corner)}.disabled(model.busy)
                    }
                }
            case .objects:
                if model.objectEditing {
                    Text(model.editingObjectID == nil ? L("새 기물 · %@/8점", model.pendingObjectWorld.count) : L("기물 수정 · %@/8점", model.pendingObjectWorld.count))
                        .font(HearFont.pretendard(.semibold,size:16))
                } else if draft.objects.isEmpty {
                    Text(L("등록한 기물 없음")).font(HearFont.pretendard(.semibold,size:16))
                } else {
                    let index=draft.objects.firstIndex {$0.id == currentObject} ?? 0
                    let object=draft.objects[index]
                    dropdown(L("%@번 %@", index+1, object.name)) {
                        ForEach(Array(draft.objects.enumerated()),id:\.element.id) {i,o in
                            Button(L("%@번 %@ · %@%@", i+1, o.name, o.kind.defaultName, o.height.map {" · \(Int(($0*100).rounded()))cm"} ?? "")) {selectedObject=o.id}
                        }
                        // The panel's old 수정하기 · 삭제하기 for the object shown (971:28720).
                        Divider()
                        Button(L("%@번 %@ 수정하기", index+1, object.name),systemImage:"pencil") {model.beginObject(object.id)}.disabled(model.busy)
                        Button(L("%@번 %@ 삭제하기", index+1, object.name),systemImage:"trash",role:.destructive) {model.deleteObject(object.id)}.disabled(model.busy)
                    }
                    // The edge a chair or stairs faces, as 「2→4」 (452:11604).
                    if object.kind == .platform || object.kind == .stairs {
                        let count=object.vertices.count
                        dropdown(object.facingEdge.map {"\($0+1)→\(($0+1)%count+1)"} ?? L("방향")) {
                            Button(L("선택 안 함")) {model.setFacingEdge(nil,of:object.id)}
                            ForEach(0..<count,id:\.self) {i in Button(L("변 %@→%@", i+1, (i+1)%count+1)) {model.setFacingEdge(i,of:object.id)}}
                        }
                    }
                }
            case .route:
                if draft.route.isEmpty {
                    Text(L("경로 0/%@점", StageRoute.maxPointCount)).font(HearFont.pretendard(.semibold,size:16))
                } else {
                    let labels=draft.routePointLabels
                    dropdown(labels.indices.contains(currentRoutePoint) ? labels[currentRoutePoint] : "P\(currentRoutePoint)") {
                        ForEach(labels.indices,id:\.self) {i in Button(labels[i]) {model.selectedRoutePoint=i}}
                    }
                }
            case .checkpoint:
                // Picking one makes + place (or replace) it; the one shown can be cleared here (971:28830).
                let shown=model.nextCheckpoint ?? 1
                dropdown(L("확인점 %@", shown+1)) {
                    Button(L("확인점 1")) {model.selectedCheckpoint=0}
                    Button(L("확인점 2")) {model.selectedCheckpoint=1}.disabled(draft.checkpoint == nil)
                    if shown == 0 ? draft.checkpoint != nil : draft.secondCheckpoint != nil {
                        Divider()
                        Button(L("확인점 %@ 지우기", shown+1),role:.destructive) {model.removeCheckpoint(shown);model.selectedCheckpoint=nil}.disabled(model.busy)
                    }
                }
            case .scan:
                EmptyView()
            }
            Spacer(minLength:0)
            // ↺ clears the step's input (452:13161).
            Button {model.resetStep()} label: {
                Image(systemName:"arrow.counterclockwise").font(.system(size:14,weight:.semibold)).foregroundStyle(.white)
                    .frame(width:32,height:32).background(ScanChrome.panelTint,in:Circle())
            }.buttonStyle(.plain).disabled(model.busy || !canReset).opacity(canReset ? 1 : 0.4)
                .accessibilityLabel(L("%@ 초기화", model.step.title))
        }
    }
    private var canReset: Bool {
        let draft=model.draft
        switch model.step {
        case .scan: return false
        case .boundary: return draft.corners.contains {$0 != nil}
        case .objects: return model.objectEditing ? !model.pendingObjectWorld.isEmpty : !draft.objects.isEmpty
        case .route: return !draft.route.isEmpty
        case .checkpoint: return draft.checkpoint != nil
        }
    }
    private var currentRoutePoint: Int {
        let count=model.draft.route.count
        guard count > 0 else {return 0}
        return min(model.selectedRoutePoint ?? count-1,count-1)
    }
    private func dropdown<Items: View>(_ title: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {items()} label: {
            HStack(spacing:4) {Text(title).lineLimit(1);Image(systemName:"chevron.down").font(.system(size:12,weight:.semibold))}
                .font(HearFont.pretendard(.semibold,size:16)).foregroundStyle(.white)
                .padding(.horizontal,12).frame(height:32).background(ScanChrome.panelTint,in:Capsule())
        }
    }
    private var currentObject: UUID? {
        let objects=model.draft.objects
        return objects.contains {$0.id == selectedObject} ? selectedObject : objects.first?.id
    }

    // MARK: Errors and short notes kept from the old guide card
    @ViewBuilder private var notes: some View {
        let draft=model.draft
        VStack(alignment:.leading,spacing:4) {
            if model.step == .boundary {
                if draft.area != nil, !draft.dangerZones.isEmpty {
                    Text(StageDangerZone.summary(draft.dangerZones)).foregroundStyle(.orange)
                }
                if model.allCornersCaptured, let error=draft.boundaryErrors.first {Text(error).foregroundStyle(ScanChrome.danger)}
            }
            if model.step == .objects, !model.objectEditing, let error=draft.objectErrors.first {Text(error).foregroundStyle(ScanChrome.danger)}
            if model.step == .route, draft.routeFinished, let error=draft.routeErrors.first {Text(error).foregroundStyle(ScanChrome.danger)}
            if model.step == .route, !draft.dangerZoneRoutePointLabels.isEmpty {
                Text(L("주의: %@ 위험 구역 포함", draft.dangerZoneRoutePointLabels.joined(separator:" · "))).foregroundStyle(.orange)
            }
            if model.step == .checkpoint, draft.checkpoint != nil, let error=draft.checkpointErrors.first {Text(error).foregroundStyle(ScanChrome.danger)}
        }.font(.caption).fixedSize(horizontal:false,vertical:true)
    }

    // MARK: Object inputs, as in the old guide card
    private var objectForm: some View {
        VStack(alignment:.leading,spacing:8) {
            TextField(L("기물 이름"),text:$model.obstacleName).textFieldStyle(.roundedBorder).font(.caption)
            Picker(L("종류"),selection:$model.obstacleKind) {Text(L("기물")).tag(ObstacleKind.other); Text(L("의자")).tag(ObstacleKind.platform); Text(L("계단")).tag(ObstacleKind.stairs)}.pickerStyle(.segmented)
                // The kind is fixed once a vertex is placed; undo every vertex to change it.
                .disabled(!model.pendingObjectWorld.isEmpty)
            if (model.obstacleKind == .platform || model.obstacleKind == .stairs), model.pendingObjectWorld.count >= 3 {
                let count=model.pendingObjectWorld.count
                Menu {
                    Button(L("선택 안 함")) {model.facingEdge=nil;model.synchronize()}
                    ForEach(0..<count,id:\.self) {i in
                        Button(L("변 %@ · %@→%@", i+1, i+1, (i+1)%count+1)) {model.facingEdge=i;model.synchronize()}
                    }
                } label: {
                    HStack(spacing:6) {
                        Text(model.facingEdge.map {L("바라볼 변 %@→%@", $0+1, ($0+1)%count+1)} ?? L("바라볼 변 선택"))
                        Image(systemName:"chevron.down").font(.system(size:11,weight:.semibold))
                    }.font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal,10).frame(height:30).background(Color.white.opacity(0.16),in:Capsule())
                }.accessibilityValue(model.facingEdge.map {L("변 %@", $0+1)} ?? L("선택 안 됨"))
                Text(L("도착한 뒤 바라볼 변이에요. 둘레 점을 바꾸면 선택이 지워져요.")).font(.caption2).foregroundStyle(.secondary)
            }
            if model.obstacleKind != .platform && model.obstacleKind != .stairs {
                Picker(L("다시보기 모형"),selection:$model.objectModel) {
                    ForEach(ObjectAppearance.Model.allCases,id:\.self) {Text($0.title).tag($0)}
                }.font(.caption)
                Picker(L("정면 방향"),selection:$model.objectHeading) {
                    Text(L("관객 쪽")).tag(0.0);Text(L("오른쪽")).tag(90.0);Text(L("뒤쪽")).tag(180.0);Text(L("왼쪽")).tag(270.0)
                }.font(.caption)
            }
            if let note=model.objectHeightNote {Text(note).font(.caption).foregroundStyle(.secondary)}
        }
    }
}
