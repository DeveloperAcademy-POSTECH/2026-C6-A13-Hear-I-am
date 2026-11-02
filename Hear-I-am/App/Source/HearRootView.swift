import SwiftUI
import HearIAmCore

/// A role belongs to this app session, never to persistent preferences.
struct HearRootView: View {
    @StateObject private var library=StageLibrary()
    @StateObject private var wake=VoiceWakeListener()
    @ObservedObject private var launch=VoiceLaunch.shared
    @ObservedObject private var gate=VoiceWakeGate.shared
    @ObservedObject private var scanTransition=ScanTransition.shared
    @State private var showsLaunch=true
    @State private var role:HearRole?
    @State private var tab=0
    @State private var selectedPerformanceID:UUID?
    @State private var guidance:VoiceGuidanceLaunch?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let role {
                if role == .performer {
                    HomeView(library:library,wake:wake,start:{open(VoiceGuidanceLaunch())},changeRole:chooseRole,isPresented:guidance == nil)
                } else {helperTabs}
            } else {
                // The role page plays the launch logo itself the first time (see RoleSelectionView.runLaunch).
                RoleSelectionView(animatesLaunch:showsLaunch) {role=$0;tab=0;openSiriRequest();syncWake()}
            }
        }
        // Black over tabs and bars while the scan screen comes and goes (see ScanTransition).
        .overlay {ScanVeil(on:scanTransition.veiled)}
        .fullScreenCover(item:$guidance,onDismiss:{openSiriRequest();syncWake()}) {request in
            GuidanceView(library:library,voiceExperiment:true,request:request.request,
                         stageID:request.stageID,mode:request.mode,helperPreparation:request.helperPreparation,
                         openPlans:{guidance=nil;openHelper(tab:1)},openScan:{guidance=nil;openHelper(tab:0)})
        }
        .onAppear {
            wake.onRequest={text in
                switch VoiceAppRequest.resolve(text) {
                case .plans?: wake.answer(["공연 관리는 조력자 화면에서 사용할 수 있어요."]) {openHelper(tab:1)}
                case .scan?: wake.answer(VoiceAppRequest.scanAnswer) {openHelper(tab:0)}
                case nil:open(VoiceGuidanceLaunch(request:VoiceAppRequest.isRehearsal(text) ? nil : text))
                }
            }
            syncWake()
            #if DEBUG
            VoiceTestInbox.shared.home={text in wake.simulateHeard(text)}
            VoiceTestInbox.shared.start()
            #endif
        }
        .onChange(of:launch.pending) {openSiriRequest()}
        .onChange(of:gate.open) {openSiriRequest();syncWake()}
        .onChange(of:scenePhase) {syncWake()}
        .onChange(of:role) {syncWake()}
        .onChange(of:library.records.map(\.id)) {HearShortcuts.updateAppShortcutParameters()}
        .task {
            await library.refresh()
            HearShortcuts.updateAppShortcutParameters()
        }
        .task {
            guard showsLaunch else {return}
            // Long enough for the launch logo's loop, second draw-in and rise (it never repeats after that).
            try? await Task.sleep(for:.seconds(RoleSelectionView.launchDuration))
            guard !Task.isCancelled else {return}
            showsLaunch=false
        }
        .alert("확인이 필요해요",isPresented:Binding(get:{library.error != nil},set:{if !$0 {library.error=nil}})) {
            Button("확인",role:.cancel) {library.error=nil}
        } message: {Text(library.error ?? "")}
    }

    private var helperTabs: some View {
        TabView(selection:$tab) {
            HelperScanHomeView(library:library) {id in selectedPerformanceID=id;tab=1}
                .tabItem {Label("스캔",systemImage:"camera")}.tag(0)
            PerformanceLibraryView(library:library,selectedPerformanceID:$selectedPerformanceID) {stageID in
                open(VoiceGuidanceLaunch(stageID:stageID,mode:.performance,helperPreparation:true))
            }.tabItem {Label("공연 관리",systemImage:"folder")}.tag(1)
            GuidanceRecordsView(library:library).tabItem {Label("기록",systemImage:"clock")}.tag(2)
        }.tint(HearV3.text).preferredColorScheme(.dark)
            .environment(\.hearChangeRole,chooseRole)
    }
    private func chooseRole() {wake.stop();role=nil;selectedPerformanceID=nil}
    private func openHelper(tab:Int) {wake.stop();role = .helper;self.tab=tab}
    private func open(_ value:VoiceGuidanceLaunch) {wake.stop();guidance=value}
    private func openSiriRequest() {
        guard !showsLaunch,role != nil,let value=launch.pending,guidance == nil,gate.open else {return}
        launch.pending=nil
        let helper=role == .helper
        open(VoiceGuidanceLaunch(stageID:value.stageID,mode:helper ? .performance : value.mode,helperPreparation:helper))
    }
    private func syncWake() {
        if !showsLaunch,role == .performer,scenePhase == .active,guidance == nil,gate.open {wake.start()}
        else {wake.stop()}
    }
}

private struct HearChangeRoleKey: EnvironmentKey {static let defaultValue:(()->Void)? = nil}
extension EnvironmentValues {
    var hearChangeRole:(()->Void)? {
        get {self[HearChangeRoleKey.self]}
        set {self[HearChangeRoleKey.self]=newValue}
    }
}
