import SwiftUI
import HearIAmCore

/// Landscape editor for a schematic plan with real stage dimensions (stageWidth × stageDepth metres).
struct PlanEditorView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PlanEditorViewModel
    @FocusState private var inputFocused: Bool
    @Environment(\.dismiss) private var dismiss
    init(initial:PerformancePlan,library:StageLibrary) {self.library=library; _model=StateObject(wrappedValue:PlanEditorViewModel(initial:initial))}
    var body: some View {
        let plan=model.plan
        VStack(spacing:10) {
            HStack(spacing:12) {
                Button {if model.hasChanges {model.confirmingExit=true} else {dismiss()}} label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("편집 나가기")
                TextField("공연 이름",text:$model.plan.name).font(.title3.bold()).textInputAutocapitalization(.sentences).submitLabel(.done).focused($inputFocused)
                HStack(spacing:6) {
                    Text("가로").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("가로",value:$model.plan.stageWidth,format:.number)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width:56).focused($inputFocused)
                    Text("m × 세로").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("세로",value:$model.plan.stageDepth,format:.number)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder).frame(width:56).focused($inputFocused)
                    Text("m").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
                ActionButton(title:model.saving ? "저장 중…" : "저장",enabled:!model.saving && model.valid) {inputFocused=false; save()}
            }
            StageMap(points:plan.points,finished:plan.finished,objects:plan.objects,selectedObject:model.selected) { point in
                inputFocused=false
                model.tap(point)
            }.accessibilityLabel("공연 동선 편집 도면. 선택한 도구로 화면을 눌러 위치를 지정하세요.")
            PlanEditorTools(model:model)
            HStack(spacing:12) {
                if let summary=model.segmentSummary {
                    Text("환산 거리: \(summary)").font(.caption.weight(.medium)).foregroundStyle(Color.hearInk).lineLimit(1)
                } else {
                    Text(plan.finished ? "출발 → 내부 \(plan.points.count-2)개 → 도착 · 기물은 모두 통과 금지" : "\(plan.points.count)/6점 · 최소 3점부터 완료 · 마지막 점이 도착점이 됩니다").font(.caption)
                }
                Spacer()
                if (plan.finished || !plan.hasValidDimensions), !model.valid {
                    Text(model.validationMessage ?? "").font(.caption).foregroundStyle(.red)
                }
            }.foregroundStyle(.secondary)
        }.padding(.horizontal,18).padding(.vertical,8).background(.white).disabled(model.saving)
            .toolbar {
                ToolbarItemGroup(placement:.keyboard) {
                    Spacer()
                    Button("완료") {inputFocused=false}.fontWeight(.bold)
                }
            }
            .onAppear {ScreenOrientation.set(.landscape)}.onDisappear {ScreenOrientation.set(.portrait)}
            .alert("확인해주세요",isPresented:Binding(get:{model.message != nil},set:{if !$0 {model.message=nil}})) {Button("확인",role:.cancel) {model.message=nil}} message:{Text(model.message ?? "")}
            .confirmationDialog("저장하지 않은 변경사항이 있어요",isPresented:$model.confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {dismiss()}; Button("계속 편집",role:.cancel) {}
            }
    }
    private func save() {
        model.save(to:library) {dismiss()}
    }
}
