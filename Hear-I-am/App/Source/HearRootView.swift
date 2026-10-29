import SwiftUI
import HearIAmCore

struct HearRootView: View {
    @StateObject private var library=StageLibrary()
    /// The call is heard on every tab, not only Home (#90).
    @StateObject private var wake=VoiceWakeListener()
    @ObservedObject private var launch=VoiceLaunch.shared
    @ObservedObject private var gate=VoiceWakeGate.shared
    @State private var tab=0
    @State private var guidance: VoiceGuidanceLaunch?
    /// The logo animation on a cold start (HearSplashView). Turned off for now (10/29); set to true to bring it back.
    @State private var splash=false
    /// Set when the agent was asked for a new scan; the 장소 tab opens it once its places are loaded.
    @State private var voiceScan=false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TabView(selection:$tab) {
            HomeView(library:library,wake:wake) {open(VoiceGuidanceLaunch())}.tabItem {Label("홈",systemImage:"house.fill")}.tag(0)
            PlacesView(library:library,voiceScan:$voiceScan).tabItem {Label("장소",systemImage:"folder.fill")}.tag(1)
            PlanLibraryView(library:library).tabItem {Label("공연 사전 저장",systemImage:"map")}.tag(2)
            GuidanceRecordsView(library:library)
                .tabItem {Label("기록",systemImage:"clock")}.tag(3)
        }.tint(.hearInk).preferredColorScheme(.light)
            // The call and Siri open guidance over whichever tab is showing (#90, #91). An item, not a flag,
            // so the screen gets the request it was opened with rather than the value from before.
            // A Siri request that came while guidance was open waits for it to close.
            .fullScreenCover(item:$guidance,onDismiss:{openSiriRequest();syncWake()}) { launch in
                GuidanceView(library:library,voiceExperiment:true,request:launch.request,stageID:launch.stageID,mode:launch.mode) {
                    guidance=nil;showPlans()
                } openScan: {
                    guidance=nil;showScan()
                }
            }
            // The agent shows as light around the screen edge; a tap anywhere while it listens closes it.
            .overlay {VoiceEdgeGlow(visualization:wake.visualization,active:wake.awake)}
            .overlay {if wake.awake {VoiceDismissLayer {wake.dismiss()}}}
            .overlay {if splash {HearSplashView {splash=false}}}
            .onAppear {
                wake.onRequest={ text in
                    switch VoiceAppRequest.resolve(text) {
                    case .plans?:showPlans()
                    case .scan?:showScan()
                    case nil:open(VoiceGuidanceLaunch(request:text))
                    }
                }
                syncWake()
            }
            .onChange(of:launch.pending) {openSiriRequest()}
            .onChange(of:gate.open) {openSiriRequest();syncWake()}
            .onChange(of:scenePhase) {syncWake()}
            .onChange(of:splash) {syncWake()}
            // Siri phrases that name a stage only know the stages it was last told about.
            .onChange(of:library.records.map(\.id)) {HearShortcuts.updateAppShortcutParameters()}
            .task {
                await library.refresh()
                // Re-register Siri phrases on every launch; Shortcuts did not list them on Ian's phone (10/28).
                HearShortcuts.updateAppShortcutParameters()
            }
            .alert("확인이 필요해요",isPresented:Binding(get:{library.error != nil},set:{if !$0 {library.error=nil}})) {
                Button("확인",role:.cancel) {library.error=nil}
            } message: {Text(library.error ?? "")}
    }

    private func open(_ launch: VoiceGuidanceLaunch) {
        wake.stop()
        guidance=launch
    }
    /// 「사전 저장된 공연 보여줘」 opens the 공연 사전 저장 tab and reads what is there.
    private func showPlans() {
        tab=2
        wake.answer(VoiceAppRequest.plansAnswer(names:library.plans.map(\.name)))
    }
    /// 「새 스캔」 opens a scan from the 장소 tab. The helper scans with buttons and the scan screen stops
    /// listening, so the agent says so before it opens.
    private func showScan() {
        tab=1
        wake.answer(VoiceAppRequest.scanAnswer) {voiceScan=true}
    }
    /// A Siri request waits while another screen covers the tabs, then opens guidance.
    private func openSiriRequest() {
        guard let value=launch.pending, guidance == nil, gate.open else {return}
        launch.pending=nil
        open(VoiceGuidanceLaunch(stageID:value.stageID,mode:value.mode))
    }
    private func syncWake() {
        // The microphone permission prompt waits until the logo animation is over.
        if scenePhase == .active && guidance == nil && gate.open && !splash {wake.start()}
        else {wake.stop()}
    }
}
