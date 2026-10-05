import SwiftUI

struct SettingsToolbar: ToolbarContent {
    @Binding var isPresented: Bool
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("설정", systemImage: "gearshape") { isPresented = true }
                .accessibilityIdentifier("openSettings")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var haptics: HapticService
    @Environment(\.dismiss) private var dismiss
    @State private var resetting = false
    @State private var sound = FeedbackSoundService()
    @State private var soundError: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ParameterControl(title: "전체 진동 세기", value: $preferences.values.gain, range: 0.2...1, step: 0.05, scale: 100, unit: "%")
                    Button("현재 세기로 느껴보기", systemImage: "waveform") {
                        haptics.preview(Presets.all[0].pattern(for: .front), gain: preferences.values.gain)
                    }.disabled(!haptics.canPlay || haptics.isPlaying).accessibilityIdentifier("settingsPreview")
                } header: { Text("진동") } footer: {
                    Text("모든 진동에 적용합니다. 기본값은 100%이며, 강도 변화·강도 단계 패턴의 차이는 유지됩니다.")
                }
                Section {
                    Stepper("재생 준비 시간 \(preferences.values.preparationSeconds)초", value: $preferences.values.preparationSeconds, in: 1...10)
                        .accessibilityIdentifier("preparationTime")
                    Toggle("정답·오답 알림음", isOn: $preferences.values.successSound).accessibilityIdentifier("successSoundSetting")
                    Button("정답음 들어보기", systemImage: "speaker.wave.2") {
                        do { try sound.prepare(); try sound.play() }
                        catch { soundError = error.localizedDescription }
                    }.accessibilityIdentifier("previewSuccessSound")
                    Button("오답음 들어보기", systemImage: "speaker.wave.2") {
                        do { try sound.play(correct: false) }
                        catch { soundError = error.localizedDescription }
                    }.accessibilityIdentifier("previewIncorrectSound")
                    Toggle("체험 중 자동 잠금 방지", isOn: $preferences.values.keepAwake).accessibilityIdentifier("keepAwakeSetting")
                } header: { Text("눈 감고 체험") } footer: {
                    Text("진동을 느낀 뒤 몸과 휴대폰을 함께 돌리세요. 정답은 올라가는 소리, 오답은 내려가는 소리입니다. 무음 모드에서도 재생하며, 기기 음량이 0이면 들리지 않습니다. 확인 후 다음 진동이 자동으로 이어집니다.")
                }
                Section("화면") {
                    Picker("화면 모드", selection: $preferences.values.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.menu).accessibilityIdentifier("appearanceSetting")
                    Label("글자 크기는 iPhone 설정을 따릅니다", systemImage: "textformat.size").foregroundStyle(.secondary)
                }
                Section {
                    LabeledContent("햅틱 지원", value: haptics.supportsHaptics ? "지원됨" : "실제 iPhone 필요")
                    if haptics.isPreview { Label("화면 미리보기 · 실제 진동 없음", systemImage: "eye").foregroundStyle(.secondary) }
                    Text("방향은 진동으로 안내하고, 1초간 멈추면 정답·오답에 따라 다른 알림음을 재생합니다. TTS·음성 읽기는 사용하지 않습니다.")
                    Text("체험 결과는 저장하지 않습니다. 사용자 패턴·즐겨찾기·앱 설정만 기기에 남습니다.")
                } header: { Text("앱 정보") }
                Section {
                    Button("앱 설정 초기화", role: .destructive) { resetting = true }.accessibilityIdentifier("resetPreferences")
                } footer: { Text("직접 만든 패턴과 즐겨찾기는 유지됩니다.") }
            }
            .navigationTitle("설정").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { haptics.stop(); dismiss() } } }
            .confirmationDialog("앱 설정을 초기화할까요?", isPresented: $resetting, titleVisibility: .visible) {
                Button("설정 초기화", role: .destructive) { preferences.reset() }
            }
            .alert("알림음을 확인해 주세요", isPresented: Binding(get: { soundError != nil }, set: { if !$0 { soundError = nil } })) {
                Button("확인") { soundError = nil }
            } message: { Text(soundError ?? "") }
        }.onDisappear { haptics.stop(); sound.close() }
    }
}
