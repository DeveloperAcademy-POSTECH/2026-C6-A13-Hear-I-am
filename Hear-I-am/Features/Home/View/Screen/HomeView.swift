import SwiftUI
import HearIAmCore

/// Voice-first home. Scan preparation and saved performances remain in the Places tab.
struct HomeView: View {
    @ObservedObject var library: StageLibrary
    @State private var showingSettings=false
    @State private var showingVoiceGuidance=false
    @ScaledMetric(relativeTo:.largeTitle) private var headingSize: CGFloat=36

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment:.leading,spacing:0) {
                        HStack {
                            Text("Hear I am").font(.largeTitle.bold())
                            Spacer()
                            Button {showingSettings=true} label: {
                                Image(systemName:"gearshape").font(.title2)
                                    .frame(width:44,height:44)
                                    .background(Color(.systemGray6),in:Circle())
                            }.accessibilityLabel("설정").accessibilityIdentifier("home.settings")
                        }
                        Spacer(minLength:36)
                        Text("말로 안내를\n시작해보세요")
                            .font(.system(size:headingSize,weight:.bold))
                            .fixedSize(horizontal:false,vertical:true)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength:36)
                        voiceButton(diameter:min(270,geometry.size.width-64))
                            .frame(maxWidth:.infinity)
                        Text("버튼을 누르고\n사용할 무대 이름을 말해주세요")
                            .font(.body).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal:false,vertical:true)
                            .frame(maxWidth:.infinity).padding(.top,32)
                        Spacer(minLength:36)
                    }.padding(.horizontal,24).padding(.vertical,20)
                        .frame(minHeight:geometry.size.height,alignment:.top)
                }.scrollBounceBehavior(.basedOnSize)
            }
            .background(Color(.systemBackground))
            .navigationTitle("홈").toolbar(.hidden,for:.navigationBar)
            .toolbar(showingSettings ? .hidden : .visible,for:.tabBar)
            .navigationDestination(isPresented:$showingSettings) {HomeSettingsView()}
            .fullScreenCover(isPresented:$showingVoiceGuidance) {
                GuidanceView(library:library,voiceExperiment:true)
            }
        }
    }

    private func voiceButton(diameter:CGFloat) -> some View {
        Button {showingVoiceGuidance=true} label: {
            VStack(spacing:20) {
                Image(systemName:"mic.fill").font(.system(size:72,weight:.regular))
                Text("말로 안내 시작").font(.title3.bold())
                    .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            }.padding(28).frame(width:diameter,height:diameter)
                .foregroundStyle(.white).background(Color.hearInk,in:Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.08),lineWidth:1))
                .shadow(color:.black.opacity(0.13),radius:20,y:12)
                .contentShape(Circle())
        }.buttonStyle(.plain)
            .accessibilityLabel("말로 안내 시작")
            .accessibilityHint("저장한 무대를 음성이나 버튼으로 선택합니다")
            .accessibilityIdentifier("home.voice.start")
    }
}
