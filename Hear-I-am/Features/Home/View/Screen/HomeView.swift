import SwiftUI
import Combine
import HearIAmCore

/// Voice-first home. Scan preparation and saved performances remain in the Places tab.
struct HomeView: View {
    @ObservedObject var library: StageLibrary
    @State private var showingSettings=false
    @State private var showingVoiceGuidance=false
    @State private var request: String?
    @State private var visible=false
    @StateObject private var wake=HomeWakeWordListener()
    @ObservedObject private var launch=VoiceLaunch.shared
    @State private var siriRequest: VoiceLaunch.Request?
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo:.largeTitle) private var headingSize: CGFloat=44

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        HStack {
                            Text(VoiceWakeWord.phrase).font(.largeTitle.bold())
                            Spacer()
                            Button {showingSettings=true} label: {
                                Image(systemName:"gearshape").font(.title2)
                                    .frame(width:44,height:44)
                                    .background(Color(.systemGray6),in:Circle())
                            }.accessibilityLabel("설정").accessibilityIdentifier("home.settings")
                        }
                        Spacer(minLength:48)
                        // Voice only: no start button. Calling the app name wakes the agent here (#90).
                        VStack(spacing:32) {
                            VoiceGlassOrb(active:wake.awake).frame(width:120,height:120)
                            VStack(spacing:12) {
                                Text("이렇게 불러주세요").font(.headline).foregroundStyle(.secondary)
                                Text("“\(VoiceWakeWord.phrase)”")
                                    .font(.system(size:headingSize,weight:.bold))
                                    .minimumScaleFactor(0.6).lineLimit(1)
                                // While awake the agent's state and what it heard take this line; nothing covers Home.
                                Text(agentLine)
                                    .font(.body).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal:false,vertical:true)
                                    .padding(.top,4)
                            }
                        }.frame(maxWidth:.infinity)
                            .accessibilityElement(children:.ignore)
                            .accessibilityLabel("Hear I am이라고 부르면 안내를 시작해요. 무대 고르기부터 출발까지 말로 이어서 진행해요.")
                            .accessibilityAddTraits(.isHeader)
                        if let failure=wake.failure {
                            // Without a microphone or dictation the call cannot be heard; keep one way in.
                            VStack(spacing:12) {
                                Text(failure).font(.body).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                                Button("버튼으로 시작") {
                                    wake.stop()
                                    request=nil
                                    showingVoiceGuidance=true
                                }.font(.headline).frame(minHeight:44)
                                    .accessibilityIdentifier("home.voice.start")
                            }.frame(maxWidth:.infinity).padding(.top,24)
                        }
                        Spacer(minLength:36)
                    }.padding(.horizontal,24).padding(.vertical,20)
                        .frame(minHeight:geometry.size.height,alignment:.top)
                }.scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(.systemBackground))
            .navigationTitle("홈").toolbar(.hidden,for:.navigationBar)
            .toolbar(showingSettings ? .hidden : .visible,for:.tabBar)
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView()}
            .fullScreenCover(isPresented:$showingVoiceGuidance,onDismiss:syncWake) {
                GuidanceView(library:library,voiceExperiment:true,request:request,
                             stageID:siriRequest?.stageID,mode:siriRequest?.mode)
            }
        }
        // The agent shows as light around the screen edge; a step screen opens only once there is a request.
        .overlay {VoiceEdgeGlow(visualization:wake.visualization,active:wake.awake)}
        // Like Siri, a tap anywhere while the agent is listening closes it.
        .overlay {if wake.awake {VoiceDismissLayer {wake.dismiss()}}}
        .onAppear {
            visible=true
            wake.onRequest={ text in
                siriRequest=nil
                request=text
                showingVoiceGuidance=true
            }
            syncWake()
        }
        .onDisappear {visible=false;wake.stop()}
        .onChange(of:launch.pending) { _, value in
            guard let value, !showingVoiceGuidance else {return}
            launch.pending=nil
            wake.stop()
            request=nil;siriRequest=value
            showingVoiceGuidance=true
        }
        .onChange(of:scenePhase) {syncWake()}
        .onChange(of:showingSettings) {syncWake()}
    }

    private var agentLine: String {
        guard wake.awake else {return "무대 고르기부터 출발까지\n말로 이어서 진행해요"}
        return wake.speaking ? HomeWakeWordListener.greeting : "듣고 있어요"
    }

    /// The wake word is heard only while Home itself is on screen and the app is active.
    private func syncWake() {
        if visible && scenePhase == .active && !showingVoiceGuidance && !showingSettings {wake.start()}
        else {wake.stop()}
    }
}

/// The voice agent on Home (#90). While asleep it only waits for 「히얼아이엠」; speech without the call
/// belongs to someone else and is ignored. Once called it greets, takes one request and hands it to
/// guidance, or falls asleep again after a quiet while.
@MainActor final class HomeWakeWordListener: ObservableObject {
    @Published private(set) var listening=false
    @Published private(set) var awake=false
    @Published private(set) var speaking=false
    /// Why the call cannot be heard (no permission, dictation off); nil while listening works.
    @Published private(set) var failure: String?
    var onRequest: ((String) -> Void)?
    var visualization: VoiceInputVisualization {recognition.inputVisualization}

    static let greeting="네, 어떤 무대를 준비할까요?"
    private let recognition=VoiceRecognitionService()
    private let speech=GuidanceSpeech()
    private let chime=VoiceListeningChime()
    private var startTask: Task<Void,Never>?
    private var sleepTask: Task<Void,Never>?
    private var active=false

    init() {
        // Speak through the recognizer's engine so its echo cancellation hears the user over the greeting.
        speech.bufferedOutput={ [weak self] utterance, completion in
            self?.recognition.speakNarration(utterance,completion:completion) ?? false
        }
        speech.stopBufferedOutput={ [weak self] in self?.recognition.stopNarration() }
        speech.onSpeaking={ [weak self] value in self?.speaking=value }
        recognition.onTranscript={ [weak self] text in self?.heardPartial(text) }
        recognition.onFinal={ [weak self] text in self?.heardFinal(text) }
        // A permission or dictation failure shows a fallback button; the next visit to Home tries again.
        recognition.onError={ [weak self] message in self?.active=false;self?.failure=message;self?.sleep() }
        recognition.$isListening.receive(on:RunLoop.main).assign(to:&$listening)
    }

    func start() {
        guard !active else {return}
        active=true;failure=nil
        startTask=Task { [weak self] in
            guard let self, self.active else {return}
            await self.recognition.start(contextualStrings:VoiceWakeWord.hints,vocabulary:VoiceVocabulary.phrases(),listensForWakeWord:true)
            // Asleep, Home listens in English for 「Hear I am」 only (#92).
            if self.active, !self.awake {self.recognition.listenInEnglish(true)}
        }
    }

    func stop() {
        sleep()
        guard active else {return}
        active=false
        startTask?.cancel();startTask=nil
        recognition.stop()
    }

    private func heardPartial(_ text:String) {
        guard active else {return}
        guard !awake, VoiceWakeWord.matches(text) else {return}
        // Switching to Korean ends this English turn, so the greeting cannot wait for its final text.
        wake();greet()
    }

    private func heardFinal(_ text:String) {
        guard active else {return}
        // The call may sit in a lower recognition candidate (#92).
        let call=([text]+recognition.lastAlternatives).lazy.compactMap(VoiceWakeWord.request(in:)).first
        if let request=call {
            if !awake {wake()}
            if request.isEmpty {if !speaking {greet()}} else {hand(request)}
            return
        }
        guard awake, !recognition.listensInEnglish else {return}
        hand(text)
    }

    private func wake() {
        awake=true
        speech.stop()
        recognition.listenInEnglish(false)
        chime.play()
        stayAwake(8)
    }

    private func greet() {
        stayAwake(60)
        speech.play([Self.greeting]) { [weak self] _ in self?.stayAwake(8) }
    }

    private func hand(_ request:String) {
        stop()
        onRequest?(request)
    }

    /// A tap closes the agent and goes back to waiting for 「Hear I am」.
    func dismiss() {
        guard awake else {return}
        sleep()
    }

    private func stayAwake(_ seconds:Double) {
        sleepTask?.cancel()
        sleepTask=Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
            guard !Task.isCancelled else {return}
            self?.sleep()
        }
    }

    private func sleep() {
        sleepTask?.cancel();sleepTask=nil
        if speaking {speech.stop()}
        awake=false
        if active {recognition.listenInEnglish(true)}
    }
}
