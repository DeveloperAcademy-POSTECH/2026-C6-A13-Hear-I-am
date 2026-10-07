import OrientationCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: HapticSettingsStore
    @ObservedObject var signals: SignalService
    let onPreview: (AngleCue) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("신호 방식") {
                    Picker("신호 방식", selection: Binding(
                        get: { store.signalMode },
                        set: { store.setSignalMode($0) }
                    )) {
                        ForEach(SignalMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("signal-mode-picker")
                    Text(store.signalMode.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("모든 각도와 기준 리셋에 선택한 한 가지 방식만 사용해요. 변경 사항은 자동으로 저장됩니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if store.signalMode != .haptic {
                        Text("소리 크기는 아이폰 미디어 음량으로 조절해요. 무음 모드에서도 재생되며, 연결된 이어폰이 있으면 이어폰으로 들려요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                angleSection(title: "왼쪽", angles: [-30, -45, -90])
                angleSection(title: "오른쪽", angles: [30, 45, 90])
                if let error = store.errorMessage {
                    Section("설정 저장 상태") {
                        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("기준 리셋 신호") {
                    Text(store.signalMode.resetDescription)
                    Text("리셋 완료는 각도 도달과 다른 신호로 알려요.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("신호 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
    }

    private func angleSection(title: String, angles: [Int]) -> some View {
        Section(title) {
            ForEach(angles, id: \.self) { angle in
                let cue = AngleCue(signedDegrees: angle)
                NavigationLink {
                    AngleSettingEditor(cue: cue, store: store, signals: signals, onPreview: onPreview)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(cue.label) · \(store.isEnabled(angle) ? "켜짐" : "꺼짐")")
                            .font(.headline)
                        Text(signalDescription(for: angle))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityLabel("\(cue.label), \(store.isEnabled(angle) ? "켜짐" : "꺼짐"), \(signalDescription(for: angle))")
                .accessibilityHint("이 각도의 신호 설정을 엽니다.")
            }
        }
    }

    private func signalDescription(for angle: Int) -> String {
        switch store.signalMode {
        case .haptic: store.configuration(for: angle).describe
        case .speech: AudioCue.angle(Double(angle))?.speech ?? ""
        case .beep: AudioCue.angle(Double(angle))?.beepDescription ?? ""
        }
    }
}

private struct AngleSettingEditor: View {
    let cue: AngleCue
    @ObservedObject var store: HapticSettingsStore
    @ObservedObject var signals: SignalService
    let onPreview: (AngleCue) -> Void

    private var configuration: HapticConfiguration {
        store.configuration(for: cue.signedDegrees)
    }

    var body: some View {
        Form {
            Section {
                Toggle("이 각도에서 신호 받기", isOn: Binding(
                    get: { store.isEnabled(cue.signedDegrees) },
                    set: { store.setEnabled(cue.signedDegrees, enabled: $0) }
                ))
            } footer: {
                Text("꺼 두면 회전할 때 이 각도를 알리지 않아요. 체험 버튼으로는 계속 확인할 수 있어요.")
            }
            if store.signalMode == .haptic {
                Section("진동 종류") {
                    Picker("리듬", selection: settingBinding(\.preset)) {
                        ForEach(HapticConfiguration.Preset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Text(HapticService.patternDescription(for: Double(cue.signedDegrees), configuration: configuration))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section("진동 느낌") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("세기 \(Int((configuration.intensity * 100).rounded()))%")
                            .font(.headline).monospacedDigit()
                        Slider(value: settingBinding(\.intensity), in: 0.1...1, step: 0.05)
                            .accessibilityLabel("진동 세기")
                            .accessibilityValue("\(Int((configuration.intensity * 100).rounded()))퍼센트")
                        HStack { Text("약하게"); Spacer(); Text("강하게") }
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("선명도 \(Int((configuration.sharpness * 100).rounded()))%")
                            .font(.headline).monospacedDigit()
                        Slider(value: settingBinding(\.sharpness), in: 0...1, step: 0.05)
                            .accessibilityLabel("진동 선명도")
                            .accessibilityValue("\(Int((configuration.sharpness * 100).rounded()))퍼센트")
                        HStack { Text("부드럽게"); Spacer(); Text("또렷하게") }
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            } else {
                Section("\(store.signalMode.title) 안내") {
                    Text(store.signalMode == .speech
                         ? AudioCue.angle(Double(cue.signedDegrees))?.speech ?? ""
                         : AudioCue.angle(Double(cue.signedDegrees))?.beepDescription ?? "")
                        .font(.title3.bold())
                    Text(store.signalMode.explanation).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section {
                Button { onPreview(cue) } label: {
                    Label("현재 설정으로 \(store.signalMode.title) 체험", systemImage: store.signalMode == .haptic ? "waveform" : "speaker.wave.2")
                        .font(.headline).padding(.vertical, 10)
                }
                .accessibilityLabel("\(cue.label) 현재 \(store.signalMode.title) 설정 체험")
                Text(signals.state.error ?? signals.state.status)
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } footer: {
                Text("허리에 고정한 상태에서 선택한 신호를 구분할 수 있는지 확인해 주세요.")
            }
            if store.signalMode == .haptic, configuration.preset == .directional {
                Section("기본 리듬 읽는 법") {
                    Text("왼쪽은 긴 진동 한 번, 오른쪽은 짧은 진동 두 번으로 시작해요. 잠깐 쉰 뒤 30°는 한 번, 45°는 두 번, 90°는 세 번 짧게 울려요.")
                        .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
            }
            if store.signalMode == .haptic {
                Section {
                    Button("이 각도의 기본 진동으로 복원") {
                        store.resetConfiguration(for: cue.signedDegrees)
                    }
                }
            }
            if let error = store.errorMessage {
                Section("설정 저장 상태") {
                    Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(cue.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<HapticConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { store.configuration(for: cue.signedDegrees)[keyPath: keyPath] },
            set: { value in
                var edited = store.configuration(for: cue.signedDegrees)
                edited[keyPath: keyPath] = value
                store.setConfiguration(edited, for: cue.signedDegrees)
            }
        )
    }
}
