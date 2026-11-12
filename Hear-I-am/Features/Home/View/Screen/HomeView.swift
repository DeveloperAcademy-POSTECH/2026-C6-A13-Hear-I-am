import SwiftUI
import HearIAmCore

/// Performer-only home (Figma 971:36998): the stroke logo over 「오늘은 어떤 공연을 연습할까요?」 and
/// 「HearIam을 불러주세요」 on the dark canvas with the three lights below. Calling 「Hear I am」 (or tapping
/// the question) keeps this very screen and starts listening: the grey line turns to 「듣고 있어요」, and the
/// request then appears as a bubble while the app finds the performance (495:5074 · 5096).
struct HomeView: View {
    @ObservedObject var library:StageLibrary
    @ObservedObject var wake:VoiceWakeListener
    let start:()->Void
    var isPresented=true
    @State private var showingSettings=false
    @State private var isVisible=false
    @State private var heardAt=Date()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.hearChangeRole) private var changeRole

    private var animating:Bool {isPresented && isVisible && !showingSettings && scenePhase == .active}
    private var hasRequest:Bool {!wake.caption.transcript.isEmpty}

    var body: some View {
        NavigationStack {
            ZStack {
                VoiceStyle.canvas.ignoresSafeArea()
                VoiceBloom(animating:animating).ignoresSafeArea()
                if wake.awake && (hasRequest || !wake.answerLines.isEmpty) {awakeContent} else {prompt}
            }
            .hearTopBar(nil) {
                if wake.awake {
                    Button {wake.dismiss()} label: {HearTopButtonLabel(systemImage:"chevron.left")}
                        .accessibilityLabel(L("뒤로")).accessibilityIdentifier("home.voice.close")
                } else {
                    Button {changeRole?()} label: {HearTopButtonLabel(systemImage:"house")}
                        .accessibilityLabel(L("처음 화면")).accessibilityIdentifier("home.role")
                }
            } trailing: {
                // Not in 971:36998; kept so the performer still reaches sound and permission settings.
                Button {showingSettings=true} label: {HearTopButtonLabel(systemImage:"gearshape")}
                    .accessibilityLabel(L("설정")).accessibilityIdentifier("home.settings")
            }
            .navigationDestination(isPresented:$showingSettings) {
                HomeSettingsView().suspendsVoiceWake()
            }
            .onAppear {isVisible=true}
            .onDisappear {isVisible=false}
            .onChange(of:hasRequest) {_,heard in if heard {heardAt=Date()}}
            .animation(.easeInOut(duration:0.3),value:wake.awake)
            .v3Screen()
        }.preferredColorScheme(.dark)
    }

    /// One screen before and after the call: only the grey line changes, so calling feels like the same
    /// conversation going on. A tap anywhere on it starts listening without the wake phrase.
    private var prompt:some View {
        VoiceWaitingPrompt(subtitle:wake.awake ? L("듣고 있어요") : L("Hear I am을 불러주세요"),animating:animating)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {if !wake.awake {wake.beginConversation()}}
            .accessibilityAddTraits(wake.awake ? [] : .isButton)
            .accessibilityHint(wake.awake ? "" : L("눌러서 호출어 없이 말하기"))
            .accessibilityIdentifier(wake.awake ? "home.voice.caption.status" : "home.voice.orb")
            // The design has no list button; the saved performances stay one VoiceOver action away.
            .accessibilityAction(named:L("저장된 공연에서 직접 선택"),start)
            .overlay(alignment:.bottom) {
                if let failure=wake.failure {
                    Text(failure).font(.system(size:15)).foregroundStyle(VoiceStyle.status).multilineTextAlignment(.center)
                        .padding(.horizontal,32).padding(.bottom,120)
                        .accessibilityIdentifier("home.voice.failure")
                }
            }
    }

    /// 495:5074 until the performer speaks, then 495:5096: the words as a bubble over the spinner line.
    @ViewBuilder private var awakeContent:some View {
        if !wake.answerLines.isEmpty {
            // A request Home answers itself (스캔, 공연 관리): the words, then the answer, before that screen opens.
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    if let request=wake.answerRequest {VoiceUserBubble(text:request,date:heardAt)}
                    VoiceAppLine(text:wake.answerLines.joined(separator:" "),date:Date())
                }
                .padding(.horizontal,16).padding(.top,32).padding(.bottom,48)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
        } else if hasRequest {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    VoiceUserBubble(text:wake.caption.transcript,date:heardAt,showsMeta:!wake.listening || wake.confirmingInput,typing:true)
                    VoiceStatusRow(text:wake.confirmingInput ? L("말씀하신 공연을 찾고 있어요") : L("듣고 있어요"))
                }
                .padding(.horizontal,16).padding(.top,32).padding(.bottom,48)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
            .accessibilityIdentifier("home.voice.caption.text")
        }
    }
}
