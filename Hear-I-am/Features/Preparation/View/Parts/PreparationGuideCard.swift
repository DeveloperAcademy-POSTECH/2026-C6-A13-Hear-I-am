import SwiftUI
import HearIAmCore

/// Collapsible instructions for the current step, with the step's inline inputs.
struct PreparationGuideCard: View {
    @ObservedObject var model: PreparationViewModel
    let maxHeight: CGFloat
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text("STEP \(model.step.rawValue+1)").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Button {model.intro=0} label:{Image(systemName:"questionmark.circle")}.accessibilityLabel("단계 안내 다시 보기")
                Button {model.guideCollapsed.toggle()} label:{Image(systemName:model.guideCollapsed ? "chevron.down" : "chevron.up")}.accessibilityLabel(model.guideCollapsed ? "안내 펼치기" : "안내 접기")
            }.padding(12)
            if !model.guideCollapsed {
                ScrollView {content}.frame(maxHeight:maxHeight)
            }
        }
    }
    private var content: some View {
        let draft=model.draft, step=model.step, guide=model.guide
        return VStack(alignment:.leading,spacing:8) {
            Text(guide.title).font(.system(size:19,weight:.bold))
            Text(guide.description).font(.system(size:12)).foregroundStyle(.secondary)
            if step == .scan {
                if model.supportsMesh {
                    Text("\(model.meshCount)개 표면 · \(model.mapping)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Pro의 LiDAR 센서를 사용해야 정확하게 측정 가능합니다 · \(model.mapping)").font(.caption).foregroundStyle(.orange)
                }
            }
            if step <= .objects && model.supportsMesh {
                Toggle("스캔 범위 표시",isOn:$model.showMesh).font(.caption).tint(.hearGreen)
            }
            if step == .boundary {
                HStack(spacing:5) {ForEach(PreparationDraft.captureOrder,id:\.self) {i in
                    Button(PreparationStep.cornerNames[i]) {model.selectedCorner=i}.font(.system(size:10)).buttonStyle(.bordered).tint(model.selectedCorner == i ? .hearGreen : .gray)
                }}
                if draft.area != nil {
                    Text("‘위험 구역’에서 변과 거리(0.5m/1m)를 선택할 수 있어요.").font(.caption)
                    Text(StageDangerZone.summary(draft.dangerZones)).font(.caption).foregroundStyle(.orange)
                }
                if model.allCornersCaptured, let error=draft.boundaryErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
            }
            if step == .objects {
                if model.objectEditing {
                    TextField("기물 이름",text:$model.obstacleName).textFieldStyle(.roundedBorder).font(.caption)
                    Picker("종류",selection:$model.obstacleKind) {Text("장애물").tag(ObstacleKind.other); Text("의자").tag(ObstacleKind.platform); Text("계단").tag(ObstacleKind.stairs)}.pickerStyle(.segmented)
                    if (model.obstacleKind == .platform || model.obstacleKind == .stairs), model.pendingObjectWorld.count >= 3 {
                        Text("변 번호는 둘레 점 순서입니다. 복수 선택 가능하며, 같은 변에 올라감·내려감을 모두 허용할 수 있어요. 미선택 측면은 통과 금지입니다. 둘레 점을 바꾸면 선택이 초기화됩니다.").font(.caption)
                        ForEach(0..<model.pendingObjectWorld.count,id:\.self) { i in
                            HStack {
                                Text("변 \(i+1) · \(i+1)→\((i+1)%model.pendingObjectWorld.count+1)").font(.caption)
                                edgeButton("올라감",selected:model.entryEdges.contains(i),color:.blue) {
                                    if !model.entryEdges.insert(i).inserted {model.entryEdges.remove(i)}
                                }
                                edgeButton("내려감",selected:model.exitEdges.contains(i),color:.orange) {
                                    if !model.exitEdges.insert(i).inserted {model.exitEdges.remove(i)}
                                }
                            }.font(.caption)
                        }
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
                } else {
                    ScrollView {VStack(spacing:4) {ForEach(draft.objects) {o in
                        HStack {Button("\(o.name) · \(o.kind.defaultName)\(o.height.map { " · \(Int(($0*100).rounded()))cm" } ?? "")") {model.beginObject(o.id)}; Spacer(); Button {model.deleteObject(o.id)} label:{Image(systemName:"trash")}.accessibilityLabel("\(o.name) 삭제")}.font(.caption).padding(.vertical,4)
                    }}}.frame(maxHeight:60)
                }
            }
            if step == .route, draft.routeFinished, let error=draft.routeErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
            if step == .checkpoint, draft.checkpoint != nil, let error=draft.checkpointErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
        }.padding(.horizontal,14).padding(.bottom,14)
    }
    private func edgeButton(_ title: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action:action) {
            Label(title,systemImage:selected ? "checkmark.circle.fill" : "circle")
                .font(.caption.bold()).frame(maxWidth:.infinity,minHeight:44)
                .foregroundStyle(selected ? Color.white : color)
                .background(selected ? color : color.opacity(0.1),in:RoundedRectangle(cornerRadius:10))
                .overlay(RoundedRectangle(cornerRadius:10).stroke(color,lineWidth:selected ? 2 : 1))
        }.buttonStyle(.plain)
            .accessibilityValue(selected ? "선택됨" : "선택 안 됨")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

}
