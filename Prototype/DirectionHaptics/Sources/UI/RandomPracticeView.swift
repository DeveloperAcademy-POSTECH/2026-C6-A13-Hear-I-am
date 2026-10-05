import SwiftUI

private struct RandomSetup: Identifiable {
    let id = UUID()
    let set: PatternSet
    let preferences: AppPreferences
}

struct RandomPracticeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var haptics: HapticService
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var selected = Presets.all[0].id
    @State private var settings = false
    @State private var setup: RandomSetup?
    private var set: PatternSet { store.sets.first { $0.id == selected } ?? Presets.all[0] }
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath").font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
                    Text("느낀 방향으로 몸을 돌려보세요").font(.title2.bold())
                    Text("휴대폰을 함께 돌려 방향을 확인합니다. 1초간 멈추면 정답·오답을 알려주고 다음 진동이 이어져요.").foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                DeviceBanner()
            }
            Section("체험할 패턴") {
                Picker("패턴 세트", selection: $selected) {
                    ForEach(store.sets) { Text("\($0.code) · \($0.name)").tag($0.id) }
                }.accessibilityIdentifier("randomSetPicker")
                NavigationLink { SetDetailView(setID: set.id) } label: {
                    Label("네 방향 미리 익히기", systemImage: "hand.tap")
                }
            }
            Section {
                Label("화면이 위를 향하도록 휴대폰을 들고, 윗부분을 몸 앞쪽으로 향하게 하세요.", systemImage: "iphone")
                Label("시작을 누르고 \(preferences.values.preparationSeconds)초 동안 눈을 감으세요.", systemImage: "eye.slash")
                Label("진동 직전 방향이 기준입니다. 왼쪽·오른쪽은 90°, 뒤는 180°로 몸과 휴대폰을 함께 돌리세요.", systemImage: "arrow.triangle.2.circlepath")
                Label("앞은 그대로, 다른 방향은 돌린 뒤 1초간 멈추면 답이 확정됩니다.", systemImage: "pause.circle")
            } header: { Text("회전으로 답하기") } footer: {
                Text("정답 각도 ±20° 안이면 정답, 다른 방향이나 중간 각도면 오답입니다. 둘 다 2초 쉬고 준비 시간 뒤 다음 진동이 나옵니다. 다음 기준은 새 진동 직전의 방향입니다. 계속 움직여 답이 확정되지 않으면 같은 진동을 10초 뒤 다시 재생합니다.")
            }
            Section {
                Button("회전 체험 시작", systemImage: "play.fill") {
                    setup = RandomSetup(set: set, preferences: preferences.values)
                }.buttonStyle(LabButtonStyle()).listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    .disabled(!haptics.canPlay || haptics.isPlaying).accessibilityIdentifier("startRandom")
            } footer: {
                Text(preferences.values.successSound
                     ? "정답·오답 알림음 켜짐 · 무음 모드에서도 재생합니다. 기기 음량을 확인하세요. TTS는 사용하지 않습니다."
                     : "정답·오답 알림음 꺼짐 · 눈을 감고 결과를 들으려면 상단 설정에서 켜세요.")
            }
        }
        .navigationTitle("랜덤 체험")
        .toolbar { SettingsToolbar(isPresented: $settings) }
        .sheet(isPresented: $settings) { SettingsView() }
        .fullScreenCover(item: $setup) { setup in
            RandomPracticeHost(set: setup.set, preferences: setup.preferences, haptics: haptics)
        }
    }
}

struct RandomPracticeHost: View {
    @StateObject private var runner: RandomPracticeRunner
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(set: PatternSet, preferences: AppPreferences, haptics: HapticService) {
        _runner = StateObject(wrappedValue: RandomPracticeRunner(set: set, preferences: preferences, haptics: haptics))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    DeviceBanner()
                    Text(runner.set.name).font(.headline).foregroundStyle(.secondary)
                    VStack(spacing: 20) {
                        Image(systemName: stateSymbol).font(.system(size: 52))
                            .foregroundStyle(stateColor).accessibilityHidden(true)
                        Text(stateTitle).font(.title2.bold()).multilineTextAlignment(.center)
                        Text(stateHint).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if runner.phase == .countdown {
                            Text("\(runner.countdown)").font(.largeTitle.monospacedDigit())
                        }
                        if runner.phase == .orienting {
                            Text("\(runner.relativeDegrees)°").font(.largeTitle.monospacedDigit())
                            Text("현재 회전 · 오른쪽 + / 왼쪽 −").font(.caption).foregroundStyle(.secondary)
                            if !runner.faceUp { Text("휴대폰 화면을 위로 향하게 해주세요.").foregroundStyle(.orange) }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 250).padding(20)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(stateTitle). \(stateHint)")
                        .accessibilityValue(runner.phase == .feedback ? (runner.feedback?.isCorrect == true ? "정답" : "오답") : "방향 숨김")
                        .accessibilityIdentifier("rotationStatus")
                    if let issue = runner.issue { Text(issue).foregroundStyle(.secondary).accessibilityIdentifier("rotationIssue") }
                    Text("이번 체험 \(runner.completed)회 확인").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("randomScore")
                    #if DEBUG && targetEnvironment(simulator)
                    if runner.isPreview {
                        VStack(spacing: 12) {
                            Text("센서 미리보기 · 실제 회전 감지 아님").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button("왼쪽 90°") { runner.rotatePreview(by: -90) }.accessibilityIdentifier("simulateLeft")
                                Button("오른쪽 90°") { runner.rotatePreview(by: 90) }.accessibilityIdentifier("simulateRight")
                                Button("뒤 180°") { runner.rotatePreview(by: 180) }.accessibilityIdentifier("simulateBack")
                            }.buttonStyle(.bordered).disabled(runner.phase != .orienting && runner.phase != .playing)
                        }
                    }
                    #endif
                }.padding(20)
            }.background(Theme.canvas)
            .safeAreaInset(edge: .bottom) {
                Group {
                    if runner.phase == .ready || runner.phase == .interrupted {
                        Button("다시 시작", systemImage: "play.fill") { runner.start() }
                            .buttonStyle(LabButtonStyle()).accessibilityIdentifier("rotationResume")
                    } else {
                        Button("체험 일시 정지", systemImage: "pause.fill") { runner.interrupt() }
                            .buttonStyle(LabButtonStyle(prominent: false)).accessibilityIdentifier("rotationPause")
                    }
                }.padding().background(.bar)
            }
            .navigationTitle("회전 체험").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { runner.close(); dismiss() } } }
        }.interactiveDismissDisabled()
            .modifier(KeepAwakeModifier(enabled: runner.preferences.keepAwake))
            .onAppear { runner.start() }
            .onChange(of: scenePhase) { _, value in if value != .active { runner.interrupt() } }
            .onDisappear { runner.close() }
    }
    private var stateTitle: String {
        switch runner.phase {
        case .ready: return "준비되셨나요?"
        case .preparing: return "회전 센서를 준비하고 있어요"
        case .countdown: return "눈을 감고 준비하세요"
        case .playing: return "진동을 느껴보세요"
        case .orienting: return "느낀 방향으로 돌려주세요"
        case .feedback: return runner.feedback?.isCorrect == true ? "정답이에요" : "오답이에요"
        case .interrupted: return "체험을 잠시 멈췄어요"
        }
    }
    private var stateHint: String {
        switch runner.phase {
        case .ready: return "휴대폰과 몸을 함께 돌려주세요."
        case .preparing: return runner.faceUp ? "센서가 준비되면 카운트다운을 시작합니다." : "휴대폰 화면을 천장 쪽으로 향하게 해주세요."
        case .countdown: return "휴대폰 화면을 위로 들고 가만히 준비하세요."
        case .playing: return "진동을 끝까지 느낀 뒤 움직여주세요."
        case .orienting: return "앞은 그대로 · 좌우는 90° · 뒤는 180°\n1초간 멈추면 정답·오답을 확인합니다."
        case .feedback:
            guard let feedback = runner.feedback else { return "" }
            let answer = feedback.answer.direction?.title ?? "중간 각도"
            return "정답: \(feedback.expected.title) · 내 응답: \(answer)\n2초 뒤 다음 준비를 시작합니다. 지금 방향을 유지하세요."
        case .interrupted: return "다시 시작하면 준비 시간 뒤 이어집니다."
        }
    }
    private var stateColor: Color {
        guard runner.phase == .feedback else { return .blue }
        return runner.feedback?.isCorrect == true ? .green : .red
    }
    private var stateSymbol: String {
        switch runner.phase {
        case .ready, .orienting: return "arrow.triangle.2.circlepath"
        case .preparing, .countdown: return "hourglass"
        case .playing: return "waveform"
        case .feedback: return runner.feedback?.isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill"
        case .interrupted: return "pause.circle"
        }
    }
}
