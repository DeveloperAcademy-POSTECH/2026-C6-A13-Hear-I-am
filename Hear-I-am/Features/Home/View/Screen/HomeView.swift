import SwiftUI
import HearIAmCore

/// Voice-first home. Scan preparation and saved performances remain in the Places tab.
struct HomeView: View {
    @ObservedObject var library: StageLibrary
    /// The call is heard app-wide (HearRootView); Home shows the agent's state and the button fallback.
    @ObservedObject var wake: VoiceWakeListener
    let start: () -> Void
    @State private var showingSettings=false
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
                        // Voice only: no start button. Calling the app name wakes the agent here (#90); the light
                        // around the screen edge is the only sign that it listens.
                        VStack(spacing:32) {
                            VStack(spacing:12) {
                                Text("이렇게 불러주세요").font(.headline).foregroundStyle(.secondary)
                                Text("“\(VoiceWakeWord.phrase)”")
                                    .font(.system(size:headingSize,weight:.bold))
                                    .minimumScaleFactor(0.6).lineLimit(1)
                                Text("무대 고르기부터 출발까지\n말로 이어서 진행해요")
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
                                Button("버튼으로 시작") {start()}.font(.headline).frame(minHeight:44)
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
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView().suspendsVoiceWake()}
        }
    }
}
