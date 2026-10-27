import SwiftUI
import AVFoundation
import HearIAmCore

/// Pushed from Home. Settings and its children share Home's navigation stack.
struct HomeSettingsView: View {
    @StateObject private var output=SoundOutputStatus()
    @AppStorage(SignalPlayer.directionDeadbandKey) private var directionDeadbandDegrees=DirectionTickGate.defaultDeadbandDegrees
    private var selectedDeadbandDegrees: Int {
        let minDeg=Double(DirectionTickGate.minConfigurableDeadbandDegrees)
        let maxDeg=Double(DirectionTickGate.maxConfigurableDeadbandDegrees)
        return Int((directionDeadbandDegrees >= minDeg && directionDeadbandDegrees <= maxDeg ? directionDeadbandDegrees : DirectionTickGate.defaultDeadbandDegrees).rounded())
    }
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
            Section("소리 및 안내") {
                NavigationLink { SoundOutputView() } label: {
                    Label {
                        VStack(alignment:.leading,spacing:4) {
                            Text("소리 출력")
                            Text(output.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {Image(systemName:"speaker.wave.2").accessibilityHidden(true)}
                    .padding(.vertical,4)
                }.accessibilityIdentifier("settings.output")
                NavigationLink { DirectionDeadbandView() } label: {
                    Label {
                        VStack(alignment:.leading,spacing:4) {
                            Text("방향 허용 각도")
                            Text("±\(selectedDeadbandDegrees)° 이내에서는 방향 신호를 쉬어요").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {Image(systemName:"location.north.line").accessibilityHidden(true)}
                    .padding(.vertical,4)
                }.accessibilityIdentifier("settings.deadband")
            }
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

struct DirectionDeadbandView: View {
    @AppStorage(SignalPlayer.directionDeadbandKey) private var storedDegrees=DirectionTickGate.defaultDeadbandDegrees
    @State private var degreesText=""
    @State private var notice: String?
    @FocusState private var fieldFocused: Bool
    private let minDegrees=DirectionTickGate.minConfigurableDeadbandDegrees
    private let maxDegrees=DirectionTickGate.maxConfigurableDeadbandDegrees
    private let presets=DirectionTickGate.deadbandPresets

    private var currentDegrees: Int {
        let minDeg=Double(minDegrees), maxDeg=Double(maxDegrees)
        let value=storedDegrees >= minDeg && storedDegrees <= maxDeg ? storedDegrees : DirectionTickGate.defaultDeadbandDegrees
        return Int(value.rounded())
    }
    private var parsedDegrees: Int? {
        guard let value=Int(degreesText.trimmingCharacters(in:.whitespacesAndNewlines)),
              (minDegrees...maxDegrees).contains(value) else { return nil }
        return value
    }

    var body: some View {
        List {
            Section("현재 적용 각도") {
                VStack(alignment:.leading,spacing:6) {
                    Text("±\(currentDegrees)°").font(.title2.bold())
                    Text("목표 방향에서 왼쪽·오른쪽으로 \(currentDegrees)° 이내로 향하고 있으면 방향 맞음으로 인정되어 방향 음성과 톡톡 소리가 나지 않아요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical,6)
            }
            Section {
                VStack(alignment:.leading,spacing:10) {
                    HStack(spacing:10) {
                        Text("±").font(.headline).foregroundStyle(.secondary).accessibilityHidden(true)
                        TextField("\(minDegrees)~\(maxDegrees)",text:$degreesText)
                            .keyboardType(.numberPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width:110)
                            .focused($fieldFocused)
                            .accessibilityLabel("방향 허용 각도, 도")
                            .accessibilityIdentifier("deadband.input")
                            .onChange(of:degreesText) { _,_ in notice=nil }
                        Text("° (도)").font(.subheadline)
                        Spacer()
                        Button("적용") { applyEnteredDegrees() }
                            .buttonStyle(.borderedProminent)
                            .disabled(parsedDegrees == nil)
                            .accessibilityIdentifier("deadband.apply")
                    }
                    if !degreesText.isEmpty && parsedDegrees == nil {
                        Text("\(minDegrees)° 이상 \(maxDegrees)° 이하의 정수를 입력해주세요.")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if let notice {
                        Text(notice).font(.caption).foregroundStyle(Color.hearGreen)
                    }
                }.padding(.vertical,6)
            } header: {
                Text("각도 직접 입력 (\(minDegrees)° ~ \(maxDegrees)°)")
            } footer: {
                Text("기본값은 15°예요. 이동 중 왼쪽·오른쪽 피드백이 너무 자주 들리면 숫자를 높여 정면 인정 범위를 넓힐 수 있어요.")
            }
            Section("빠른 선택") {
                ForEach(presets,id:\.self) { deg in
                    presetRow(deg)
                }
            }
        }.listStyle(.insetGrouped).tint(.hearInk)
            .navigationTitle("방향 허용 각도").navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden,for:.tabBar)
            .toolbar {
                ToolbarItemGroup(placement:.keyboard) {
                    Spacer()
                    Button("완료") { fieldFocused=false }
                }
            }
            .onAppear { degreesText="\(currentDegrees)" }
    }

    private func applyEnteredDegrees() {
        guard let value=parsedDegrees else { return }
        save(value)
        fieldFocused=false
    }
    private func save(_ value: Int) {
        SignalPlayer.directionDeadbandDegrees=Double(value)
        storedDegrees=Double(value)
        degreesText="\(value)"
        notice="±\(value)°로 설정했어요."
    }
    private func presetRow(_ degrees: Int) -> some View {
        let selected=currentDegrees == degrees
        let detail=degrees == 15 ? "기본 · 15° 이상 벗어나면 안내 시작" : "\(degrees)° 이상 벗어났을 때만 방향 안내"
        return Button { save(degrees);fieldFocused=false } label: {
            HStack(spacing:12) {
                Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size:22)).frame(width:26).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4) {
                    Text("±\(degrees)°").font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
            }.padding(.vertical,6).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("±\(degrees)도").accessibilityHint(detail)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityIdentifier("deadband.preset.\(degrees)")
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
