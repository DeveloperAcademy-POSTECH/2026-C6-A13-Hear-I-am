import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var haptics: HapticService
    @EnvironmentObject private var preferences: PreferencesStore
    @Environment(\.dismiss) private var dismiss
    let original: PatternSet
    @State private var draft: PatternSet
    @State private var direction: Direction = .front
    @State private var showAdvanced = false
    @State private var discard = false
    @State private var reset = false
    @State private var localError: String?
    @State private var playingLabel = ""
    @State private var asCopy = false

    init(original: PatternSet) {
        self.original = original
        var draft = original
        if original.isBuiltIn { draft.name += " · 나의 세트" }
        _draft = State(initialValue: draft)
    }
    private var current: HapticPattern { draft.pattern(for: direction) }
    private var pattern: Binding<HapticPattern> {
        Binding(get: { draft.pattern(for: direction) }, set: { draft.patterns[direction] = $0 })
    }
    var body: some View {
        NavigationStack {
            Form {
                if let range = current.adjustableDurationRange {
                    Section {
                        if range.upperBound - range.lowerBound > 0.000_001 {
                            ParameterControl(title: "전체 햅틱 길이", value: totalDuration, range: range,
                                             step: 0.01, scale: 1000, unit: "ms")
                        } else {
                            Text("현재 비율에서는 전체 길이를 더 바꿀 수 없어요. 상세 편집에서 개별 블록의 길이를 조절해 주세요.")
                                .foregroundStyle(.secondary)
                        }
                    } header: { Text("\(direction.title) 방향 · 길이 조절") } footer: {
                        Text("진동·쉼·반복 간격을 같은 비율로 조절합니다. 1,000ms는 1초입니다. 짧은 탭도 길이를 바꿀 수 있으며, 촉감이 달라질 수 있습니다.")
                    }.disabled(haptics.isPlaying)
                }
                Section {
                    TextField("세트 이름", text: $draft.name).accessibilityIdentifier("setName")
                    TextField("세트 설명", text: $draft.detail, axis: .vertical)
                    if !original.isBuiltIn { Toggle("새 세트로 복제하여 저장", isOn: $asCopy) }
                } header: { Text("세트 정보") } footer: {
                    Text(original.isBuiltIn ? "기본 세트를 복제해 나의 패턴으로 저장합니다." : "수정한 패턴을 새 버전으로 저장합니다.")
                }
                Section {
                    Menu {
                        ForEach(Direction.allCases.filter { $0 != direction }) { other in
                            Button("\(other.title) 패턴과 교환") { draft.swap(direction, other) }
                        }
                    } label: { Label("방향 배정 바꾸기", systemImage: "arrow.left.arrow.right") }.disabled(haptics.isPlaying)
                    DeviceBanner()
                } footer: {
                    Text("그래프는 위에 고정됩니다. 강도는 높이, 촉감은 색의 진하기, 시간은 가로 길이로 확인하세요.")
                }
                Section {
                    ParameterControl(title: "진동 강도", value: common(\.intensity), range: 0.1...1, step: 0.05, scale: 100, unit: "%")
                    ParameterControl(title: "촉감 · 둥글게 ↔ 날카롭게", value: common(\.sharpness), range: 0...1, step: 0.05, scale: 100, unit: "%")
                    if current.steps.contains(where: { $0.kind == .continuous }) {
                        ParameterControl(title: "연속 진동 길이", value: duration(of: .continuous), range: 0.03...2, step: 0.01, scale: 1000, unit: "ms")
                    }
                    if current.steps.contains(where: { $0.kind == .pause }) {
                        ParameterControl(title: "쉼 길이", value: duration(of: .pause), range: 0.03...2, step: 0.01, scale: 1000, unit: "ms")
                    }
                    Stepper("패턴 반복 \(current.repetitions)회", value: pattern.repetitions, in: 1...5)
                    if current.repetitions > 1 {
                        ParameterControl(title: "반복 사이 간격", value: pattern.repeatGap, range: 0.1...2, step: 0.05, scale: 1000, unit: "ms")
                    }
                } header: { Text("간편 조절") } footer: {
                    Text("선택한 방향의 해당 블록에 같은 값을 적용합니다. 블록별 차이를 유지하려면 상세 편집을 사용하세요.")
                }
                .disabled(haptics.isPlaying)
                Section {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        ForEach(Array(current.steps.enumerated()), id: \.element.id) { index, step in
                            StepEditor(step: stepBinding(step.id), index: index,
                                       canMoveUp: index > 0, canMoveDown: index < current.steps.count - 1,
                                       move: { move(step.id, by: $0) }, delete: { remove(step.id) })
                                .padding(.vertical, 8)
                        }
                    } label: { Text("상세 편집 · \(current.steps.count)개 블록") }
                    Menu {
                        Button("짧은 탭") { add(.tap()) }
                        Button("연속 진동") { add(.buzz(0.35)) }
                        Button("쉼") { add(.rest(0.2)) }
                    } label: { Label("블록 추가", systemImage: "plus.circle") }
                        .disabled(current.steps.count >= 16).accessibilityIdentifier("addBlock")
                }.disabled(haptics.isPlaying)
                if let issue = draft.validationIssue {
                    Section { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                }
                Section {
                    Button("이 방향 초기화") { draft.patterns[direction] = original.pattern(for: direction) }
                    Button("전체 패턴 초기화", role: .destructive) { reset = true }
                }.disabled(haptics.isPlaying)
            }
            .safeAreaInset(edge: .top, spacing: 0) { livePreview }
            .navigationTitle("패턴 편집").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { discard = true } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.bold().disabled(draft.validationIssue != nil || haptics.isPlaying).accessibilityIdentifier("saveSet")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("완료") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .interactiveDismissDisabled()
            .alert("편집을 끝낼까요?", isPresented: $discard) {
                Button("계속 편집", role: .cancel) {}
                Button("저장하지 않고 닫기", role: .destructive) { haptics.stop(); dismiss() }
            }
            .confirmationDialog("원래 패턴으로 돌아갈까요?", isPresented: $reset, titleVisibility: .visible) {
                Button("초기화", role: .destructive) { draft.patterns = original.patterns }
            }
            .alert("확인해 주세요", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) {
                Button("확인") { localError = nil }
            } message: { Text(localError ?? "") }
        }.onDisappear { haptics.stop() }
    }
    private var timelineRange: Double {
        max(2, ceil(current.steps.reduce(0) { $0 + $1.scheduledDuration }))
    }
    private var livePreview: some View {
        VStack(spacing: 8) {
            DirectionSelector(selection: $direction).disabled(haptics.isPlaying)
            HStack {
                Text("\(direction.title) · 전체 \(String(format: "%.2f", current.duration))초 · \(current.repetitions)회")
                    .accessibilityIdentifier("patternDurationSummary")
                Spacer()
                Text("1주기 · 0–\(Int(timelineRange))초")
            }.font(.caption).foregroundStyle(.secondary)
            PatternTimeline(pattern: current, height: 56, minimumDuration: timelineRange)
                .accessibilityIdentifier("liveTimeline")
                .accessibilityValue(current.steps.map {
                    "\($0.kind.title) \(Int($0.intensity * 100))% / \(Int($0.sharpness * 100))% / \(Int($0.scheduledDuration * 1000))ms / \($0.envelope.title)"
                }.joined(separator: ", ") + " · \(current.repetitions)회")
            HStack {
                Button { play(original.pattern(for: direction), label: "수정 전") } label: { Label("수정 전", systemImage: "play") }
                    .buttonStyle(LabButtonStyle(prominent: false)).accessibilityIdentifier("previewBefore")
                Button { play(current, label: "수정 후") } label: { Label("수정 후", systemImage: "play.fill") }
                    .buttonStyle(LabButtonStyle()).accessibilityIdentifier("previewAfter")
            }.disabled(!haptics.canPlay || haptics.isPlaying || current.validationIssue != nil)
            if haptics.isPlaying {
                Button("\(playingLabel) 재생 중 · 중지", role: .destructive) { haptics.stop() }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
            .overlay(alignment: .bottom) { Divider() }
    }
    private func play(_ pattern: HapticPattern, label: String) {
        playingLabel = label
        Task { do { try await haptics.play(pattern, gain: preferences.values.gain) } catch { localError = error.localizedDescription } }
    }
    private func save() {
        if store.saveSet(draft, original: original, asCopy: asCopy) != nil { dismiss() }
        else { localError = store.error; store.error = nil }
    }
    private func common(_ key: WritableKeyPath<HapticStep, Double>) -> Binding<Double> {
        Binding(get: { current.steps.first(where: { $0.kind != .pause })?[keyPath: key] ?? 0.5 }, set: { value in
            var p = current
            for index in p.steps.indices where p.steps[index].kind != .pause { p.steps[index][keyPath: key] = value }
            draft.patterns[direction] = p
        })
    }
    private var totalDuration: Binding<Double> {
        Binding(get: { current.duration }, set: { draft.patterns[direction] = current.resized(to: $0) })
    }
    private func duration(of kind: StepKind) -> Binding<Double> {
        Binding(get: { current.steps.first(where: { $0.kind == kind })?.duration ?? 0.2 }, set: { value in
            var p = current
            for index in p.steps.indices where p.steps[index].kind == kind { p.steps[index].duration = value }
            draft.patterns[direction] = p
        })
    }
    private func stepBinding(_ id: UUID) -> Binding<HapticStep> {
        Binding(get: { current.steps.first { $0.id == id } ?? .tap() }, set: { step in
            var p = current
            if let index = p.steps.firstIndex(where: { $0.id == id }) { p.steps[index] = step; draft.patterns[direction] = p }
        })
    }
    private func add(_ step: HapticStep) { var p = current; p.steps.append(step); draft.patterns[direction] = p; showAdvanced = true }
    private func remove(_ id: UUID) { var p = current; p.steps.removeAll { $0.id == id }; draft.patterns[direction] = p }
    private func move(_ id: UUID, by offset: Int) {
        var p = current
        guard let index = p.steps.firstIndex(where: { $0.id == id }), p.steps.indices.contains(index + offset) else { return }
        p.steps.swapAt(index, index + offset); draft.patterns[direction] = p
    }
}

private struct StepEditor: View {
    @Binding var step: HapticStep
    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(index + 1). \(step.kind.title)").font(.subheadline.bold())
                Spacer()
                Button { move(-1) } label: { Image(systemName: "arrow.up").frame(width: 44, height: 44) }.disabled(!canMoveUp).accessibilityLabel("블록 위로 이동")
                Button { move(1) } label: { Image(systemName: "arrow.down").frame(width: 44, height: 44) }.disabled(!canMoveDown).accessibilityLabel("블록 아래로 이동")
                Button(role: .destructive, action: delete) { Image(systemName: "trash").frame(width: 44, height: 44) }.accessibilityLabel("블록 삭제")
            }
            Picker("블록 종류", selection: $step.kind) { ForEach(StepKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if step.kind == .tap {
                Button("이 탭의 길이 조절", systemImage: "timer") { step.setLength(step.scheduledDuration) }
                    .accessibilityIdentifier("enableTapLength_\(index)")
                Text("길이를 조절하면 짧은 탭이 연속 진동으로 바뀝니다.").font(.caption).foregroundStyle(.secondary)
            } else {
                ParameterControl(title: "길이", value: $step.duration, range: 0.03...2, step: 0.01, scale: 1000, unit: "ms", identifier: "stepLength_\(index)")
            }
            if step.kind != .pause {
                ParameterControl(title: "강도", value: $step.intensity, range: 0.1...1, step: 0.05, scale: 100, unit: "%")
                ParameterControl(title: "촉감", value: $step.sharpness, range: 0...1, step: 0.05, scale: 100, unit: "%")
                if step.kind == .continuous {
                    Picker("강도 흐름", selection: $step.envelope) { ForEach(Envelope.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
                }
            }
        }.buttonStyle(.borderless)
    }
}
