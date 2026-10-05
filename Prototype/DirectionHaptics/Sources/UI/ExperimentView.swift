import SwiftUI

struct ExperimentSetupView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var haptics: HapticService
    @EnvironmentObject private var preferences: PreferencesStore
    @State private var selected: Set<UUID> = [Presets.all[0].id, Presets.all[1].id]
    @State private var context = StudyContext()
    @State private var repetitions = 5
    @State private var study: StudySession?
    @State private var pair: PairSetup?
    @State private var issue: String?
    @State private var settings = false
    private var sets: [PatternSet] { store.sets.filter { selected.contains($0.id) } }
    private var experimentContext: StudyContext {
        var value = context
        value.gain = preferences.values.gain
        return DeviceInfo.context(value, preview: haptics.isPreview)
    }
    var body: some View {
        List {
            Section {
                Text("같은 조건에서 두 패턴을 비교해 보세요.").foregroundStyle(.secondary)
                DeviceBanner()
            }
            Section {
                ForEach(store.sets) { set in
                    Button {
                        if selected.contains(set.id) { selected.remove(set.id) }
                        else if selected.count < 2 { selected.insert(set.id) }
                    } label: {
                        HStack(spacing: 12) {
                            CodeBadge(code: set.code)
                            Text(set.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected.contains(set.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(set.id) ? Color.accentColor : Color.secondary)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(set.name), \(selected.contains(set.id) ? "선택됨" : "선택 안 됨")")
                        .accessibilityIdentifier("selectSet_\(set.code)")
                }
            } header: { Text("비교할 세트 · \(sets.count)/2") } footer: { Text("세트는 최대 두 개까지 선택할 수 있습니다.") }
            Section("비교 조건") {
                ContextFields(context: $context)
                LabeledContent("전체 진동 세기", value: "\(Int(preferences.values.gain * 100))%")
            }
            Section {
                Button("A/B 비교 시작", systemImage: "rectangle.on.rectangle") {
                    guard sets.count == 2 else { return }
                    pair = PairSetup(a: sets[0], b: sets[1], context: experimentContext)
                }.disabled(sets.count != 2 || !haptics.canPlay || haptics.isPlaying).accessibilityIdentifier("startAB")
            } header: { Text("빠른 A/B 비교") } footer: {
                Text("같은 방향의 A와 B를 느끼고, 더 구별하기 쉬운 쪽을 선택합니다.")
            }
            Section {
                Stepper("방향당 \(repetitions)회", value: $repetitions, in: 1...10).accessibilityIdentifier("repetitions")
                LabeledContent("전체 시행", value: "\(sets.count * 4 * repetitions)회")
                Button("식별 실험 시작", systemImage: "play.fill", action: startStudy)
                    .disabled(sets.isEmpty || !haptics.canPlay || haptics.isPlaying).accessibilityIdentifier("startStudy")
            } header: { Text("방향 식별 비교") } footer: {
                Text("방향당 2회 학습한 뒤 무작위로 재생합니다. 답하는 동안 정답을 숨기고, 끝나면 두 세트의 정답률을 비교합니다. 결과는 저장하지 않습니다.")
            }
        }.navigationTitle("패턴 비교")
            .toolbar { SettingsToolbar(isPresented: $settings) }
            .sheet(isPresented: $settings) { SettingsView() }
            .fullScreenCover(item: $study) { session in
                StudyHost(session: session, haptics: haptics, preferences: preferences.values)
            }
            .sheet(item: $pair) { PairCompareView(setup: $0) }
            .alert("시작하지 못했어요", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) {
                Button("확인") { issue = nil }
            } message: { Text(issue ?? "") }
            .onChange(of: store.sets.map(\.id)) { _, ids in selected = selected.intersection(Set(ids)) }
    }
    private func startStudy() {
        guard !sets.isEmpty else { return }
        if let invalid = sets.first(where: { $0.validationIssue != nil }) { issue = invalid.validationIssue; return }
        study = StudySession(sets: sets, context: experimentContext, repetitions: repetitions, seed: UInt64.random(in: 0...UInt64.max))
    }
}

struct PairSetup: Identifiable { let id = UUID(); let a: PatternSet; let b: PatternSet; let context: StudyContext }

struct PairCompareView: View {
    @EnvironmentObject private var haptics: HapticService
    @Environment(\.dismiss) private var dismiss
    let setup: PairSetup
    @State private var direction: Direction = .front
    @State private var playedA = false
    @State private var playedB = false
    @State private var localError: String?
    @State private var preference: PairPreference?
    @State private var playing: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DeviceBanner()
                    Text("같은 방향, 다른 느낌").font(.title2.bold())
                    Text("A와 B를 모두 느껴본 뒤 선택해 주세요. 방향을 바꾸면 새로운 비교가 시작돼요.").font(.subheadline).foregroundStyle(.secondary)
                    DirectionSelector(selection: $direction).disabled(haptics.isPlaying)
                    playCard("A", set: setup.a, played: playedA)
                    playCard("B", set: setup.b, played: playedB)
                    if haptics.isPlaying { Button("재생 중지", role: .destructive) { haptics.stop() } }
                    if let preference {
                        Label(preference.title, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityIdentifier("pairFeedback")
                        Text("결과는 이 화면에서만 확인해요.").font(.caption).foregroundStyle(.secondary)
                        Button("이 방향 다시 비교") { playedA = false; playedB = false; self.preference = nil }.buttonStyle(LabButtonStyle(prominent: false))
                    } else {
                        ForEach(PairPreference.allCases) { option in
                            Button(option.title) { preference = option }
                                .buttonStyle(LabButtonStyle(prominent: option == .a || option == .b))
                                .disabled(!playedA || !playedB || haptics.isPlaying)
                        }
                    }
                }.padding(20)
            }.background(Theme.canvas).navigationTitle("A/B 비교").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { haptics.stop(); dismiss() } } }
                .onChange(of: direction) { _, _ in playedA = false; playedB = false; preference = nil }
                .alert("재생 확인", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                    Button("확인") { localError = nil }
                } message: { Text(localError ?? "") }
        }.onDisappear { haptics.stop() }
    }
    private func playCard(_ label: String, set: PatternSet, played: Bool) -> some View {
        LabCard {
            HStack { CodeBadge(code: label); Text(set.name).font(.headline); Spacer(); if played { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) } }
            PatternTimeline(pattern: set.pattern(for: direction), height: 45)
            Button {
                playing = label
                Task {
                    do {
                        try await haptics.play(set.pattern(for: direction), gain: setup.context.gain)
                        if label == "A" { playedA = true } else { playedB = true }
                    } catch { localError = error.localizedDescription }
                    playing = nil
                }
            } label: { Label(playing == label ? "재생 중" : "\(label) 재생", systemImage: "play.fill") }
                .buttonStyle(LabButtonStyle(prominent: false)).disabled(haptics.isPlaying || preference != nil)
                .accessibilityIdentifier("play\(label)")
        }
    }
}

struct StudyHost: View {
    @StateObject private var runner: StudyRunner
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var stopping = false
    @State private var comfort = 3
    @State private var confidence = 3
    @State private var effort = 3
    @State private var note = ""
    let preferences: AppPreferences

    init(session: StudySession, haptics: HapticService, preferences: AppPreferences) {
        self.preferences = preferences
        _runner = StateObject(wrappedValue: StudyRunner(session: session, haptics: haptics, preparationSeconds: preferences.preparationSeconds))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DeviceBanner()
                    if runner.phase == .finished {
                        Label(runner.session.status == .completed ? "실험을 마쳤어요" : "여기까지 비교했어요", systemImage: "checkmark.circle.fill")
                            .font(.title2.bold()).foregroundStyle(Theme.accent)
                        SessionSummary(session: runner.session)
                        Button("완료") { dismiss() }.buttonStyle(LabButtonStyle()).accessibilityIdentifier("finishStudy")
                    } else {
                        ProgressView(value: runner.progress).tint(Theme.accent)
                        Text("세트 \(runner.block + 1)/\(runner.session.sets.count) · \(runner.set.name)").font(.subheadline.bold())
                        phaseContent
                        if let issue = runner.issue { Text(issue).font(.footnote).foregroundStyle(Theme.amber) }
                    }
                }.padding(20)
            }.background(Theme.canvas).navigationTitle("방향 식별").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if runner.phase != .finished {
                        ToolbarItem(placement: .cancellationAction) { Button("중단") { runner.pause(); stopping = true } }
                    }
                }
                .alert("실험을 여기서 마칠까요?", isPresented: $stopping) {
                    Button("계속하기", role: .cancel) {}
                    Button("결과 보고 마치기", role: .destructive) { runner.stopSession() }
                } message: { Text("지금까지의 결과를 잠시 확인할 수 있어요. 화면을 닫으면 사라져요.") }
        }.interactiveDismissDisabled()
            .modifier(KeepAwakeModifier(enabled: preferences.keepAwake))
            .onChange(of: scenePhase) { _, phase in if phase != .active { runner.pause() } }
    }

    @ViewBuilder private var phaseContent: some View {
        switch runner.phase {
        case .practice, .practicing:
            LabCard {
                Text("학습").font(.subheadline).foregroundStyle(.secondary)
                Text("먼저 네 방향을 익혀요").font(.title2.bold())
                Text("방향마다 두 번씩 느껴보세요. 몸 기준의 앞·뒤·좌·우예요.").foregroundStyle(.secondary)
                ForEach(Direction.allCases) { direction in
                    Button { runner.practice(direction) } label: {
                        HStack { Label(direction.title, systemImage: direction.symbol); Spacer(); Text("\(runner.practiceCounts[direction, default: 0])/2") }
                    }.buttonStyle(LabButtonStyle(prominent: false))
                        .disabled(runner.phase == .practicing || runner.practiceCounts[direction, default: 0] >= 2)
                        .accessibilityIdentifier("practice_\(direction.rawValue)")
                }
                Button("학습 완료 · 테스트 시작") { runner.beginTrials() }.buttonStyle(LabButtonStyle())
                    .disabled(!runner.practiceComplete || runner.phase == .practicing).accessibilityIdentifier("beginTrials")
            }
        case .ready, .countdown, .playing, .answer, .interrupted:
            LabCard {
                Text("방향 식별").font(.subheadline).foregroundStyle(.secondary)
                Text("\(runner.trial + 1) / \(runner.blockCount)").font(.largeTitle.bold()).monospacedDigit()
                Text(trialTitle).font(.title2.bold())
                if runner.phase == .ready || runner.phase == .interrupted {
                    Text("버튼을 누른 뒤 \(preferences.preparationSeconds)초 후 재생돼요. 화면을 보지 않고 진동에 집중해 주세요.").font(.subheadline).foregroundStyle(.secondary)
                    Button(runner.phase == .interrupted ? "같은 시행 다시 시작" : "진동 재생") { runner.playTrial() }
                        .buttonStyle(LabButtonStyle()).accessibilityIdentifier("playTrial")
                    if runner.phase == .interrupted { Button("이 시행 건너뛰기") { runner.skip() }.foregroundStyle(Theme.amber) }
                }
                if runner.phase == .countdown {
                    Text("\(runner.countdown)").font(.largeTitle).monospacedDigit().frame(maxWidth: .infinity).accessibilityLabel("재생 준비")
                }
                if runner.phase == .playing {
                    Image(systemName: "waveform").font(.system(size: 64)).foregroundStyle(Theme.accent).frame(maxWidth: .infinity).padding()
                }
                if runner.phase == .countdown || runner.phase == .playing {
                    Button("재생 중지") { runner.pause() }.frame(maxWidth: .infinity).foregroundStyle(.secondary)
                }
                if runner.phase == .answer {
                    Text(runner.session.context.inputMode == .facilitator ? "참여자의 답을 기록해 주세요." : "느낀 방향을 골라 주세요.").foregroundStyle(.secondary)
                    DirectionPad { runner.answer($0) }
                    Button("모르겠음") { runner.answer(nil) }.buttonStyle(LabButtonStyle(prominent: false)).accessibilityIdentifier("answerUnknown")
                    Button("다시 느끼기 · \(runner.replayCount)회 요청") { runner.playTrial(replay: true) }.frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
        case .rating:
            LabCard {
                Text("평가").font(.subheadline).foregroundStyle(.secondary)
                Text("이 세트는 어땠나요?").font(.title2.bold())
                rating("편안함", value: $comfort, low: "불편해요", high: "편안해요")
                rating("방향에 대한 확신", value: $confidence, low: "확신 없어요", high: "확실해요")
                rating("집중 부담", value: $effort, low: "부담 없어요", high: "많이 부담돼요")
                TextField("느낀 점 (선택)", text: $note, axis: .vertical).textFieldStyle(.roundedBorder)
                Button(runner.block + 1 == runner.session.sets.count ? "결과 보기" : "다음 세트 학습") {
                    runner.rate(comfort: comfort, confidence: confidence, effort: effort, note: note)
                    comfort = 3; confidence = 3; effort = 3; note = ""
                }.buttonStyle(LabButtonStyle()).accessibilityIdentifier("finishRating")
            }
        case .finished: EmptyView()
        }
    }
    private var trialTitle: String {
        switch runner.phase {
        case .countdown: return "진동을 준비하고 있어요"
        case .playing: return "진동을 느껴보세요"
        case .answer: return "어느 방향이었나요?"
        case .interrupted: return "시행이 중단됐어요"
        default: return "다음 신호를 느껴보세요"
        }
    }
    private func rating(_ title: String, value: Binding<Int>, low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            Picker(title, selection: value) { ForEach(1...5, id: \.self) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
            HStack { Text("1 \(low)"); Spacer(); Text("5 \(high)") }.font(.caption).foregroundStyle(.secondary)
        }
    }
}
