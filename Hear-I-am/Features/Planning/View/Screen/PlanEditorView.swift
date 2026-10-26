import SwiftUI
import HearIAmCore

/// Adaptive editor for a schematic plan. Units are layout units, not surveyed metres.
struct PlanEditorView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PlanEditorViewModel
    @Environment(\.dismiss) private var dismiss
    init(initial:PerformancePlan,library:StageLibrary) {self.library=library; _model=StateObject(wrappedValue:PlanEditorViewModel(initial:initial))}
    var body: some View {
        let plan=model.plan
        GeometryReader { geometry in
            VStack(spacing:12) {
                HStack(spacing:12) {
                    Button {if model.hasChanges {model.confirmingExit=true} else {dismiss()}} label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("편집 나가기")
                    TextField("공연 이름",text:$model.plan.name).font(.title3.bold()).textInputAutocapitalization(.sentences).submitLabel(.done)
                        .accessibilityLabel("공연 이름")
                    ActionButton(title:model.saving ? "저장 중…" : "저장",enabled:!model.saving && model.valid) {save()}
                }
                Text("배치 연습용 · 3:2 고정 비율").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth:.infinity,alignment:.leading)
                StageMap(points:plan.points,finished:plan.finished,objects:plan.objects,selectedObject:model.selected,onTap:model.tap)
                    .accessibilityLabel("공연 동선 편집 도면. 선택한 도구로 화면을 눌러 위치를 지정하세요.")
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        PlanEditorTools(model:model)
                        Text(plan.finished ? "출발 → 내부 \(plan.points.count-2)개 → 도착 · 기물은 모두 통과 금지" : "\(plan.points.count)/\(StageRoute.maxPointCount)점(시작점 포함) · 최소 3점부터 완료 · 마지막 점이 도착점이 됩니다").font(.caption)
                        if plan.finished, !model.valid {Text(model.validationMessage ?? "").font(.caption).foregroundStyle(.red)}
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight:geometry.size.height*0.4).fixedSize(horizontal:false,vertical:true)
                    .foregroundStyle(.secondary)
            }.padding(.horizontal,16).padding(.vertical,8)
        }.background(.white).disabled(model.saving)
            .onAppear {ScreenOrientation.set(.allButUpsideDown)}.onDisappear {ScreenOrientation.set(.portrait)}
            .alert("확인해주세요",isPresented:Binding(get:{model.message != nil},set:{if !$0 {model.message=nil}})) {Button("확인",role:.cancel) {model.message=nil}} message:{Text(model.message ?? "")}
            .confirmationDialog("저장하지 않은 변경사항이 있어요",isPresented:$model.confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {dismiss()}; Button("계속 편집",role:.cancel) {}
            }
    }
    private func save() {
        model.save(to:library) {dismiss()}
    }
}
