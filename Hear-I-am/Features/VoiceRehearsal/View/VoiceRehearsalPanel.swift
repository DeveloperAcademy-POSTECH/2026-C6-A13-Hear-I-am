import SwiftUI
import HearIAmCore

struct VoiceModePicker: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if let selected=model.selected {
                VStack(alignment:.leading,spacing:8) {
                    Label("선택한 무대",systemImage:"checkmark.circle.fill").font(.subheadline)
                    Text(selected.name).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)
                }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                    .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:20))
            }
            Text("어떻게 사용할까요?").font(.largeTitle.bold())
            ForEach(VoiceUsageMode.allCases) { mode in
                Button {model.selectVoiceMode(mode,advanceAutomatically:false)} label: {
                    HStack(spacing:14) {
                        Image(systemName:mode.symbol).font(.title2).frame(width:32)
                        VStack(alignment:.leading,spacing:4) {
                            Text(mode.title).font(.headline)
                            Text(mode.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName:model.voiceMode == mode ? "checkmark.circle.fill" : "circle")
                    }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
                        .background(model.voiceMode == mode ? Color.primary.opacity(0.09) : Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                        .overlay(RoundedRectangle(cornerRadius:18).stroke(model.voiceMode == mode ? Color.primary : .clear,lineWidth:2))
                }.buttonStyle(.plain).foregroundStyle(Color.primary)
                    .accessibilityAddTraits(model.voiceMode == mode ? [.isSelected] : [])
            }
            Text("말하면 바로 진행해요. 카드를 누르면 다음 버튼이 나타나요.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct VoiceRehearsalPanel: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VoiceGlassCard(visualization: model.voiceRecognition.inputVisualization,
                       listening: model.voiceShouldListen && model.voiceRecognition.isListening,
                       processing: model.voiceProcessingCommand,
                       recovering: model.voiceRecognition.isRecovering,
                       speaking: model.voiceTurnActive,
                       title: model.voiceStatusTitle,
                       detail: model.voiceInputError ?? model.voiceStatusDetail,
                       transcript: model.voiceTranscript,
                       pulse: model.voiceListeningPulse) {
            if model.voiceCanOfferInput || model.phase == .selection {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { inputActions }
                    VStack(alignment: .leading, spacing: 0) { inputActions }
                }
            }
        }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 4)
    }
    @ViewBuilder private var inputActions: some View {
        if model.voiceCanOfferInput {
            Button {model.retryVoiceListening()} label: {
                Label(model.voiceInputError != nil || !model.voiceListeningEnabled ? "다시 듣기" : "다시 말하기",systemImage:"mic")
                    .font(.subheadline.weight(.semibold)).frame(minHeight:44)
            }.buttonStyle(.plain)
            if model.voiceListeningEnabled {
                Button("음성 끄기") {model.disableVoiceListening()}
                    .font(.subheadline).foregroundStyle(.secondary).frame(minHeight:44)
            }
        }
        if model.phase == .selection {
            Button(model.voiceSelectionControlsVisible ? "버튼 접기" : "버튼으로 선택") {
                model.toggleVoiceSelectionControls()
            }.font(.subheadline).frame(minHeight:44).buttonStyle(.plain)
                .accessibilityHint(model.voiceSelectionControlsVisible ? "선택은 유지하고 하단 진행 버튼을 숨깁니다" : "설명 다시 듣기와 다음 버튼을 표시합니다")
        }
    }
}

struct VoiceListeningOverlay: View {
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        VStack(spacing:20) {
            VoiceGlassOrb(active: model.voiceRecognition.isListening,
                          symbol: model.voiceProcessingCommand ? "ellipsis" : model.voiceTurnActive ? "waveform" : "checkmark")
                .frame(width: 88, height: 88).padding(.top, 8)
            Text(model.voiceProcessingCommand ? "요청을 확인하고 있어요" : model.voiceTurnActive ? "듣고 있어요" : "P\(model.guide?.rehearsalReturnArrivalIndex ?? 0)에 도착했어요")
                .font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(model.voiceTurnActive ? "잠시 멈춰주세요. 말씀을 마치면 요청을 확인해요." : "‘계속’이라고 말하면 다음 지점으로 안내해요.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer(minLength:0)
        }.padding(24).padding(.top,24).frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(.systemBackground))
    }
}

/// One question per screen: choose the stage first, then choose how to use it.
struct VoiceStagePicker: View {
    @ObservedObject var library: StageLibrary
    @ObservedObject var model: GuidanceViewModel
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                Text(model.voiceChoosingMode ? "2 / 2 · 사용 방식" : "1 / 2 · 무대 선택")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                if model.voiceChoosingMode {
                    VoiceModePicker(model:model)
                } else {
                    Text("어느 무대를 사용할까요?").font(.title.bold()).fixedSize(horizontal:false,vertical:true)
                    Text("이름이나 번호를 말하거나 목록에서 골라주세요.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let query=model.voiceSearchQuery {
                        HStack {
                            Text("‘\(query)’ 검색 결과").font(.headline)
                            Spacer()
                            Text("\(model.visibleVoiceStages.count)개").foregroundStyle(.secondary)
                        }
                    } else {Text("저장한 무대").font(.headline)}
                    if library.loading {ProgressView("무대를 불러오고 있어요")}
                    if model.visibleVoiceStages.isEmpty && !library.loading {
                        VStack(alignment:.leading,spacing:10) {
                            Image(systemName:"rectangle.stack").font(.largeTitle)
                            Text(model.voiceSearchQuery == nil ? "저장된 무대가 없어요" : "일치하는 무대가 없어요").font(.title2.bold())
                            Text(model.voiceSearchQuery == nil ? "홈에서 공간과 동선을 먼저 저장해주세요." : "다른 이름을 말씀하거나 취소해서 전체 목록으로 돌아가세요.").foregroundStyle(.secondary)
                        }.padding(.vertical,20)
                    }
                    ForEach(Array(model.visibleVoiceStages.enumerated()),id:\.element.id) { index,item in
                        stage(item,number:index+1)
                    }
                    if let error=library.error {
                        Text(error).font(.footnote)
                        Button("목록 다시 불러오기") {
                            Task {
                                await library.refresh()
                                model.voiceStages=library.groups.pinned+library.groups.recent
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    private func stage(_ item:ScanManifest,number:Int) -> some View {
        let usable=item.route.map {$0.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty} ?? false
        let selected=model.selected?.id == item.id
        return Button {model.select(item,advanceAutomatically:false)} label: {
            HStack(alignment:.top,spacing:14) {
                Text("\(number)").font(.headline).frame(width:32,height:32)
                    .background(Color.primary,in:Circle()).foregroundStyle(Color(.systemBackground))
                VStack(alignment:.leading,spacing:7) {
                    Text(item.name).font(.headline).fixedSize(horizontal:false,vertical:true)
                    Text(usable ? "내부 지점 \(max(0,(item.route?.points.count ?? 2)-2))개" : "동선 준비가 필요해요")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(item.date.formatted(.dateTime.locale(Locale(identifier:"ko_KR")).month().day().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength:0)
                Image(systemName:selected ? "checkmark.circle.fill" : "circle").font(.title3).accessibilityHidden(true)
            }.multilineTextAlignment(.leading).padding(18).frame(maxWidth:.infinity,alignment:.leading)
                .background(Color(.systemGray6),in:RoundedRectangle(cornerRadius:18))
                .overlay(RoundedRectangle(cornerRadius:18).stroke(selected ? Color.primary : .clear,lineWidth:2))
        }.buttonStyle(.plain).disabled(!usable).opacity(usable ? 1 : 0.5)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
            .accessibilityLabel("\(number)번, \(item.name)")
            .accessibilityHint(usable ? "선택한 후 다음 버튼을 누르면 사용 방식을 선택합니다" : "사용 가능한 동선을 먼저 준비해야 합니다")
    }
}

// Listening feedback uses the existing audio session; these views never request microphone access.
private enum VoiceGlassPalette {
    static let cyan = Color(red: 0.18, green: 0.77, blue: 0.88)
    static let blue = Color(red: 0.30, green: 0.48, blue: 0.90)
    static let violet = Color(red: 0.62, green: 0.43, blue: 0.88)
}

struct VoiceBottomGlow: View {
    let active: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [.clear, VoiceGlassPalette.blue.opacity(0.06), VoiceGlassPalette.cyan.opacity(0.20)],
                           startPoint: .top, endPoint: .bottom)
            HStack(spacing: -45) {
                Ellipse().fill(VoiceGlassPalette.cyan.opacity(0.22))
                Ellipse().fill(VoiceGlassPalette.violet.opacity(0.18))
            }.frame(height: 150).blur(radius: 35).offset(y: 45)
        }
        .frame(maxWidth: .infinity).frame(height: 320)
        .opacity(active && !reduceTransparency ? 1 : 0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: active)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct VoiceGlassOrb: View {
    let active: Bool
    var symbol = "waveform"
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle().fill(VoiceGlassPalette.violet.opacity(active ? 0.12 : 0)).blur(radius: 9)
                    .scaleEffect(1.18)
                if reduceTransparency {
                    Circle().fill(Color(.secondarySystemBackground))
                } else {
                    Circle().fill(.ultraThinMaterial)
                    Circle().fill(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                Circle().stroke(AngularGradient(colors: active ? [.white, VoiceGlassPalette.cyan.opacity(0.7), .white, VoiceGlassPalette.violet.opacity(0.6), .white] : [Color.primary.opacity(0.15), .clear], center: .center), lineWidth: 1.5)
                Image(systemName: symbol).font(.system(size: proxy.size.width * 0.38, weight: .semibold))
                    .foregroundStyle(active ? Color(red: 0.15, green: 0.34, blue: 0.53) : Color.secondary)
            }.shadow(color: VoiceGlassPalette.blue.opacity(active ? 0.15 : 0), radius: 10, y: 3)
        }.accessibilityHidden(true)
    }
}

private struct VoiceAudioWaveform: View {
    @ObservedObject var visualization: VoiceInputVisualization
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active || visualization.level < 0.02)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 2.3
            let strength = active ? visualization.level : 0
            Canvas { context, size in
                let middle = size.height / 2
                let colors = [VoiceGlassPalette.cyan, VoiceGlassPalette.blue, VoiceGlassPalette.violet, VoiceGlassPalette.cyan]
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: middle)); baseline.addLine(to: CGPoint(x: size.width, y: middle))
                context.stroke(baseline, with: .linearGradient(Gradient(colors: [.clear, VoiceGlassPalette.blue.opacity(0.25), .clear]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1)
                for layer in 0..<4 {
                    var ribbon = Path()
                    let amplitude = (1.2 + strength * size.height * 0.42) * (1 - Double(layer) * 0.12)
                    func point(_ index: Int, lower: Bool) -> CGPoint {
                        let x = Double(index) / 100
                        let envelope = pow(sin(.pi * x), 1.4)
                        let offset = Double(layer) * 1.25
                        let wave = sin(x * .pi * (4.0 + Double(layer) * 0.65) + phase + offset)
                        let secondary = sin(x * .pi * 2 - phase * 0.6 + offset) * 0.22
                        let displacement = amplitude * envelope * (wave + secondary) * (lower ? -0.65 : 1)
                        return CGPoint(x: x * size.width, y: middle + displacement)
                    }
                    ribbon.move(to: point(0, lower: false))
                    for index in 1...100 { ribbon.addLine(to: point(index, lower: false)) }
                    for index in stride(from: 100, through: 0, by: -1) { ribbon.addLine(to: point(index, lower: true)) }
                    ribbon.closeSubpath()
                    context.fill(ribbon, with: .color(colors[layer].opacity(active ? 0.30 : 0.10)))
                }
            }
        }.frame(height: 46).allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct VoiceGlassCard<Actions: View>: View {
    let visualization: VoiceInputVisualization
    let listening: Bool
    let processing: Bool
    let recovering: Bool
    let speaking: Bool
    let title: String
    let detail: String
    let transcript: String
    let pulse: Int
    @ViewBuilder let actions: () -> Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var lifted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VoiceGlassOrb(active: listening, symbol: processing ? "ellipsis" : listening ? "waveform" : "mic.slash")
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(listening ? "VOICE" : "음성 안내").font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.8).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("voice-feedback-status")
                }
                Spacer(minLength: 0)
                if recovering || processing { ProgressView().controlSize(.small).accessibilityLabel(processing ? "요청 확인 중" : "연결 중") }
            }
            if listening || processing {
                VoiceAudioWaveform(visualization: visualization, active: listening)
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(speaking ? "인식 중인 말" : "입력된 말").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                Text(transcript.isEmpty ? "말씀하신 내용이 여기에 표시돼요" : transcript)
                    .font(.subheadline).foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(12)
                .background(Color(.systemBackground).opacity(reduceTransparency ? 1 : 0.58), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            actions()
        }.padding(18)
            .background {
                let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
                if reduceTransparency { shape.fill(Color(.secondarySystemBackground)) }
                else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(LinearGradient(colors: [.white.opacity(0.50), .white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.95), listening ? VoiceGlassPalette.cyan.opacity(0.35) : Color.primary.opacity(0.08), listening ? VoiceGlassPalette.violet.opacity(0.28) : Color.primary.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: Color.black.opacity(0.045), radius: 18, y: 7)
            .shadow(color: VoiceGlassPalette.blue.opacity(listening ? 0.10 : 0), radius: 20, y: 2)
            .scaleEffect(lifted ? 1.018 : 1, anchor: .bottom)
            .offset(y: lifted ? -4 : 0)
            .task(id: pulse) {
                guard pulse > 0, listening, !reduceMotion else { lifted = false; return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.64)) { lifted = true }
                do { try await Task.sleep(nanoseconds: 200_000_000) } catch { lifted = false; return }
                withAnimation(.spring(response: 0.42, dampingFraction: 0.80)) { lifted = false }
            }
            .onChange(of: listening) { _, value in if !value { lifted = false } }
            .onChange(of: reduceMotion) { _, value in if value { lifted = false } }
            .accessibilityElement(children: .contain)
    }
}

#if DEBUG
/// Deterministic visual fixture, never used for microphone readiness or guidance commands.
struct VoiceGlassPreviewHarness: View {
    @StateObject private var visualization = VoiceInputVisualization()
    @State private var state = "듣기"
    @State private var pulse = 1
    private var listening: Bool { state == "듣기" || state == "발화" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("1 / 2 · 무대 선택").font(.subheadline).foregroundStyle(.secondary)
                    Text("어느 무대를 사용할까요?").font(.title.bold())
                    Text("이름이나 번호를 말하거나 목록에서 골라주세요.").font(.subheadline).foregroundStyle(.secondary)
                    Text("저장한 무대").font(.headline)
                    ForEach(Array(["효자아트홀 I believe", "중앙무대"].enumerated()), id: \.offset) { index, name in
                        HStack(spacing: 14) {
                            Text("\(index + 1)").font(.headline).frame(width: 32, height: 32).background(.black, in: Circle()).foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 7) {
                                Text(name).font(.headline)
                                Text("내부 지점 3개").font(.subheadline).foregroundStyle(.secondary)
                                Text("10월 26일 오후 2:30").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "circle").font(.title3)
                        }.padding(18).background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 18))
                    }
                }.padding(24)
            }.navigationTitle("말로 안내 시작").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Image(systemName: "xmark") } }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 12) {
                        VoiceGlassCard(visualization: visualization, listening: listening, processing: state == "처리", recovering: state == "준비", speaking: state == "발화",
                            title: state == "발화" ? "듣고 있어요" : state == "실전" ? "실전 안내 중 · 음성 인식 꺼짐" : state == "오류" ? "음성 입력을 확인해주세요" : state == "처리" ? "말씀을 확인하고 있어요" : state == "준비" ? "마이크 입력 확인 중" : "말씀하시면 들을게요",
                            detail: state == "실전" ? "마이크를 끈 상태로 저장된 동선을 안내해요." : state == "오류" ? "버튼으로 진행하거나 다시 듣기를 눌러주세요." : "장소 이름이나 무대 이름을 말씀해주세요.",
                            transcript: state == "발화" || state == "처리" ? "효자아트홀 I believe" : "", pulse: pulse) {
                                HStack(spacing: 20) {
                                    Label("다시 말하기", systemImage: "mic").font(.subheadline.weight(.semibold))
                                    Text("음성 끄기").font(.subheadline).foregroundStyle(.secondary)
                                }.frame(minHeight: 38)
                            }.padding(.horizontal, 24)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(["준비", "듣기", "발화", "처리", "오류", "실전"], id: \.self) { item in
                                    Button(item) { state = item; visualization.update(item == "발화" ? 0.72 : 0); pulse += 1 }
                                        .buttonStyle(.bordered).tint(.black)
                                }
                            }.padding(.horizontal, 24)
                        }.accessibilityIdentifier("preview-controls")
                        Text("디자인 검증용 · 파형 입력 예시").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.top, 10).padding(.bottom, 12)
                        .background { ZStack(alignment: .bottom) { Color(.systemBackground); VoiceBottomGlow(active: listening).ignoresSafeArea(edges: .bottom) } }
                }
        }.preferredColorScheme(.light)
            .onAppear {
                if ProcessInfo.processInfo.arguments.contains("--voice-glass-speaking") { state = "발화"; visualization.update(0.72) }
            }
    }
}
#endif
