import SwiftUI
import HearIAmCore

/// Performer-only home. The orb also opens voice conversation without a wake phrase.
/// Once called, the screen becomes the start of the conversation (Figma 495:5074 · 5096): the question
/// under the logo, then the request as a bubble while the app finds the performance.
struct HomeView: View {
    @ObservedObject var library:StageLibrary
    @ObservedObject var wake:VoiceWakeListener
    let start:()->Void
    var changeRole:(()->Void)? = nil
    var isPresented=true
    @State private var showingSettings=false
    @State private var isVisible=false
    @State private var heardAt=Date()
    @Environment(\.scenePhase) private var scenePhase

    private var animating:Bool {isPresented && isVisible && !showingSettings && scenePhase == .active}
    private var hasRequest:Bool {!wake.caption.transcript.isEmpty}

    var body: some View {
        NavigationStack {
            GeometryReader {geometry in
                ZStack(alignment:.bottom) {
                    (wake.awake ? VoiceStyle.canvas : HearV3.canvas).ignoresSafeArea()
                    if wake.awake {
                        VoiceBloom(animating:animating).ignoresSafeArea()
                    } else {
                        HomeVoiceWaves(awake:false,animating:animating)
                            .frame(width:geometry.size.width,height:320 + geometry.safeAreaInsets.bottom)
                            .offset(y:geometry.safeAreaInsets.bottom)
                    }
                    if wake.awake {
                        awakeContent
                    } else {
                        ScrollView {
                            VStack(spacing:24) {idleContent}.padding(20)
                        }.scrollBounceBehavior(.basedOnSize).clipped()
                    }
                }.frame(width:geometry.size.width,height:geometry.size.height)
            }
            .navigationTitle(wake.awake ? "" : "Hear I am").navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(wake.awake ? .hidden : .automatic,for:.navigationBar)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button {showingSettings=true} label: {Image(systemName:"gearshape")}
                        .accessibilityLabel("설정").accessibilityIdentifier("home.settings")
                }
                if wake.awake {
                    ToolbarItem(placement:.topBarLeading) {
                        VoiceBackButton {wake.dismiss()}.accessibilityIdentifier("home.voice.close")
                    }
                }
            }
            .navigationDestination(isPresented:$showingSettings) {
                HomeSettingsView(role:.performer,changeRole:changeRole).suspendsVoiceWake()
            }
            .onAppear {isVisible=true}
            .onDisappear {isVisible=false}
            .onChange(of:hasRequest) {_,heard in if heard {heardAt=Date()}}
            .animation(.easeInOut(duration:0.3),value:wake.awake)
            .v3Screen()
        }.preferredColorScheme(.dark)
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
                    VoiceStatusRow(text:wake.confirmingInput ? "말씀하신 공연을 찾고 있어요" : "듣고 있어요")
                }
                .padding(.horizontal,16).padding(.top,32).padding(.bottom,48)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
            .accessibilityIdentifier("home.voice.caption.text")
        } else {
            VoiceWaitingPrompt(animating:animating)
                .accessibilityIdentifier("home.voice.caption.status")
                .overlay(alignment:.bottom) {
                    // Opened by hand while the microphone cannot be used, the reason shows here (not back on the waiting screen).
                    if let failure=wake.failure {
                        Text(failure).font(.system(size:15)).foregroundStyle(VoiceStyle.status).multilineTextAlignment(.center)
                            .padding(.horizontal,32).padding(.bottom,120)
                            .accessibilityIdentifier("home.voice.failure")
                    }
                }
        }
    }

    private var idleContent:some View {
        Group {
            Spacer(minLength:28)
            Button {wake.beginConversation()} label: {
                HomeVoiceOrb(awake:false,speaking:false,animating:animating)
            }.buttonStyle(.plain).accessibilityLabel("눌러서 말하기")
                .accessibilityHint("호출어 없이 음성 대화를 시작해요")
                .accessibilityIdentifier("home.voice.orb")
            VStack(spacing:12) {
                Text("이렇게 불러주세요").font(.headline).foregroundStyle(HearV3.secondary)
                Text("“Hear I am”").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("띠링·인사를 들은 뒤\n한국어로 요청해주세요.")
                    .foregroundStyle(HearV3.secondary).multilineTextAlignment(.center)
            }.fixedSize(horizontal:false,vertical:true)
            Button(action:start) {
                HStack(spacing:12) {
                    Image(systemName:"folder")
                    Text("저장된 공연에서 직접 선택").multilineTextAlignment(.leading)
                    Spacer(minLength:0)
                    Image(systemName:"chevron.right").font(.footnote.weight(.semibold))
                }
            }.buttonStyle(HomePerformanceButtonStyle()).accessibilityIdentifier("home.stage.list")
            VStack(alignment:.leading,spacing:8) {
                Text("이렇게 요청할 수 있어요").font(.headline)
                Text("“Lion King 연습할래”\n“효자아트홀에 저장된 공연 찾아줘”").font(.subheadline).foregroundStyle(HearV3.secondary)
            }.v3Card(inset:16)
            if let failure=wake.failure {
                Text(failure).font(.subheadline).multilineTextAlignment(.center).v3Card(inset:16)
                    .accessibilityIdentifier("home.voice.failure")
            } else {
                Label("호출을 기다리고 있어요",systemImage:"mic")
                    .font(.subheadline).frame(maxWidth:.infinity,alignment:.leading).v3Card(inset:16)
            }
            Spacer(minLength:20)
        }
    }
}

private struct HomePerformanceButtonStyle: ButtonStyle {
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .foregroundStyle(HearV3.text).padding(.horizontal,20).padding(.vertical,18)
            .frame(maxWidth:.infinity,minHeight:56)
            .background(HearV3.raised,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).strokeBorder(.white.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
