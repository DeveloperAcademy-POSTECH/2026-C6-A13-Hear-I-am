import SwiftUI
import AVFoundation
import Speech
import CoreMotion
import HearIAmCore

/// Pushed from Home. Settings and its children share Home's navigation stack (Figma 「설정」 457:14420).
/// Rows the design does not show yet (역할 · 방향 허용 각도 · 받아쓰기 엔진 · 음성으로 사용하기) stay, in the same style.
struct HomeSettingsView: View {
    var role:HearRole = .performer
    var changeRole:(()->Void)? = nil
    @State private var confirmsRoleChange=false
    @StateObject private var output=SoundOutputStatus()
    @AppStorage(VoiceRecognitionService.analyzerKey) private var speechAnalyzer=true
    private var version: String {Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""}
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                SettingsHeroCard().padding(.top,15).padding(.bottom,27)
                section("소리") {
                    NavigationLink { SoundOutputView() } label: {SettingsRowLabel(title:"소리 출력",value:output.name)}
                        .buttonStyle(.plain).accessibilityIdentifier("settings.output")
                }
                section("사용 도움말") {
                    NavigationLink {V3UsageHelpView()} label: {SettingsRowLabel(title:"착용과 안내 준비")}.buttonStyle(.plain)
                    SettingsDivider()
                    SettingsRowLabel(title:"소리가 들리지 않을 때",value:"준비 중",accessory:.none)
                    SettingsDivider()
                    NavigationLink {V3VoiceHelpView()} label: {SettingsRowLabel(title:"음성으로 사용하기")}.buttonStyle(.plain)
                }
                section("음성 인식") {
                    Toggle(isOn:$speechAnalyzer) {
                        VStack(alignment:.leading,spacing:4) {
                            Text("새 받아쓰기 엔진 (시험)").foregroundStyle(.white)
                            Text("iOS 26의 새 음성 인식을 써요. 다음에 음성 입력을 시작할 때부터 적용돼요.").font(.subheadline).foregroundStyle(SettingsStyle.secondary)
                        }
                    }.tint(.green).padding(.horizontal,SettingsStyle.rowInset).padding(.vertical,11).accessibilityIdentifier("settings.speechAnalyzer")
                }
                section("앱 관리") {
                    NavigationLink {V3PermissionView()} label: {SettingsRowLabel(title:"권한 상태")}.buttonStyle(.plain)
                    SettingsDivider()
                    NavigationLink {AppInfoView()} label: {SettingsRowLabel(title:"앱 정보",value:"Hear I am \(version)")}
                        .buttonStyle(.plain).accessibilityIdentifier("settings.appInfo")
                    if changeRole != nil {
                        SettingsDivider()
                        Button {confirmsRoleChange=true} label: {SettingsRowLabel(title:"사용 역할",value:role.title)}
                            .buttonStyle(.plain).accessibilityIdentifier("settings.role")
                    }
                }
            }.padding(.horizontal,20).padding(.bottom,24)
        }.settingsScreen()
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("사용 역할을 바꿀까요?",isPresented:$confirmsRoleChange,titleVisibility:.visible) {
                Button("역할 다시 선택") {changeRole?()}
                Button("취소",role:.cancel) {}
            } message: {Text("저장한 공연과 기록은 유지돼요.")}
            .toolbar(.visible,for:.navigationBar)
            .readsAloud {readAloudLines}
            .onAppear {output.refresh()}
    }
    /// Everything on the page, top to bottom, for the read-aloud button.
    private var readAloudLines: [String] {
        var lines=["설정","안내 신호 익히기","조력자와 하나씩 들어보세요","바로가기 버튼",
                   "소리","소리 출력, \(output.name)",
                   "사용 도움말","착용과 안내 준비","소리가 들리지 않을 때, 준비 중","음성으로 사용하기",
                   "음성 인식","새 받아쓰기 엔진 시험, \(speechAnalyzer ? "켜짐" : "꺼짐")","iOS 26의 새 음성 인식을 써요. 다음에 음성 입력을 시작할 때부터 적용돼요.",
                   "앱 관리","권한 상태","앱 정보, Hear I am \(version)"]
        if changeRole != nil {lines.append("사용 역할, \(role.title)")}
        return lines
    }
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing:0) {
            SettingsSectionHeader(title:title)
            SettingsGroup {content()}
        }.padding(.bottom,24)
    }
}

/// 「안내 신호 익히기」 card with the design's moving background (Liquid Metal + Light rays, see SettingsHeroShader.metal).
struct SettingsHeroCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start=Date()
    var body: some View {
        ZStack {
            TimelineView(.animation(paused:reduceMotion)) { context in
                let seconds=Float(context.date.timeIntervalSince(start))
                GeometryReader { geometry in
                    Rectangle().colorEffect(ShaderLibrary.settingsHero(.float2(geometry.size),.float(seconds)))
                }
            }
            // 58pt symbol, 26pt title, 16pt copy, then a 50pt capsule in plain Liquid Glass 14pt from the card's sides.
            VStack(spacing:0) {
                Image(systemName:"waveform").font(.system(size:44,weight:.regular)).foregroundStyle(.white)
                    .frame(width:58,height:58).accessibilityHidden(true)
                Text("안내 신호 익히기").font(.system(size:26,weight:.semibold)).foregroundStyle(.white).padding(.top,5)
                Text("조력자와 하나씩 들어보세요").font(.system(size:16)).foregroundStyle(.white.opacity(0.8)).padding(.top,3)
                NavigationLink {SoundTestView()} label: {
                    Text("바로가기").font(.system(size:17,weight:.semibold)).foregroundStyle(.white)
                        .frame(maxWidth:.infinity,minHeight:50)
                        .liquidGlass(Capsule())
                        .contentShape(Capsule())
                }.buttonStyle(.plain).padding(.top,28).accessibilityLabel("안내 신호 익히기 바로가기")
                    .accessibilityIdentifier("settings.tutorial")
            }.lineLimit(1).minimumScaleFactor(0.8).padding(.horizontal,14).padding(.vertical,28)
        }.frame(height:255).clipShape(RoundedRectangle(cornerRadius:34,style:.continuous))
            .environment(\.colorScheme,.dark)
    }
}

/// 「소리 출력」 (Figma 457:13432): output device, playback preference and a volume check.
struct SoundOutputView: View {
    @AppStorage(HearAudioSession.speakerKey) private var forcesSpeaker=false
    @StateObject private var output=SoundOutputStatus()
    @StateObject private var model=SoundTestViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let test=SignalTutorialExample("output-test","시험 소리 듣기","출발 준비 완료 때 들리는 띵 소리",playback:.arrival)
    var body: some View {
        ScrollView {
            VStack(spacing:0) {
                OutputDeviceHero(output:output)
                OutputDeviceRow(output:output).padding(.top,8).padding(.bottom,16)
                SettingsSectionHeader(title:"재생 방식")
                SettingsGroup {
                    option("연결된 기기로 자동",detail:"이어폰이 없으면 iPhone 스피커로 재생해요.",speaker:false)
                    SettingsDivider()
                    option("항상 iPhone 스피커",detail:"조력자와 함께 들을 때 사용해요.",speaker:true)
                }.padding(.bottom,16)
                SettingsSectionHeader(title:"소리 확인")
                SystemVolumeSlider().padding(.bottom,8)
                SettingsGroup {TutorialExampleRow(example:test,model:model)}
                if let error=model.error {TutorialPlaybackError(message:error).padding(.top,8)}
            }.padding(.horizontal,16).padding(.bottom,24)
        }.settingsScreen()
            .navigationTitle("소리 출력").navigationBarTitleDisplayMode(.inline)
            .readsAloud {
                model.stop()
                return ["소리 출력","출력 기기, \(output.name)","재생 방식",
                        "연결된 기기로 자동\(forcesSpeaker ? "" : ", 선택됨")","항상 iPhone 스피커\(forcesSpeaker ? ", 선택됨" : "")",
                        "소리 확인","음량 조절","\(test.title), \(test.detail)"]
            }
            .onAppear {model.appear();output.refresh()}.onDisappear {model.disappear()}
            .onChange(of:forcesSpeaker) {_,_ in model.outputPreferenceChanged();output.refresh()}
            .onChange(of:scenePhase) {_,phase in if phase != .active {model.stop()} else {output.refresh()} }
    }
    private func option(_ title: String, detail: String, speaker: Bool) -> some View {
        Button {forcesSpeaker=speaker} label: {
            SettingsRowLabel(title:title,accessory:forcesSpeaker == speaker ? .checkmark : .none)
        }.buttonStyle(.plain).accessibilityLabel(title).accessibilityHint(detail)
            .accessibilityAddTraits(forcesSpeaker == speaker ? [.isSelected] : [])
            .accessibilityIdentifier(speaker ? "output.speaker" : "output.auto")
    }
}

/// Read-only route information; opening settings never changes the user's audio session.
@MainActor final class SoundOutputStatus: ObservableObject {
    @Published private(set) var name="소리 출력 확인"
    @Published private(set) var detail="시험 소리를 재생해 출력 기기를 확인하세요."
    @Published private(set) var symbol="speaker.wave.2"
    @Published private(set) var kind: OutputDeviceKind = .iPhone
    private var observer: NSObjectProtocol?
    init() {
        refresh()
        observer=NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    deinit { if let observer {NotificationCenter.default.removeObserver(observer)} }
    func refresh() {
        let ports=AVAudioSession.sharedInstance().currentRoute.outputs
        kind=OutputDeviceKind(port:ports.first)
        guard !ports.isEmpty else {
            name="소리 출력 확인";detail="시험 소리를 재생해 출력 기기를 확인하세요.";symbol="speaker.wave.2";return
        }
        name=ports.map { port in
            switch port.portType {
            case .builtInSpeaker: return "iPhone 스피커"
            case .builtInReceiver: return "iPhone 수화부"
            default: return port.portName
            }
        }.joined(separator:", ")
        let headphones=ports.contains { [.headphones,.bluetoothA2DP,.bluetoothHFP,.bluetoothLE].contains($0.portType) }
        symbol=headphones ? "headphones" : "speaker.wave.2"
        detail=headphones ? "이어폰으로 소리를 재생해요." : "현재 소리가 나오는 기기예요."
    }
}
