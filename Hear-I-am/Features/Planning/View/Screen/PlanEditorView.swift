import SwiftUI
import HearIAmCore

/// V3 portrait editor. This schematic remains independent of calibrated venue routes.
struct PlanEditorView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: PlanEditorViewModel
    let performanceID: UUID?
    @Environment(\.dismiss) private var dismiss
    init(initial: PerformancePlan, library: StageLibrary, performanceID: UUID? = nil) {
        self.library=library;self.performanceID=performanceID
        _model=StateObject(wrappedValue:PlanEditorViewModel(initial:initial))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    HStack(alignment:.firstTextBaseline) {
                        Text(model.plan.name).font(.title3.bold())
                        Spacer()
                        Text(model.plan.points.isEmpty ? "새 동선" : "\(model.plan.points.count)지점 · 기준 동선")
                            .font(.caption).foregroundStyle(HearV3.secondary)
                    }
                    Text("공연장에 맞추기 전, 기준이 되는 동선이에요.")
                        .font(.subheadline).foregroundStyle(HearV3.secondary)
                    StageMap(points:model.plan.points,finished:model.plan.finished,objects:model.plan.objects,
                             selectedObject:model.selected,onTap:model.tap,v3Style:true,
                             objectFacings:model.plan.objectFacings,onDrag:model.drag)
                        .frame(height:280)
                        .accessibilityLabel("기본 동선 도면. 눌러 지점을 추가하고, 기물을 끌어 이동하거나 꼭짓점을 끌어 크기를 조절하세요.")
                    toolPicker
                    if model.plan.points.isEmpty && model.tool == .points {emptyInstructions}
                    else if model.tool == .points {routeList}
                    else {objectControls}
                    if model.plan.finished,let message=model.validationMessage {
                        Text(message).font(.caption).foregroundStyle(.orange)
                    }
                }.padding(20)
            }
            .navigationTitle("기본 동선 설정").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) {
                    Button {if model.hasChanges {model.confirmingExit=true} else {dismiss()}} label:{Image(systemName:"chevron.left")}
                        .accessibilityLabel("기본 동선 설정 나가기")
                }
            }
            .safeAreaInset(edge:.bottom) {
                Button(model.saving ? "저장 중…" : "기본 동선 저장",action:save)
                    .buttonStyle(V3PrimaryButtonStyle())
                    .disabled(model.saving || model.plan.points.count<3)
                    .opacity(model.plan.points.count<3 ? 0.35 : 1)
                    .padding(.horizontal,20).padding(.vertical,12).background(HearV3.canvas)
            }
            .v3Screen()
            .disabled(model.saving)
            .onAppear {ScreenOrientation.set(.portrait)}
            .confirmationDialog("저장하지 않은 변경사항이 있어요",isPresented:$model.confirmingExit,titleVisibility:.visible) {
                Button("저장하지 않고 나가기",role:.destructive) {dismiss()}
                Button("계속 편집",role:.cancel) {}
            }
            .alert("확인해주세요",isPresented:Binding(get:{model.message != nil},set:{if !$0 {model.message=nil}})) {
                Button("확인",role:.cancel) {model.message=nil}
            } message: {Text(model.message ?? "")}
            .sheet(isPresented:Binding(get:{model.selectedPoint != nil},set:{if !$0 {model.selectedPoint=nil}})) {
                if let index=model.selectedPoint {
                    PlanPointSettingsSheet(label:model.plan.pointLabel(at:index),settings:model.plan.settings(at:index),
                                           canWait:index>0 && index<model.plan.points.count-1) {value in
                        if model.updatePoint(value,at:index) {model.selectedPoint=nil}
                    }.suspendsVoiceWake()
                }
            }
        }
    }
    private var toolPicker: some View {
        HStack(spacing:8) {
            ForEach(PlanEditorTool.allCases,id:\.self) {tool in
                Button {model.tool=tool} label: {
                    Text(tool.rawValue).font(.subheadline.weight(.semibold)).padding(.horizontal,16).padding(.vertical,8)
                        .foregroundStyle(model.tool==tool ? HearV3.canvas : HearV3.secondary)
                        .background(model.tool==tool ? HearV3.text : HearV3.surface,in:Capsule())
                }.buttonStyle(.plain).frame(minHeight:48).accessibilityAddTraits(model.tool==tool ? .isSelected : [])
            }
        }
    }
    private var emptyInstructions: some View {
        VStack(alignment:.leading,spacing:14) {
            VStack(alignment:.leading,spacing:10) {
                Text("출발점을 먼저 찍어주세요").font(.headline)
                Text("무대를 누르는 순서대로 이동 지점을 추가해요.\n마지막 지점은 도착점이 돼요.")
                    .font(.subheadline).foregroundStyle(HearV3.secondary)
            }.v3Card()
            Text("1  출발점 추가\n2  중간 지점과 도착점 추가\n3  장애물·의자 배치 후 저장")
                .font(.subheadline).lineSpacing(10)
        }
    }
    private var routeList: some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("이동 순서").font(.headline)
                Spacer()
                Button("마지막 점 삭제") {model.undoPoint()}.font(.caption).frame(minHeight:44)
            }
            ForEach(model.plan.points.indices,id:\.self) {index in
                let settings=model.plan.settings(at:index)
                Button {model.selectedPoint=index} label: {
                    HStack(spacing:12) {
                        Text(model.plan.pointLabel(at:index)).font(.caption.bold())
                            .frame(width:38,height:38).background(HearV3.selected,in:Circle())
                        VStack(alignment:.leading,spacing:5) {
                            Text(settings.name.isEmpty ? model.plan.pointLabel(at:index) : settings.name).font(.subheadline.weight(.medium))
                            Text("\(settings.holdSeconds==0 ? "대기 없음" : "\(settings.holdSeconds)초 대기") · \(settings.facing?.label ?? "방향 미지정")")
                                .font(.caption).foregroundStyle(HearV3.secondary)
                        }
                        Spacer()
                        Image(systemName:"chevron.right").font(.caption)
                    }.v3Card(inset:12)
                }.buttonStyle(.plain)
            }
            if model.plan.finished {
                Button("지점 더 추가하기") {model.plan.resumeEditing()}.frame(minHeight:44)
            }
            Text("지점을 눌러 이름, 대기 시간, 바라볼 방향을 설정하세요.")
                .font(.caption).foregroundStyle(HearV3.secondary)
        }
    }
    private var objectControls: some View {
        VStack(alignment:.leading,spacing:12) {
            if let object=model.plan.objects.first(where:{$0.id==model.selected}) {
                VStack(alignment:.leading,spacing:14) {
                    HStack {
                        Text(object.name).font(.headline)
                        Spacer()
                        Button(role:.destructive,action:model.deleteSelectedObject) {Image(systemName:"trash")}
                            .buttonStyle(.bordered).buttonBorderShape(.circle).accessibilityLabel("선택한 기물 삭제")
                    }
                    if object.isStep {
                        Text("앉은 뒤 바라볼 방향을 정해주세요.").font(.subheadline).foregroundStyle(HearV3.secondary)
                        let facing=model.plan.objectFacings[object.id] ?? .north
                        HStack {
                            Button("↶ 45°") {model.rotateChair(-1)}.buttonStyle(.bordered).buttonBorderShape(.capsule)
                            Spacer()
                            VStack {Text("\(Int(facing.headingDegrees))°").font(.title2.bold());Text(facing.label).font(.caption)}
                            Spacer()
                            Button("45° ↷") {model.rotateChair(1)}.buttonStyle(.bordered).buttonBorderShape(.capsule)
                        }
                    } else {
                        Text("도면에서 끌어 이동하고, 꼭짓점을 끌어 크기를 조절해요.")
                            .font(.subheadline).foregroundStyle(HearV3.secondary)
                    }
                }.v3Card()
            } else {
                Text("도면을 눌러 \(model.tool.rawValue)를 배치해주세요.").font(.subheadline).v3Card()
            }
            Button("\(model.tool.rawValue) 추가") {model.selected=nil}
                .frame(maxWidth:.infinity,minHeight:48).background(HearV3.raised,in:Capsule())
            Text("기본 배치의 기준이며 실제 무대 준비 시 현장에서 확인합니다.")
                .font(.caption).foregroundStyle(HearV3.secondary)
        }
    }
    private func save() {
        if !model.plan.finished {model.finishRoute()}
        guard model.valid else {model.message=model.validationMessage;return}
        model.save(to:library,performanceID:performanceID) {dismiss()}
    }
}

private struct PlanPointSettingsSheet: View {
    let label: String
    let canWait: Bool
    let onSave: (PerformancePlanPointSettings) -> Void
    @State private var settings: PerformancePlanPointSettings
    @Environment(\.dismiss) private var dismiss
    init(label: String, settings: PerformancePlanPointSettings, canWait: Bool, onSave: @escaping (PerformancePlanPointSettings)->Void) {
        self.label=label;self.canWait=canWait;self.onSave=onSave;_settings=State(initialValue:settings)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("지점 이름") {TextField("예: 대사 시작",text:$settings.name)}
                Section("도착 후 대기") {
                    if canWait {Stepper("\(settings.holdSeconds)초",value:$settings.holdSeconds,in:0...3600)}
                    else {Text("출발점과 마지막 도착점은 대기하지 않아요.").font(.subheadline)}
                }
                Section("바라볼 방향") {
                    Picker("방향",selection:$settings.facing) {
                        Text("지정 안 함").tag(StageFacing?.none)
                        ForEach(StageFacing.allCases,id:\.self) {Text($0.label).tag(Optional($0))}
                    }
                }
            }.scrollContentBackground(.hidden)
                .navigationTitle("\(label) 설정").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) {Button("취소") {dismiss()}}
                    ToolbarItem(placement:.confirmationAction) {Button("완료") {onSave(settings)}.disabled(settings.name.count>80)}
                }.v3Screen()
        }
    }
}
