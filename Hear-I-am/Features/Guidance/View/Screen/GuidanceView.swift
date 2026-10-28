import SwiftUI
import HearIAmCore

/// Portrait guidance. One AR view stays attached for the whole flow.
struct GuidanceView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: GuidanceViewModel
    /// `request` is what the user already asked the voice agent on Home; it is handled first (#90).
    /// `stageID` and `mode` come from Siri (#91): the stage is chosen and the mode applied first.
    init(library:StageLibrary,voiceExperiment:Bool = false,request:String? = nil,stageID:UUID? = nil,mode:VoiceUsageMode? = nil) {
        self.library=library
        let model=GuidanceViewModel(voiceExperiment:voiceExperiment)
        model.voiceInitialRequest=request
        model.voiceInitialStageID=stageID;model.voiceInitialMode=mode
        _model=StateObject(wrappedValue:model)
    }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                if !model.voiceExperiment || model.phase != .selection {
                    Text(model.phase.stepLabel(targetName:model.targetName)).font(.subheadline.weight(.semibold)).foregroundStyle(model.voiceExperiment ? Color.primary : Color.hearGreen).padding(.horizontal,24)
                }
                if model.phase.showsRouteCamera { GuidanceRouteHeader(model:model) }
                ZStack {
                    // Keep one AR view attached throughout the flow, including when the screen shows instructions.
                    CameraView(model:model.tracking).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
                    // Listening while paused keeps the route camera in view; the slim voice card shows it (#90).
                    if model.phase.showsRouteCamera { GuidanceRouteOverlay(model:model) }
                    else if model.phase.isCameraStep { GuidanceCameraPrompt(model:model) }
                    else if model.phase == .selection {
                        Color(.systemBackground)
                        if model.voiceExperiment {VoiceStagePicker(library:library,model:model)}
                        else {GuidanceStageList(library:library,model:model)}
                    }
                    else { Color(.systemBackground).opacity(model.phase.showsCameraBehindInstruction ? 0.7 : 1); GuidanceInstruction(model:model) }
                }.clipShape(RoundedRectangle(cornerRadius:model.phase.showsRouteCamera ? 18 : 0))
                    .padding(.horizontal,model.phase.showsRouteCamera ? 20 : 0)
            }
            .navigationTitle(model.voiceExperiment ? "말로 안내 시작" : "안내 사용하기").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button("나가기",systemImage:"xmark") { exit() }.labelStyle(.iconOnly)
                        .disabled(model.phase == .finishing || model.savingRecord || (model.phase == .completed && model.speaking))
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                VStack(spacing:0) {
                    if model.voiceExperiment {VoiceRehearsalPanel(model:model)}
                    // Selection starts voice-first; navigation and recovery controls stay available.
                    if !model.voiceExperiment || model.phase != .selection || model.voiceSelectionControlsVisible || model.audioIssue != nil {
                        GuidanceControls(library:library,model:model,close:close,saveAndClose:saveAndClose)
                    }
                }.background(Color(.systemBackground))
            }
            .background(Color(.systemBackground))
            .tint(model.voiceExperiment ? .primary : .hearGreen)
            .alert("안내를 끝낼까요?",isPresented:$model.showExit) {
                Button("안내 끝내기",role:.destructive) { close() }
                Button("계속 사용하기",role:.cancel) { model.cancelExit() }
            } message: { Text("중간에 종료하면 도착 완료로 처리되지 않아요. 저장한 무대와 동선은 유지돼요.") }
        }
        .overlay {
            if model.voiceExperiment {
                VoiceEdgeGlow(visualization:model.voiceRecognition.inputVisualization,active:model.voiceShowsListening)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {ScreenOrientation.set(.portrait)}
        .task {
            await library.refresh()
            if model.voiceExperiment {
                let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("PlaceFolders",isDirectory:true)
                let places=(try? await PlaceFolderStore(root:root).load()) ?? PlaceFolderIndex()
                model.prepareVoiceExperiment(records:library.groups.pinned+library.groups.recent,places:places)
            }
            else {model.selectionDescription(empty:library.records.isEmpty)}
        }
        .onDisappear {model.finish();ScreenOrientation.set(.portrait)}
        .onChange(of:scenePhase) { _, value in
            // Camera permission sheets may make the scene inactive during restoration.
            if value == .active { model.setActive(true) }
            else if value == .background || (model.phase != .selection && model.phase != .restoring) { model.setActive(false) }
        }
    }
    private func close() { model.finish();dismiss() }
    private func saveAndClose() {
        model.saveRecord(to:library) { close() }
    }
    private func exit() {
        if model.phase == .completed {saveAndClose()}
        else if model.phase == .selection {close()}
        else {model.requestExit()}
    }
}
