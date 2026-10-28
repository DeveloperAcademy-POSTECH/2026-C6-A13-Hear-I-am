import SwiftUI
import AVFoundation
import HearIAmCore

/// Pushed from Home. Settings and its children share Home's navigation stack.
struct HomeSettingsView: View {
    @StateObject private var output=SoundOutputStatus()
    @AppStorage(VoiceRecognitionService.analyzerKey) private var speechAnalyzer=false
    var body: some View {
        List {
            Section {
                NavigationLink { SoundTestView() } label: {
                    HStack(spacing:14) {
                        Image(systemName:"waveform").font(.system(size:28)).frame(width:48,height:48)
                            .background(Color(.systemGray6),in:Circle()).accessibilityHidden(true)
                        VStack(alignment:.leading,spacing:6) {
                            Text("처음 사용하시나요?").font(.caption).foregroundStyle(.secondary)
                            Text("안내 신호 익히기").font(.headline)
                            Text("조력자와 함께 하나씩 들어보세요.").font(.subheadline).foregroundStyle(.secondary)
                        }.fixedSize(horizontal:false,vertical:true)
                    }.padding(.vertical,12)
                }.accessibilityIdentifier("settings.tutorial")
            }
            Section("소리") {
                NavigationLink { SoundOutputView() } label: {
                    Label {
                        VStack(alignment:.leading,spacing:4) {
                            Text("소리 출력")
                            Text(output.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {Image(systemName:"speaker.wave.2").accessibilityHidden(true)}
                    .padding(.vertical,4)
                }.accessibilityIdentifier("settings.output")
            }
            Section {
                Toggle(isOn:$speechAnalyzer) {
                    VStack(alignment:.leading,spacing:4) {
                        Text("새 받아쓰기 엔진 (시험)")
                        Text("iOS 26의 새 음성 인식을 써요. 다음에 음성 입력을 시작할 때부터 적용돼요.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("settings.speechAnalyzer")
            } header: {Text("음성 인식")}
            Section("사용 도움말") {
                SettingsPendingRow(title:"착용과 안내 준비",symbol:"person")
                SettingsPendingRow(title:"소리가 들리지 않을 때",symbol:"questionmark.circle")
            }
            Section("앱 관리") {
                SettingsPendingRow(title:"권한 상태",symbol:"checkmark.shield")
                SettingsPendingRow(title:"앱 정보",symbol:"info.circle")
            }
        }.listStyle(.insetGrouped).tint(.hearInk)
            .navigationTitle("설정").navigationBarTitleDisplayMode(.large)
            .toolbar(.visible,for:.navigationBar).toolbar(.hidden,for:.tabBar)
    }
}

private struct SettingsPendingRow: View {
    let title: String
    let symbol: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:6)) : AnyLayout(HStackLayout(spacing:12))) {
            Label(title,systemImage:symbol)
            if !typeSize.isAccessibilitySize { Spacer(minLength:8) }
            Text("준비 중").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical,8).frame(maxWidth:.infinity,alignment:.leading)
            .accessibilityElement(children:.ignore).accessibilityLabel(title).accessibilityValue("준비 중")
    }
}

struct SoundOutputView: View {
    @AppStorage(HearAudioSession.speakerKey) private var forcesSpeaker=false
    @StateObject private var output=SoundOutputStatus()
    @StateObject private var model=SoundTestViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let test=SignalTutorialExample("output-test","시험 소리 듣기","출발 준비 완료 때 들리는 띵 소리",playback:.arrival)
    var body: some View {
        List {
            Section("현재 출력") {
                Label {
                    VStack(alignment:.leading,spacing:5) {
                        Text(output.name).font(.headline)
                        Text(output.detail).font(.subheadline).foregroundStyle(.secondary)
                    }
                } icon: {Image(systemName:output.symbol).accessibilityHidden(true)}
                .padding(.vertical,10)
            }
            Section("재생 방식") {
                option("연결된 기기로 자동",detail:"이어폰이 없으면 iPhone 스피커로 재생해요.",speaker:false)
                option("항상 iPhone 스피커",detail:"조력자와 함께 들을 때 사용해요.",speaker:true)
            }
            Section {
                TutorialExampleRow(example:test,model:model)
                    .listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
            } footer: {
                Text("음량은 iPhone의 음량 버튼으로 조절하세요.")
            }
            if let error=model.error { Section { TutorialPlaybackError(message:error) } }
        }.listStyle(.insetGrouped).tint(.hearInk)
            .navigationTitle("소리 출력").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden,for:.tabBar)
            .onAppear {model.appear();output.refresh()}.onDisappear {model.disappear()}
            .onChange(of:forcesSpeaker) {_,_ in model.outputPreferenceChanged();output.refresh()}
            .onChange(of:scenePhase) {_,phase in if phase != .active {model.stop()} else {output.refresh()} }
    }
    private func option(_ title: String, detail: String, speaker: Bool) -> some View {
        Button {forcesSpeaker=speaker} label: {
            HStack(alignment:.top,spacing:12) {
                Image(systemName:forcesSpeaker == speaker ? "checkmark.circle.fill" : "circle")
                    .font(.system(size:24)).frame(width:28).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:6) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }.fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
            }.padding(.vertical,10).frame(minHeight:54,alignment:.leading).contentShape(Rectangle())
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
