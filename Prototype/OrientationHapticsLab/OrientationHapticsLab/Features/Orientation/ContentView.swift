import SwiftUI
import OrientationCore

struct ContentView: View {
    @StateObject private var model = LabModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var simulatedHeading = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headingCard
                    SignalStatusView(signals: model.signals)
                    controls
                    WalkMetricsView(snapshot: model.walk, status: model.stepStatus)
                    StorageStatusView(store: model.sessionStore)
                    if model.isSimulation { simulationControls }
                    Text("배 앞쪽 허리 · 세로 고정 · 화면 바깥쪽\n측정 중에는 앱을 열고 화면을 켜 두세요.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("방향 신호 실험")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showLogs = true } label: {
                        Label("로그", systemImage: "clock.arrow.circlepath")
                    }.accessibilityLabel("이전 사이클 로그")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Label("설정", systemImage: "slider.horizontal.3")
                    }.accessibilityLabel("신호 설정")
                }
            }
        }
        .overlay { ActiveSignalLayer(model: model, signals: model.signals) }
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView(store: model.settings, signals: model.signals) { model.preview($0) }
                .overlay { ActiveSignalLayer(model: model, signals: model.signals, isPreview: true) }
        }
        .fullScreenCover(isPresented: $showLogs) {
            NavigationStack {
                LogsView(store: model.sessionStore)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("완료") { showLogs = false }
                        }
                    }
            }
        }
        .onChange(of: showSettings) { _, _ in model.setEditing(showSettings || showLogs) }
        .onChange(of: showLogs) { _, _ in model.setEditing(showSettings || showLogs) }
        .onReceive(model.settings.$settings) { _ in
            // Published values arrive before the property is stored. Apply on the next main-actor turn.
            Task { @MainActor in model.applySettings() }
        }
        .onReceive(model.settings.$signalMode) { _ in
            Task { @MainActor in model.applySettings() }
        }
        .task {
            model.start()
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--snapshot-settings") { showSettings = true }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            model.setAppActive(phase == .active)
            if phase == .active { model.start() }
            else if phase == .background { model.stop(reason: .appInterrupted) }
        }
    }

    private var headingCard: some View {
        VStack(spacing: 8) {
            Text(model.cycleNumber == 0 ? "첫 기준점을 설정해 주세요" : "사이클 \(model.cycleNumber)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            Text(model.isCalibrated ? model.directionLabel : "기준 설정 대기")
                .font(.title2.bold())
            Text(model.isCalibrated ? "\(abs(model.relativeDegrees), specifier: "%.0f")°" : "—°")
                .font(.system(size: 86, weight: .bold, design: .rounded))
                .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                .accessibilityLabel(model.isCalibrated ? "\(model.directionLabel) \(abs(model.relativeDegrees), specifier: "%.0f")도" : "아직 기준 방향 없음")
            Text(model.status).font(.subheadline).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Button { model.reset() } label: {
                Label("현재 방향을 0°로 리셋", systemImage: "scope")
                    .font(.title3.bold()).frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canReset)
            .accessibilityIdentifier("reset-reference")
            .accessibilityHint("이전 기록을 저장하고 방향, 걸음 수, 추정 좌표를 초기화합니다.")
            Button(model.isRunning ? "측정 중지" : "측정 시작") {
                if model.isRunning { model.stop() } else { model.start() }
            }.buttonStyle(.bordered)
        }
    }

    private var simulationControls: some View {
        GroupBox("시뮬레이터 미리보기 · 실제 진동 없음") {
            VStack(spacing: 10) {
                Slider(value: $simulatedHeading, in: -180...180, step: 1)
                    .onChange(of: simulatedHeading) { _, value in model.simulate(heading: value) }
                    .accessibilityLabel("가상 방향")
                Text("가상 방향 \(simulatedHeading, specifier: "%.0f")°")
                HStack {
                    ForEach([-30, 30, 90], id: \.self) { angle in
                        Button("\(angle)° 체험") { model.preview(AngleCue(signedDegrees: angle)) }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}

private struct ActiveSignalLayer: View {
    @ObservedObject var model: LabModel
    @ObservedObject var signals: SignalService
    var isPreview = false

    private var snapshotAngle: Int? {
        #if DEBUG && targetEnvironment(simulator)
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--snapshot-angle=") }),
           let angle = Int(argument.split(separator: "=").last ?? ""),
           AngleCue.defaults.contains(where: { $0.id == angle }) { return angle }
        #endif
        return nil
    }

    var body: some View {
        if let angle = signals.state.angle.map({ Int($0.rounded()) }) ?? model.simulatedSignalAngle ?? snapshotAngle {
            SignalOverlay(angle: angle, currentAngle: snapshotAngle.map(Double.init) ?? model.relativeDegrees,
                          isPreview: isPreview || model.isSimulation, mode: signals.mode)
                .overlay(alignment: .bottom) {
                    if model.isSimulation, signals.mode == .haptic {
                        Text("시뮬레이터 · 실제 진동 없음")
                            .font(.footnote.bold())
                            .foregroundStyle(SignalOverlay.foregroundColor(for: angle))
                            .padding(.bottom, 28)
                    }
                }
                .statusBarHidden(true)
                .accessibilityAddTraits(.isModal)
        }
    }
}

private struct SignalStatusView: View {
    @ObservedObject var signals: SignalService
    var body: some View {
        VStack(spacing: 4) {
            Text("신호 방식: \(signals.mode.title)").font(.subheadline.bold())
            Text(signals.state.label.map { "신호: \($0)" } ?? "각도 신호 대기").font(.headline)
            Text(signals.state.error ?? signals.state.status).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}

private struct StorageStatusView: View {
    @ObservedObject var store: SessionStore
    var body: some View {
        if let message = store.storageMessage {
            Text(message).font(.footnote).foregroundStyle(.red)
        }
    }
}
