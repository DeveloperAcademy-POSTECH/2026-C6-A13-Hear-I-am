import SwiftUI
import HearIAmCore

/// Right-edge panel with the floor plan and the item being checked (Figma 452:12580 · 452:11526 ·
/// 452:11633). The handle folds it away (452:11435). While an object is drafted it holds the
/// object's inputs instead of a list.
struct PreparationGuideCard: View {
    @ObservedObject var model: PreparationViewModel
    let maxHeight: CGFloat
    @State private var selectedObject: UUID?
    @State private var selectedCheckpoint=0
    var body: some View {
        // Figma 452:12618: a 289pt glass panel (radius 34, black 20%) with the 4×34 handle on its left edge.
        HStack(spacing:0) {
            Button {withAnimation(.snappy) {model.guideCollapsed.toggle()}} label: {
                Capsule().fill(.white).frame(width:4,height:34).frame(width:22,height:64).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(model.guideCollapsed ? "평면도 펼치기" : "평면도 접기")
            if !model.guideCollapsed {
                VStack(spacing:10) {
                    header
                    ScrollView {
                        VStack(alignment:.leading,spacing:10) {
                            if model.step == .objects && model.objectEditing {objectForm}
                            else {PreparationMiniMap(model:model,dark:true).frame(height:100)}
                            notes
                        }
                    }.frame(maxHeight:max(80,maxHeight-110))
                    footer
                }.padding(.leading,6).padding(.trailing,22).padding(.vertical,19)
            }
        }.frame(width:model.guideCollapsed ? nil : 289)
            .liquidGlass(RoundedRectangle(cornerRadius:34,style:.continuous),tint:model.guideCollapsed ? ScanChrome.buttonTint : ScanChrome.panelTint)
            .environment(\.colorScheme,.dark)
    }

    // MARK: Header dropdowns (452:13173)
    @ViewBuilder private var header: some View {
        let draft=model.draft
        HStack {
            switch model.step {
            case .boundary:
                dropdown(model.nextCorner.map {PreparationStep.cornerNames[$0]} ?? "모서리") {
                    ForEach(PreparationDraft.captureOrder,id:\.self) {i in
                        Button {model.selectedCorner=i} label: {
                            Label(PreparationStep.cornerNames[i],systemImage:draft.corners[i] == nil ? "circle" : "checkmark.circle.fill")
                        }
                    }
                }
            case .objects:
                if model.objectEditing {
                    Text(model.editingObjectID == nil ? "새 기물 · \(model.pendingObjectWorld.count)/8점" : "기물 수정 · \(model.pendingObjectWorld.count)/8점")
                        .font(.system(size:16,weight:.semibold))
                } else if draft.objects.isEmpty {
                    Text("등록한 기물 없음").font(.system(size:16,weight:.semibold))
                } else {
                    let index=draft.objects.firstIndex {$0.id == currentObject} ?? 0
                    dropdown("\(index+1)번 \(draft.objects[index].name)") {
                        ForEach(Array(draft.objects.enumerated()),id:\.element.id) {i,o in
                            Button("\(i+1)번 \(o.name) · \(o.kind.defaultName)\(o.height.map {" · \(Int(($0*100).rounded()))cm"} ?? "")") {selectedObject=o.id}
                        }
                    }
                }
            case .route:
                Text("경로 \(draft.route.count)/\(StageRoute.maxPointCount)점").font(.system(size:16,weight:.semibold))
            case .checkpoint:
                dropdown("확인점 \(selectedCheckpoint+1)") {
                    Button("확인점 1") {selectedCheckpoint=0}
                    Button("확인점 2") {selectedCheckpoint=1}.disabled(draft.checkpoint == nil)
                }
            case .scan:
                EmptyView()
            }
            Spacer(minLength:0)
        }
    }
    private func dropdown<Items: View>(_ title: String, @ViewBuilder items: () -> Items) -> some View {
        Menu {items()} label: {
            HStack(spacing:4) {Text(title).lineLimit(1);Image(systemName:"chevron.down").font(.system(size:12,weight:.semibold))}
                .font(.system(size:16,weight:.semibold)).foregroundStyle(.white)
                .padding(.horizontal,12).frame(height:32).background(ScanChrome.panelTint,in:Capsule())
        }
    }
    private var currentObject: UUID? {
        let objects=model.draft.objects
        return objects.contains {$0.id == selectedObject} ? selectedObject : objects.first?.id
    }

    // MARK: Footer (삭제하기 · 수정하기)
    @ViewBuilder private var footer: some View {
        let draft=model.draft
        switch model.step {
        case .boundary:
            if let corner=model.nextCorner {
                HStack(spacing:6) {
                    ScanCardButton(title:"삭제하기",primary:false,destructive:true,enabled:draft.corners[corner] != nil && !model.busy,compact:true) {model.undoCorner(corner)}
                    ScanCardButton(title:draft.corners[corner] == nil ? "지정하기" : "수정하기",enabled:model.canPlacePoint,compact:true) {model.captureCorner(corner)}
                }
            }
        case .objects:
            if !model.objectEditing, let id=currentObject {
                HStack(spacing:6) {
                    ScanCardButton(title:"삭제하기",primary:false,destructive:true,enabled:!model.busy,compact:true) {model.deleteObject(id)}
                    ScanCardButton(title:"수정하기",enabled:!model.busy,compact:true) {model.beginObject(id)}
                }
            }
        case .checkpoint:
            let set=selectedCheckpoint == 0 ? draft.checkpoint != nil : draft.secondCheckpoint != nil
            ScanCardButton(title:set ? "다시 찍기" : "지정하기",enabled:model.canPlacePoint && draft.area != nil && (selectedCheckpoint == 0 || draft.checkpoint != nil),compact:true) {
                model.placeCheckpoint(selectedCheckpoint)
            }
        case .scan,.route:
            EmptyView()
        }
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
                Text("주의: \(draft.dangerZoneRoutePointLabels.joined(separator:" · ")) 위험 구역 포함").foregroundStyle(.orange)
            }
            if model.step == .checkpoint, draft.checkpoint != nil, let error=draft.checkpointErrors.first {Text(error).foregroundStyle(ScanChrome.danger)}
        }.font(.caption).fixedSize(horizontal:false,vertical:true)
    }

    // MARK: Object inputs, as in the old guide card
    private var objectForm: some View {
        VStack(alignment:.leading,spacing:8) {
            TextField("기물 이름",text:$model.obstacleName).textFieldStyle(.roundedBorder).font(.caption)
            Picker("종류",selection:$model.obstacleKind) {Text("기물").tag(ObstacleKind.other); Text("의자").tag(ObstacleKind.platform); Text("계단").tag(ObstacleKind.stairs)}.pickerStyle(.segmented)
            if (model.obstacleKind == .platform || model.obstacleKind == .stairs), model.pendingObjectWorld.count >= 3 {
                let count=model.pendingObjectWorld.count
                Menu {
                    Button("선택 안 함") {model.facingEdge=nil;model.synchronize()}
                    ForEach(0..<count,id:\.self) {i in
                        Button("변 \(i+1) · \(i+1)→\((i+1)%count+1)") {model.facingEdge=i;model.synchronize()}
                    }
                } label: {
                    HStack(spacing:6) {
                        Text(model.facingEdge.map {"바라볼 변 \($0+1)→\(($0+1)%count+1)"} ?? "바라볼 변 선택")
                        Image(systemName:"chevron.down").font(.system(size:11,weight:.semibold))
                    }.font(.caption.bold()).foregroundStyle(.white)
                        .padding(.horizontal,10).frame(height:30).background(Color.white.opacity(0.16),in:Capsule())
                }.accessibilityValue(model.facingEdge.map {"변 \($0+1)"} ?? "선택 안 됨")
                Text("도착한 뒤 바라볼 변이에요. 둘레 점을 바꾸면 선택이 지워져요.").font(.caption2).foregroundStyle(.secondary)
            }
            if model.obstacleKind != .platform && model.obstacleKind != .stairs {
                Picker("다시보기 모형",selection:$model.objectModel) {
                    ForEach(ObjectAppearance.Model.allCases,id:\.self) {Text($0.title).tag($0)}
                }.font(.caption)
                Picker("정면 방향",selection:$model.objectHeading) {
                    Text("관객 쪽").tag(0.0);Text("오른쪽").tag(90.0);Text("뒤쪽").tag(180.0);Text("왼쪽").tag(270.0)
                }.font(.caption)
            }
            if let note=model.objectHeightNote {Text(note).font(.caption).foregroundStyle(.secondary)}
        }
    }
}
