import SwiftUI
import HearIAmCore

/// Performer-only home. The white orb is also an accessible manual entry to voice conversation.
struct HomeView: View {
    @ObservedObject var library:StageLibrary
    @ObservedObject var wake:VoiceWakeListener
    let start:()->Void
    var changeRole:(()->Void)? = nil
    @State private var showingSettings=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            GeometryReader {geometry in
                ZStack(alignment:.bottom) {
                    HearV3.canvas.ignoresSafeArea()
                    Image("HearV3Ambient").resizable().scaledToFill().frame(width:geometry.size.width,height:280).clipped()
                        .opacity(wake.awake ? 1 : 0.55).ignoresSafeArea(edges:.bottom).accessibilityHidden(true)
                    ScrollView {
                        VStack(spacing:24) {
                            Spacer(minLength:44)
                            Button {wake.beginConversation()} label: {
                                Image("HearV3Orb").resizable().scaledToFit().frame(width:144,height:144)
                                    .scaleEffect(wake.speaking && !reduceMotion ? 1.08 : 1)
                                    .animation(.easeInOut(duration:0.4),value:wake.speaking)
                            }.buttonStyle(.plain).accessibilityLabel("눌러서 말하기")
                                .accessibilityHint("호출어 없이 음성 대화를 시작해요")
                                .accessibilityIdentifier("home.voice.orb")
                            VStack(spacing:12) {
                                Text(wake.awake ? (wake.speaking ? "말하고 있어요" : "듣고 있어요") : "이렇게 불러주세요")
                                    .font(.headline).foregroundStyle(HearV3.secondary)
                                Text(wake.awake ? "어떤 공연을 찾으시나요?" : "“Hear I am”")
                                    .font(.largeTitle.bold()).multilineTextAlignment(.center)
                                Text(wake.awake ? "공연 이름이나 공연장 이름을 말씀해주세요." : "띠링·인사를 들은 뒤\n한국어로 요청해주세요.")
                                    .foregroundStyle(HearV3.secondary).multilineTextAlignment(.center)
                            }.fixedSize(horizontal:false,vertical:true)
                            VStack(alignment:.leading,spacing:8) {
                                Text("이렇게 요청할 수 있어요").font(.headline)
                                Text("“Lion King 연습할래”\n“효자아트홀에 저장된 공연 찾아줘”").font(.subheadline).foregroundStyle(HearV3.secondary)
                            }.v3Card(inset:16)
                            if let failure=wake.failure {
                                VStack(spacing:12) {
                                    Text(failure).font(.subheadline).multilineTextAlignment(.center)
                                    Button("버튼으로 무대 선택하기",action:start).buttonStyle(V3PrimaryButtonStyle())
                                        .accessibilityIdentifier("home.voice.start")
                                }.v3Card(inset:16)
                            } else {
                                Label(wake.awake ? "한국어로 요청을 듣고 있어요" : "호출을 기다리고 있어요",systemImage:"mic")
                                    .font(.subheadline).frame(maxWidth:.infinity,alignment:.leading).v3Card(inset:16)
                            }
                            Button("저장된 공연에서 직접 선택",action:start).font(.subheadline).frame(minHeight:48)
                                .accessibilityIdentifier("home.stage.list")
                            Spacer(minLength:20)
                        }.padding(20).frame(minHeight:geometry.size.height)
                    }.scrollBounceBehavior(.basedOnSize)
                }.frame(width:geometry.size.width,height:geometry.size.height)
            }
            .navigationTitle("Hear I am").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button {showingSettings=true} label: {Image(systemName:"gearshape")}
                        .accessibilityLabel("설정").accessibilityIdentifier("home.settings")
                }
                if wake.awake {
                    ToolbarItem(placement:.topBarLeading) {
                        Button("대화 닫기") {wake.dismiss()}.accessibilityIdentifier("home.voice.close")
                    }
                }
            }
            .navigationDestination(isPresented:$showingSettings) {
                HomeSettingsView(role:.performer,changeRole:changeRole).suspendsVoiceWake()
            }
            .overlay {VoiceEdgeGlow(visualization:wake.visualization,active:wake.awake)}
            .v3Screen()
        }.preferredColorScheme(.dark)
    }
}
