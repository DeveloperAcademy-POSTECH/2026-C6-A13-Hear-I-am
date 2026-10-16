import SwiftUI

/// Tool picker and the actions available for the current tool or selected object.
struct PlanEditorTools: View {
    @ObservedObject var model: PlanEditorViewModel
    var body: some View {
        HStack(spacing:12) {
            Picker("도구",selection:$model.tool) {
                Label("경로",systemImage:"point.topleft.down.to.point.bottomright.curvepath").tag(PlanEditorTool.points)
                Label("장애물",systemImage:"triangle").tag(PlanEditorTool.obstacle)
                Label("단상",systemImage:"square").tag(PlanEditorTool.platform)
            }.pickerStyle(.segmented).frame(maxWidth:320)
            if model.selected != nil {
                Text("이동할 위치를 누르세요").font(.caption)
                ActionButton(title:"기물 삭제",primary:false) {model.deleteSelectedObject()}
                Button("선택 해제") {model.selected=nil}.font(.caption)
            } else if model.tool == .points {
                ActionButton(title:"최신 점 삭제",primary:false,enabled:!model.plan.points.isEmpty) {model.undoPoint()}
                ActionButton(title:model.plan.finished ? "경로 완료 ✓" : "경로 완료",enabled:model.plan.points.count>=3 && !model.plan.finished) {model.finishRoute()}
            } else {
                Text("무대 안을 눌러 \(model.tool.rawValue) 추가 · 기물을 눌러 이동/삭제").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
