import SwiftUI
import HearIAmCore

/// Portrait guidance. One AR view stays attached for the whole flow.
struct GuidanceView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: GuidanceViewModel
    /// `request` is what the user already asked the voice agent on Home; it is handled first (#90).
    /// `stageID` and `mode` come from Siri (#91): the stage is chosen and the mode applied first.
    init(library:StageLibrary,voiceExperiment:Bool = false,request:String? = nil,stageID:UUID? = nil,mode:VoiceUsageMode? = nil,helperPreparation:Bool = false,
         openPlans:(() -> Void)? = nil,openScan:(() -> Void)? = nil) {
        self.library=library
        let model=GuidanceViewModel(voiceExperiment:voiceExperiment)
        model.voiceInitialRequest=request
        model.onOpenPlans=openPlans;model.onOpenScan=openScan
        model.voiceInitialStageID=stageID;model.voiceInitialMode=mode;model.helperPreparation=helperPreparation
        _model=StateObject(wrappedValue:model)
    }
    @State private var showingSettings=false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                if !model.phase.showsRouteCamera && (!model.voiceExperiment || model.phase != .selection) {
                    Text(model.phase.stepLabel(targetName:model.targetName)).font(.subheadline.weight(.semibold)).foregroundStyle(model.voiceExperiment ? Color.primary : Color.hearGreen).padding(.horizontal,24)
                }
                ZStack {
                    // Keep one AR view attached throughout the flow, including when the screen shows instructions.
                    CameraView(model:model.tracking).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
                    // Listening while paused keeps the route camera in view; the slim voice card shows it (#90).
                    if model.phase.showsRouteCamera { GuidanceLiveView(model:model) }
                    else if model.phase.isCameraStep { GuidanceCameraPrompt(model:model) }
                    else if model.phase == .selection {
                        HearV3.canvas
                        if model.voiceExperiment {VoiceStagePicker(library:library,model:model)}
                        else {GuidanceStageList(library:library,model:model)}
                    }
                    else { HearV3.canvas; GuidanceInstruction(model:model) }
                }
            }
            .navigationTitle(model.phase.showsRouteCamera ? "Hear I am" : model.helperPreparation ? "출발 준비" : "Hear I am").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    if model.voiceShouldListen && (model.voiceAwake || model.voiceTurnActive) {
                        Button("대화 닫기",systemImage:"xmark.circle") {model.dismissVoiceConversation()}.labelStyle(.iconOnly)
                    }
                }
                ToolbarItem(placement:.topBarTrailing) {
                    Menu {
                        Button("설정",systemImage:"gearshape") {
                            model.beginSettings()
                            showingSettings=true
                        }
                        Button("안내 끝내기",systemImage:"xmark") {exit()}
                    } label: {Image(systemName:"gearshape")}
                    .accessibilityLabel("안내 설정 및 종료")
                    .disabled(model.phase == .finishing || model.savingRecord || (model.phase == .completed && model.speaking))
                }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                VStack(spacing:0) {
                    // Selection starts voice-first; navigation and recovery controls stay available, and show
                    // at once when the microphone cannot be used.
                    if !model.voiceExperiment || model.phase != .selection || model.voiceSelectionControlsVisible || model.audioIssue != nil || model.voiceInputError != nil {
                        GuidanceControls(library:library,model:model,close:close,saveAndClose:saveAndClose)
                    }
                }.background(model.phase.showsRouteCamera ? (model.isPractice ? Color.white : HearV3.canvas) : HearV3.canvas)
            }
            .background(model.phase.showsRouteCamera && model.isPractice ? Color.white : HearV3.canvas)
            .tint(model.phase.showsRouteCamera && model.isPractice ? Color.black : HearV3.text)
            .preferredColorScheme(model.phase.showsRouteCamera && model.isPractice ? .light : .dark)
            // Settings push in, as in the design; the guidance resumes when the user comes back.
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView().suspendsVoiceWake()}
            .onChange(of:showingSettings) {_,shown in if !shown {model.endSettings()}}
            .alert("안내를 끝낼까요?",isPresented:$model.showExit) {
                Button("안내 끝내기",role:.destructive) { close() }
                Button("계속 사용하기",role:.cancel) { model.cancelExit() }
            } message: { Text("중간에 종료하면 도착 완료로 처리되지 않아요. 저장한 무대와 동선은 유지돼요.") }
        }
        .overlay {
            if model.voiceExperiment {
                VoiceEdgeGlow(visualization:model.voiceRecognition.inputVisualization,active:model.voiceShowsListening)
                // Only while the microphone is on: with performance mode's microphone off a tap must reach the buttons.
            }
        }
        .interactiveDismissDisabled()
        .onAppear {ScreenOrientation.set(.portrait)}
        .task {
            await library.refresh()
            if model.voiceExperiment {
                model.prepareVoiceExperiment(records:library.groups.pinned+library.groups.recent,contexts:library.voiceStageContexts,catalog:library.catalog)
            }
            else {model.selectionDescription(empty:library.records.isEmpty)}
        }
        .onDisappear {model.finish();ScreenOrientation.set(.portrait)}
        .onChange(of:model.phase) { _, phase in
            if phase == .completed {model.saveRecordByVoice(to:library,close:close)}
        }
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
