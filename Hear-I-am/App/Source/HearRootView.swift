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
    /// A spoken scan request opens the scan screen itself once the helper tabs are up.
    @State private var scanRequested=false
    @State private var guidance:VoiceGuidanceLaunch?
    /// A shared stage file opened from Files, Messages or AirDrop, waiting until the app can show it (#218).
    @State private var pendingShare:StageShareIncoming?
    @State private var receiving:StageShareIncoming?
    @State private var shareToast:String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let role {
                if role == .performer {
                    // The performer's conversation takes Home's place in the same window, like one chat,
                    // rather than a new screen sliding up over it (11/03).
                    if let request=guidance, !request.helperPreparation {
                        guidanceView(request).id(request.id)
                    } else {
                        HomeView(library:library,wake:wake,start:{open(VoiceGuidanceLaunch())},isPresented:guidance == nil)
                            .environment(\.hearChangeRole,chooseRole)
                    }
                } else if let request=guidance, request.helperPreparation {
                    // The helper's guidance takes the tabs' place too, as the performer's takes Home's (#175). Opened
                    // as a cover over the space page, whose 3D stage stays alive underneath, the saved space was never
                    // found (11/11 POS: 0 of 9 from the helper, 5 of 5 by voice at the same place).
                    guidanceView(request).id(request.id)
                } else {helperTabs}
            } else {
                // The role page plays the launch logo itself the first time (see RoleSelectionView.runLaunch).
                RoleSelectionView(animatesLaunch:showsLaunch) {role=$0;tab=0;openSiriRequest();syncWake()}
            }
        }
        // Black over tabs and bars while the scan screen comes and goes (see ScanTransition).
        .overlay {ScanVeil(on:scanTransition.veiled)}
        .overlay(alignment:.top) {
            if let shareToast {StageShareToast(text:shareToast).transition(.move(edge:.top).combined(with:.opacity))}
        }
        .onOpenURL {url in
            guard url.isFileURL,url.pathExtension.lowercased()==StageShare.fileExtension else {return}
            openShare(url)
        }
        .onChange(of:showsLaunch) {showPendingShare()}
        .onChange(of:guidance?.id) {showPendingShare()}
        .sheet(item:$receiving) {incoming in
            StageShareReceiveSheet(library:library,incoming:incoming) {result,_ in shareSaved(result)}.suspendsVoiceWake()
        }
        .environment(\.hearShareSaved,shareSaved)
        .environment(\.hearOpenShare,openShare)
        .onAppear {
            wake.onRequest={text in
                switch VoiceAppRequest.resolve(text) {
                case .plans?: wake.answer(VoiceAppRequest.plansHandoff,request:text) {openHelper(tab:1)}
                case .scan?: wake.answer(VoiceAppRequest.scanAnswer,request:text) {openScan()}
                case nil:
                    // 「연습용」 on Home is the mode too, so it is not asked again after the stage (#156).
                    let rehearsal=VoiceAppRequest.isRehearsal(text)
                    open(VoiceGuidanceLaunch(request:rehearsal ? nil : text,heard:text,mode:rehearsal ? .practice : nil))
                }
            }
            syncWake()
            #if DEBUG
            VoiceTestInbox.shared.home={text in wake.simulateHeard(text)}
            VoiceTestInbox.shared.start()
            // Device check of the dictation probe (#189) without opening Settings > 권한 상태 by hand.
            if ProcessInfo.processInfo.arguments.contains("--dictation-check") {
                Task {_ = await DictationProbe().run(localeCode:HearLanguage.current.speechCode)}
            }
            #endif
        }
        .onChange(of:launch.pending) {openSiriRequest()}
        .onChange(of:gate.open) {openSiriRequest();syncWake()}
        .onChange(of:scenePhase) {
            syncWake()
            if scenePhase == .active {DiagnosticLogMaintenance.schedule(force:true)}
        }
        .onChange(of:role) {syncWake()}
        .onChange(of:library.voiceMetadata) {HearShortcuts.updateAppShortcutParameters()}
        .task {
            // Before the first load: a stage whose replacement stopped part way is put back first (#218).
            await library.cleanUpSharing()
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
        .alert(L("확인이 필요해요"),isPresented:Binding(get:{library.error != nil},set:{if !$0 {library.error=nil}})) {
            Button(L("확인"),role:.cancel) {library.error=nil}
        } message: {Text(library.error ?? "")}
    }

    private func guidanceView(_ request:VoiceGuidanceLaunch) -> some View {
        GuidanceView(library:library,voiceExperiment:true,request:request.request,heard:request.heard,
                     stageID:request.stageID,mode:request.mode,helperPreparation:request.helperPreparation,
                     openPlans:{guidance=nil;openHelper(tab:1)},openScan:{guidance=nil;openScan()},
                     onClose:{guidance=nil;openSiriRequest();syncWake()})
    }

    private var helperTabs: some View {
        TabView(selection:$tab) {
            HelperScanHomeView(library:library,startNow:$scanRequested) {id in selectedPerformanceID=id;tab=1}
                .tabItem {HelperTab.label(L("스캔"),systemImage:"viewfinder")}.tag(0)
            PerformanceLibraryView(library:library,selectedPerformanceID:$selectedPerformanceID) {stageID in
                open(VoiceGuidanceLaunch(stageID:stageID,mode:.performance,helperPreparation:true))
            }.tabItem {HelperTab.label(L("공연 관리"),systemImage:"folder")}.tag(1)
            GuidanceRecordsView(library:library).tabItem {HelperTab.label(L("기록"),systemImage:"clock")}.tag(2)
        }.tint(HearV3.text).preferredColorScheme(.dark)
            .environment(\.hearChangeRole,chooseRole)
    }
    /// Opens a received file once the launch logo is gone and no guidance is running. Saving goes to the helper's
    /// performance list, so the helper side is opened under it.
    private func showPendingShare() {
        guard !showsLaunch,guidance == nil,receiving == nil,let incoming=pendingShare else {return}
        pendingShare=nil
        if role != .helper {openHelper(tab:1)}
        receiving=incoming
    }
    private func openShare(_ url:URL) {
        do {
            if let old=pendingShare {StageLibrary.finishReceiving(old)}
            pendingShare=try StageLibrary.receive(url)
            // The file picker is still closing when it reports; a sheet asked for now would not appear.
            Task {try? await Task.sleep(for:.seconds(0.6)); showPendingShare()}
        } catch {library.error=L("받은 파일을 열지 못했어요: %@",error.localizedDescription)}
    }
    /// After a received file is saved: its performance opens and a line says what was saved.
    private func shareSaved(_ result:StageShareResult) {
        selectedPerformanceID=result.performanceID
        openHelper(tab:1)
        withAnimation(.spring(duration:0.35)) {shareToast=StageShareToast.message(result)}
        Task {
            try? await Task.sleep(for:.seconds(3.5))
            withAnimation(.easeOut(duration:0.3)) {shareToast=nil}
        }
    }
    private func chooseRole() {wake.stop();role=nil;selectedPerformanceID=nil}
    private func openHelper(tab:Int) {wake.stop();role = .helper;self.tab=tab}
    private func openScan() {scanRequested=true;openHelper(tab:0)}
    /// The performer's conversation carries on from Home in place, like one chat, instead of a new screen
    /// sliding up over it (11/03). The helper's guidance takes the tabs' place in the same way (#175).
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

/// The helper's tab bar items (Figma 971:24154): outline symbols in every state. The system tab bar would
/// switch a selected item to its filled symbol; the design keeps the outline and marks the selection with the bar's own highlight.
enum HelperTab {
    static func label(_ title:String,systemImage:String) -> some View {
        Label(title,systemImage:systemImage).environment(\.symbolVariants,.none)
    }
}

private struct HearChangeRoleKey: EnvironmentKey {static let defaultValue:(()->Void)? = nil}
extension EnvironmentValues {
    var hearChangeRole:(()->Void)? {
        get {self[HearChangeRoleKey.self]}
        set {self[HearChangeRoleKey.self]=newValue}
    }
}
