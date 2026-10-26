import SwiftUI

/// Tool picker and the actions available for the current tool or selected object.
struct PlanEditorTools: View {
    @ObservedObject var model: PlanEditorViewModel
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let compact=verticalSizeClass == .compact && !typeSize.isAccessibilitySize
        let layout=compact ? AnyLayout(HStackLayout(spacing:12)) : AnyLayout(VStackLayout(alignment:.leading,spacing:12))
        layout {
            Picker("도구",selection:$model.tool) {
                Label("경로",systemImage:"point.topleft.down.to.point.bottomright.curvepath").tag(PlanEditorTool.points)
                Label("장애물",systemImage:"triangle").tag(PlanEditorTool.obstacle)
                Label("의자",systemImage:"square").tag(PlanEditorTool.platform)
            }.pickerStyle(.segmented).frame(maxWidth:compact ? 260 : 320)
            WrappingControlsLayout {
            if model.selected != nil {
                Text("이동할 위치를 누르세요").font(.caption)
                ActionButton(title:"기물 삭제",primary:false) {model.deleteSelectedObject()}
                Button("선택 해제") {model.selected=nil}.font(.caption).frame(minWidth:44,minHeight:44)
            } else if model.tool == .points {
                ActionButton(title:"최신 점 삭제",primary:false,enabled:!model.plan.points.isEmpty) {model.undoPoint()}
                ActionButton(title:model.plan.finished ? "경로 완료 ✓" : "경로 완료",enabled:model.plan.points.count>=3 && !model.plan.finished) {model.finishRoute()}
            } else {
                Text("무대 안을 눌러 \(model.tool.rawValue) 추가 · 기물을 눌러 이동/삭제").font(.caption).foregroundStyle(.secondary)
            }
            }
        }
    }
}
