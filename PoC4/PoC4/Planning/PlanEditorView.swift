import SwiftUI
import PoC4Core

struct PlanEditorView: View {
    enum Tool: String, CaseIterable {case points="경로", obstacle="장애물", platform="단상"}
    @ObservedObject var library: StageLibrary
    @State private var plan: PerformancePlan
    @State private var tool: Tool = .points
    @State private var selected: UUID?
    @State private var message: String?
    @State private var confirmingExit=false
    @State private var saving=false
    @Environment(\.dismiss) private var dismiss
    private let initial: PerformancePlan
    init(initial:PerformancePlan,library:StageLibrary) {self.initial=initial; self.library=library; _plan=State(initialValue:initial)}
    var body: some View {
        VStack(spacing:10) {
            HStack(spacing:16) {
                Button {if plan != initial {confirmingExit=true} else {dismiss()}} label:{Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("편집 나가기")
                TextField("공연 이름",text:$plan.name).font(.title3.bold()).textInputAutocapitalization(.sentences).submitLabel(.done)
                Text("배치 연습용 · 3:2 고정 비율").font(.caption).foregroundStyle(.secondary)
                ActionButton(title:saving ? "저장 중…" : "저장",enabled:!saving && valid) {save()}
            }
            StageMap(points:plan.points,finished:plan.finished,objects:plan.objects,selectedObject:selected,onTap:tap)
                .accessibilityLabel("공연 동선 편집 도면. 선택한 도구로 화면을 눌러 위치를 지정하세요.")
            HStack(spacing:12) {
                Picker("도구",selection:$tool) {
                    Label("경로",systemImage:"point.topleft.down.to.point.bottomright.curvepath").tag(Tool.points)
                    Label("장애물",systemImage:"triangle").tag(Tool.obstacle)
                    Label("단상",systemImage:"square").tag(Tool.platform)
                }.pickerStyle(.segmented).frame(maxWidth:320).onChange(of:tool) {_,_ in selected=nil}
                if let selected {
                    Text("이동할 위치를 누르세요").font(.caption)
                    ActionButton(title:"기물 삭제",primary:false) {plan.objects.removeAll {$0.id==selected}; self.selected=nil}
                    Button("선택 해제") {self.selected=nil}.font(.caption)
                } else if tool == .points {
                    ActionButton(title:"최신 점 삭제",primary:false,enabled:!plan.points.isEmpty) {plan.undoPoint()}
                    ActionButton(title:plan.finished ? "경로 완료 ✓" : "경로 완료",enabled:plan.points.count>=3 && !plan.finished) {perform {try plan.finishRoute()}}
                } else {
                    Text("무대 안을 눌러 \(tool.rawValue) 추가 · 기물을 눌러 이동/삭제").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(plan.finished ? "출발 → 내부 \(plan.points.count-2)개 → 도착 · 기물은 모두 통과 금지" : "\(plan.points.count)/6점 · 최소 3점부터 완료 · 마지막 점이 도착점이 됩니다").font(.caption)
                Spacer()
                if plan.finished, !valid {Text("동선과 기물의 겹침을 확인해주세요").font(.caption).foregroundStyle(.red)}
            }.foregroundStyle(.secondary)
        }.padding(.horizontal,18).padding(.vertical,8).background(.white).disabled(saving)
            .onAppear {ScreenOrientation.set(.landscape)}.onDisappear {ScreenOrientation.set(.portrait)}
            .alert("확인해주세요",isPresented:Binding(get:{message != nil},set:{if !$0 {message=nil}})) {Button("확인",role:.cancel) {message=nil}} message:{Text(message ?? "")}
            .confirmationDialog("저장하지 않은 변경사항이 있어요",isPresented:$confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {dismiss()}; Button("계속 편집",role:.cancel) {}
            }
    }
    private var valid: Bool {(try? plan.validate()) != nil}
    private func perform(_ action:() throws -> Void) {do {try action()} catch {message=error.localizedDescription}}
    private func tap(_ point:FloorPoint) {
        guard !saving else {return}
        if let selected {perform {try plan.moveObject(selected,to:point)}; return}
        if let object=plan.objects.last(where:{$0.contains(point)}) {selected=object.id; return}
        perform {
            switch tool {
            case .points: try plan.append(point)
            case .obstacle: try plan.addObject(at:point,platform:false)
            case .platform: try plan.addObject(at:point,platform:true)
            }
        }
    }
    private func save() {
        saving=true
        Task {do {try await library.savePlan(plan); dismiss()} catch {message=error.localizedDescription}; saving=false}
    }
}
