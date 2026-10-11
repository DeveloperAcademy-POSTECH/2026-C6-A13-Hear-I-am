import SwiftUI
import WayDetectCore

struct MeasurementView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionController
    @Binding var selectedRoute: UUID?
    @State private var demo = false
    @State private var ready = false
    @State private var ending = false
    @State private var recovery = false
    private var route: Route? { store.routes.first { $0.id == selectedRoute } ?? store.routes.first }

    var body: some View {
        Group {
            if let result = session.latestResult {
                VStack(spacing: 0) {
                    if session.needsResultDecision {
                        VStack(spacing: 12) {
                            Text("이 측정 기록을 저장할까요?").font(.headline)
                            HStack {
                                Button("저장 안 함", role: .destructive) { session.discardResult() }
                                    .buttonStyle(.bordered).accessibilityIdentifier("discard-result")
                                Button("기록 저장") { session.saveResult() }
                                    .buttonStyle(.borderedProminent).accessibilityIdentifier("save-result")
                            }.controlSize(.large)
                        }.padding()
                    } else {
                        Button("새 측정 준비") { session.clearResult() }.buttonStyle(.borderedProminent).padding()
                    }
                    ResultsView(record: result)
                }
            } else if let engine = session.engine {
                live(engine)
            } else { preparation }
        }.navigationTitle(session.latestResult == nil ? "측정" : "측정 결과")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.isActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("방향 재설정", systemImage: "arrow.counterclockwise") { session.resetDirection() }
                            .accessibilityLabel("방향 재설정")
                            .accessibilityHint("정면을 보고 멈추세요. 걸음은 유지됩니다.")
                            .accessibilityIdentifier("reset-direction")
                            .disabled(session.engine?.isResettingDirection == true)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("종료", role: .destructive) { ending = true }.accessibilityIdentifier("end-measurement")
                    }
                }
            }
            .confirmationDialog("측정을 종료할까요?", isPresented: $ending, titleVisibility: .visible) {
                Button("측정 종료", role: .destructive) { session.finish() }
            } message: { Text("종료 후 기록 저장 여부를 선택합니다.") }
            .sheet(isPresented: $recovery) { RecoveryView() }
            .alert("시작할 수 없습니다", isPresented: Binding(get: { session.startError != nil }, set: { if !$0 { session.startError = nil } })) {
                Button("iOS 설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("확인", role: .cancel) { session.startError = nil }
            } message: { Text(session.startError ?? "") }
    }
    private var preparation: some View {
        Form {
            Section("사용할 경로") {
                if let route {
                    Picker("경로", selection: Binding(get: { route.id }, set: { selectedRoute = $0 })) {
                        ForEach(store.routes) { Text($0.name).tag($0.id) }
                    }
                    Text("\(route.spots.count)개 스팟 · \(route.totalSteps)걸음").foregroundStyle(.secondary)
                } else { Text("경로 탭에서 경로를 추가해 주세요.") }
            }
            Section("시작 준비") {
                Label("배 앞에 세로로 고정", systemImage: "iphone")
                Label("화면은 몸 정면을 향하게", systemImage: "arrow.up")
                Toggle("출발점과 정면을 확인했어요", isOn: $ready).accessibilityIdentifier("ready-toggle")
                Button {
                    if let route { session.start(route: route, demo: demo, store: store) }
                } label: {
                    HStack { Spacer(); if session.isPreparing { ProgressView() }; Text(session.isPreparing ? "권한 확인 중" : "센서 켜기"); Spacer() }
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!ready || route == nil || session.isPreparing).accessibilityIdentifier("start-measurement")
            }
            Section {
                InfoNote(text: "걸음 안내는 허리 움직임의 추정값입니다. 처음 두 걸음을 확인한 뒤 표시합니다. iOS 걸음은 별도로 비교하며 늦게 갱신될 수 있습니다.")
                InfoNote(text: "목표 걸음 후 목표 방향으로 1.5초 멈추면 자동 도착·재설정됩니다. 다음 방향을 맞추면 자동 출발합니다. 실제 위치를 확인하는 기능은 아닙니다.")
                    .accessibilityLabel("목표 걸음 후 정면으로 1.5초 정지. 다음 방향은 자동 출발.")
            }
            Section("화면 시험") {
                Toggle("시뮬레이션", isOn: $demo).accessibilityIdentifier("demo-toggle")
                Text("센서 없이 화면 흐름만 시험합니다.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private func live(_ e: NavigationEngine) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                if session.isDemo { Label("시뮬레이션 · 센서 측정 아님", systemImage: "testtube.2").font(.caption.bold()).foregroundStyle(.orange) }
                VStack(spacing: 6) {
                    Text("\(e.spotIndex + 1)/\(e.record.route.spots.count) · \(e.currentSpot.name)").foregroundStyle(.secondary)
                    Text(e.isResettingDirection ? "방향 재설정 중" : e.phase.title).font(.title2.bold()).accessibilityIdentifier("run-phase")
                }
                if e.isResettingDirection {
                    Text("정면을 보고 잠시 멈추세요.").font(.headline)
                    ProgressView(value: e.resetProgress).accessibilityLabel("방향 재설정 중")
                    Text(e.sensorFresh ? "1초 정지하면 설정됩니다. 걸음은 유지됩니다." : e.sensorStatus)
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityLabel(e.sensorFresh ? "걸음 유지." : e.sensorStatus)
                } else if e.phase == .reference {
                    Text("12시").font(.system(size: 64, weight: .semibold, design: .rounded)).foregroundStyle(.indigo)
                    Text("정면을 보고 멈추세요.").multilineTextAlignment(.center)
                    ProgressView(value: e.referenceProgress).accessibilityLabel("정면 설정 준비")
                    Button("12시 설정") { session.setReference() }
                        .buttonStyle(.borderedProminent).controlSize(.large).disabled(!e.referenceReady)
                        .accessibilityIdentifier("set-reference")
                    Text(!e.sensorFresh ? e.sensorStatus : e.referenceReady ? "설정 가능" : "1초 정지")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if e.phase == .paused {
                    Label(e.pauseReason, systemImage: "pause.circle.fill").foregroundStyle(.orange)
                    Text(e.directionText).font(.title2.bold())
                    Button("계속하기") { recovery = true }.buttonStyle(.borderedProminent).controlSize(.large)
                        .accessibilityIdentifier("open-recovery")
                } else if e.phase == .arrival {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 48)).foregroundStyle(.indigo)
                    Text(e.aligned ? "1.5초 멈춰 계세요." : e.directionText).font(.headline)
                    ProgressView(value: e.arrivalProgress).accessibilityLabel("자동 도착 대기")
                    Text(e.sensorFresh ? "목표 방향을 보고 정지하면 새 12시가 됩니다." : e.sensorStatus)
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityLabel(e.sensorFresh ? "정면 자동 설정." : e.sensorStatus)
                    Button("도착 취소") { session.pause("남은 걸음을 확인하세요."); recovery = true }
                } else {
                    DirectionDial(remaining: e.error, active: e.sensorFresh)
                    Text(e.directionText).font(.title2.bold()).multilineTextAlignment(.center).accessibilityIdentifier("direction-instruction")
                    if e.phase == .aiming {
                        if e.autoStartPending {
                            Text("방향을 맞추면 자동 출발합니다.")
                                .font(.headline).accessibilityIdentifier("auto-start-pending")
                        } else {
                            Button(e.legSteps > 0 ? "계속 걷기" : "출발") { session.beginWalking() }.buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(!e.canStartWalking).accessibilityIdentifier("begin-walking")
                            Text(e.aligned ? "출발 준비 완료" : "12시로 맞추세요.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if !session.lastGuidanceText.isEmpty {
                    Text(session.lastGuidanceText).font(.callout).foregroundStyle(.secondary)
                        .accessibilityLabel("최근 안내").accessibilityValue(session.lastGuidanceText)
                        .accessibilityIdentifier("last-guidance")
                }
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("추정 걸음").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text("\(e.legSteps) / \(e.stepGoal)").font(.largeTitle.bold()).monospacedDigit()
                            .accessibilityLabel("걸음").accessibilityValue("\(e.legSteps)")
                            .accessibilityIdentifier("step-count")
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("iOS 누적").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                        Text("\(e.record.systemTotal)").font(.title2.bold()).monospacedDigit()
                            .accessibilityLabel("iOS 걸음").accessibilityValue("\(e.record.systemTotal)")
                    }
                }.padding().background(.background, in: RoundedRectangle(cornerRadius: 16))
                HStack {
                    Button("다시 안내", systemImage: "speaker.wave.2") { session.repeatInstruction() }
                    Spacer()
                    if e.phase == .walking || e.phase == .aiming {
                        Button("일시정지", systemImage: "pause") { session.pause() }.accessibilityIdentifier("pause-measurement")
                    }
                }.buttonStyle(.bordered).controlSize(.large)
                DisclosureGroup("센서 상태") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(e.sensorStatus)
                        Text("추정 세션 누적 \(e.record.estimatedTotal)걸음 · iOS \(e.record.systemTotal)걸음")
                        Text(session.systemStatus)
                        Text("센서는 계속 수신합니다. 이동 중 걸음만 목표에 반영합니다.")
                    }.font(.footnote).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                if session.isDemo {
                    VStack(spacing: 12) {
                        Text("시뮬레이션 조작").font(.headline)
                        HStack {
                            Button("목표로 맞추기") { session.demoTurn(e.error) }.accessibilityIdentifier("demo-align")
                            Button("1걸음") { session.demoStep() }.accessibilityIdentifier("demo-step")
                        }
                        HStack {
                            Button("왼쪽 한 칸") { session.demoTurn(-30) }
                            Button("오른쪽 한 칸") { session.demoTurn(30) }
                        }
                        Button("센서 수신 전환") { session.toggleDemoSignal() }
                    }.buttonStyle(.bordered).padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                }
            }.padding(20)
        }.background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct RecoveryView: View {
    @EnvironmentObject private var session: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var remaining = 1
    @State private var returning = false
    var body: some View {
        NavigationStack {
            Form {
                if let e = session.engine {
                    Section("현재 위치에서 계속") {
                        Text("위치와 남은 걸음을 확인하세요. 목표 방향은 바꾸지 않습니다.")
                        Text(e.directionText).font(.headline)
                        Stepper("남은 걸음 \(remaining)", value: $remaining, in: 1...300)
                        Button("위치 확인 · 계속 걷기") { session.resume(remaining: remaining); dismiss() }
                            .disabled(!e.canResume).accessibilityIdentifier("resume-walking")
                        if e.needsReanchor { Text("방향 재설정을 누르세요.").foregroundStyle(.orange) }
                        else if !e.canResume { Text("기존 목표 방향을 향해 멈춰 서세요.").foregroundStyle(.secondary) }
                    }
                    Section("기준을 다시 잡아야 할 때") {
                        Text("방향이 맞지 않거나 휴대폰을 다시 착용했다면, 동행자와 이전 확인 스팟으로 돌아간 뒤 다시 시작하세요.")
                        Button("이전 스팟에서 다시 시작") { returning = true }.accessibilityIdentifier("restart-spot")
                    }
                }
            }.navigationTitle("위치 확인").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("방향 재설정") { session.resetDirection(); dismiss() }
                            .accessibilityIdentifier("recovery-reset-direction")
                    }
                    ToolbarItem(placement: .topBarTrailing) { Button("닫기") { dismiss() } }
                }
                .onAppear { remaining = max(1, (session.engine?.stepGoal ?? 1) - (session.engine?.legSteps ?? 0)) }
                .confirmationDialog("이전 확인 스팟에 돌아왔나요?", isPresented: $returning, titleVisibility: .visible) {
                    Button("이전 스팟 확인 · 다시 시작") { session.restartFromSpot(); dismiss() }
                }
        }
    }
}
