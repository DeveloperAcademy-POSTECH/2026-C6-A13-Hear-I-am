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
                Text("\(model.meshCount)개 표면 · \(model.mapping)").font(.caption).foregroundStyle(.secondary)
            }
            if step == .scan || step == .boundary {
                Toggle("스캔 범위 표시",isOn:$model.showMesh).font(.caption).tint(.hearGreen)
            }
            if step == .boundary {
                HStack(spacing:5) {ForEach(PreparationDraft.captureOrder,id:\.self) {i in
                    Button(PreparationStep.cornerNames[i]) {model.selectedCorner=i}.font(.system(size:10)).buttonStyle(.bordered).tint(model.selectedCorner == i ? .hearGreen : .gray)
                }}
                if model.allCornersCaptured, let error=draft.boundaryErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
            }
            if step == .objects {
                if model.objectEditing {
                    TextField("기물 이름",text:$model.obstacleName).textFieldStyle(.roundedBorder).font(.caption)
                    Picker("종류",selection:$model.obstacleKind) {Text("장애물").tag(ObstacleKind.other); Text("단상").tag(ObstacleKind.platform)}.pickerStyle(.segmented)
                } else {
                    ScrollView {VStack(spacing:4) {ForEach(draft.objects) {o in
                        HStack {Button(o.name) {model.beginObject(o.id)}; Spacer(); Button {model.deleteObject(o.id)} label:{Image(systemName:"trash")}.accessibilityLabel("\(o.name) 삭제")}.font(.caption).padding(.vertical,4)
                    }}}.frame(maxHeight:60)
                }
            }
            if step == .route, draft.routeFinished, let error=draft.routeErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
            if step == .checkpoint, draft.checkpoint != nil, let error=draft.checkpointErrors.first {Text(error).font(.caption).foregroundStyle(.red)}
        }.padding(.horizontal,14).padding(.bottom,14)
    }
}
