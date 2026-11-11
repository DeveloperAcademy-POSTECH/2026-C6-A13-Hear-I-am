import SwiftUI
import HearIAmCore

/// Portrait guidance. One AR view stays attached for the whole flow.
/// By voice (Figma 「apple intellenge」) the performer sees the conversation until the walk starts and then the
/// 연습 안내 · 실전 안내 screen (1028:18921 · 18910 · 18900); the camera keeps relocalising behind the canvas and is
/// never shown. In 실전용 the helper takes the checkpoints on the camera screen in between (1028:18949, #167).
/// Opened by the helper from a performance, it starts at that checkpoint screen and goes on as 실전용 (#175).
struct GuidanceView: View {
    @ObservedObject var library: StageLibrary
    @StateObject private var model: GuidanceViewModel
    /// `request` is what the user already asked the voice agent on Home; it is handled first (#90).
    /// `stageID` and `mode` come from Siri (#91): the stage is chosen and the mode applied first.
    init(library:StageLibrary,voiceExperiment:Bool = false,request:String? = nil,heard:String? = nil,stageID:UUID? = nil,mode:VoiceUsageMode? = nil,helperPreparation:Bool = false,
         openPlans:(() -> Void)? = nil,openScan:(() -> Void)? = nil,onClose:(() -> Void)? = nil) {
        self.library=library
        self.onClose=onClose
        let model=GuidanceViewModel(voiceExperiment:voiceExperiment)
        model.voiceInitialRequest=request
        model.onOpenPlans=openPlans;model.onOpenScan=openScan
        model.voiceInitialStageID=stageID;model.voiceInitialMode=mode
        // The helper's preparation is now 실전용's own flow from the checkpoints, not the earlier button screens (#175).
        model.helperStart=voiceExperiment && helperPreparation;model.helperPreparation=helperPreparation && !voiceExperiment
        // What was said on Home is on screen from the first frame, so the chat does not flash empty.
        if voiceExperiment, !helperPreparation, let heard=heard ?? request, !heard.isEmpty {
            model.voiceChat=[VoiceChatEntry(kind:.user(heard))]
            model.voiceChatSeededRequest=request
        }
        _model=StateObject(wrappedValue:model)
    }
    /// Set when the conversation stands in Home's place instead of being presented; closing hands Home back.
    private let onClose: (() -> Void)?
    @State private var showingSettings=false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// The performer's own voice flow, as opposed to the helper's preparation and the button-only flow.
    private var voiceFlow: Bool {model.voiceExperiment && !model.helperPreparation}
    /// 실전용 by voice: the helper aims at the checkpoints with the camera in view.
    /// Opened by the helper, it is on screen from the start, while the space is still being looked for.
    private var checkpointScreen: Bool {
        guard voiceFlow else {return false}
        if model.helperStart, [.selection,.restoring].contains(model.phase) {return true}
        return model.voicePerformanceFlow && model.phase == .checkpoint
    }
    /// The walking screen from 「출발」: 「잠시 후 안내가 시작됩니다」 while the start is read, then the walk (#167).
    private var voiceWalk: Bool {voiceFlow && (model.phase.showsRouteCamera || model.voicePerformanceToStart)}
    private var conversation: Bool {voiceFlow && !voiceWalk && !checkpointScreen}
    private var lightPractice: Bool {model.phase.showsRouteCamera && model.isPractice && !model.voiceExperiment}
    private var paper: Color {voiceFlow ? VoiceStyle.canvas : lightPractice ? Color.white : HearV3.canvas}
    /// By voice the buttons appear only when the microphone cannot carry the step or a step needs a decision.
    private var showsControls: Bool {
        if !model.voiceExperiment {return true}
        if model.voiceSelectionControlsVisible || model.audioIssue != nil || model.voiceInputError != nil {return true}
        if model.phase == .selection {return library.records.isEmpty}
        if conversation {return [.failed,.interrupted].contains(model.phase)}
        if checkpointScreen {return false}
        // The end shows only 「안내를 종료합니다 · 도착」: closing and saving happen by themselves (11/09).
        if voiceWalk {return model.phase == .paused}
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                if !model.phase.showsRouteCamera && !model.voiceExperiment {
                    Text(model.phase.stepLabel(targetName:model.targetName)).font(.subheadline.weight(.semibold)).foregroundStyle(Color.hearGreen).padding(.horizontal,24)
                }
                ZStack {
                    // Keep one AR view attached throughout the flow, including when the screen shows instructions.
                    // The checkpoint screen shows the whole camera, as the scan screen does (11/09).
                    CameraView(model:model.tracking).frame(maxWidth:.infinity,maxHeight:.infinity).accessibilityHidden(true)
                        .ignoresSafeArea(edges:checkpointScreen ? .all : [])
                    if conversation {VoiceConversationView(library:library,model:model)}
                    else if checkpointScreen {
                        PerformanceCheckpointView(model:model,tracking:model.tracking,onBack:{exit()},
                                                  onSettings:{model.beginSettings();showingSettings=true})
                    }
                    else if voiceWalk {VoiceGuidanceWalkView(model:model)}
                    // Listening while paused keeps the route camera in view; the slim voice card shows it (#90).
                    else if model.phase.showsRouteCamera { GuidanceLiveView(model:model) }
                    else if model.phase.isCameraStep { GuidanceCameraPrompt(model:model) }
                    else if model.phase == .selection {
                        HearV3.canvas
                        GuidanceStageList(library:library,model:model)
                    }
                    else { HearV3.canvas; GuidanceInstruction(model:model) }
                }
            }
            .navigationTitle(voiceWalk ? (model.isPractice ? "연습 안내" : "실전 안내") : conversation || checkpointScreen ? "" : model.helperPreparation ? "출발 준비" : "Hear I am").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(voiceFlow ? .hidden : .automatic,for:.navigationBar)
            .toolbar(checkpointScreen ? .hidden : .automatic,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    if conversation || voiceWalk {
                        VoiceBackButton {exit()}.accessibilityIdentifier("voice.back")
                    } else if model.voiceShouldListen && (model.voiceAwake || model.voiceTurnActive) {
                        Button("대화 닫기",systemImage:"xmark.circle") {model.dismissVoiceConversation()}.labelStyle(.iconOnly)
                    }
                }
                // The walking screen has only the back button (1028:18910); the checkpoint screen draws its own row.
                if !voiceWalk && !checkpointScreen { ToolbarItem(placement:.topBarTrailing) {
                    Menu {
                        Button("설정",systemImage:"gearshape") {
                            model.beginSettings()
                            showingSettings=true
                        }
                        Button("안내 끝내기",systemImage:"xmark") {exit()}
                    } label: {Image(systemName:"gearshape")}
                    .accessibilityLabel("안내 설정 및 종료")
                    .disabled(model.phase == .finishing || model.savingRecord || (model.phase == .completed && model.speaking))
                } }
            }
            .safeAreaInset(edge:.bottom,spacing:0) {
                VStack(spacing:0) {
                    // Selection starts voice-first; navigation and recovery controls stay available, and show
                    // at once when the microphone cannot be used.
                    if showsControls {
                        GuidanceControls(library:library,model:model,close:close,saveAndClose:saveAndClose)
                    }
                }.background(paper)
            }
            .background(paper)
            .tint(lightPractice ? Color.black : voiceFlow ? Color.white : HearV3.text)
            .preferredColorScheme(lightPractice ? .light : .dark)
            // Settings push in, as in the design; the guidance resumes when the user comes back.
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView().suspendsVoiceWake()}
            .onChange(of:showingSettings) {_,shown in if !shown {model.endSettings()}}
            .alert("안내를 끝낼까요?",isPresented:$model.showExit) {
                Button("안내 끝내기",role:.destructive) { close() }
                Button("계속 사용하기",role:.cancel) { model.cancelExit() }
            } message: { Text("중간에 종료하면 도착 완료로 처리되지 않아요. 저장한 무대와 동선은 유지돼요.") }
        }
        // The design (495:5074–5481) has no light around the edge; the lights under the conversation move instead.
        .interactiveDismissDisabled()
        .onAppear {
            ScreenOrientation.set(.portrait)
            model.onVoiceClose={[self] in model.phase == .completed ? saveAndClose() : close()}
        }
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
    private func close() {
        model.finish()
        if let onClose {onClose()} else {dismiss()}
    }
    private func saveAndClose() {
        model.saveRecord(to:library) { close() }
    }
    private func exit() {
        if model.phase == .completed {saveAndClose()}
        else if model.phase == .selection {close()}
        else {model.requestExit()}
    }
}
