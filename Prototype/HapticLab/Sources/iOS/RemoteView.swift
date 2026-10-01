import SwiftUI

/// **테스트 4 · 소리로 목표까지 / 테스트 10 · 진동으로 목표까지 (E4, Wizard of Oz)**
///
/// 카메라도 위치 추정도 없이, 운영자가 눈으로 보고 손으로 신호를 보낸다.
/// 문서의 방침 그대로다 — **신호 자체를 알아듣는지부터 먼저 잰다.**
///
/// 출력은 두 가지다. 시계가 없을 때는 무용수가 **운영자 폰에 연결된 AirPods** 를 끼고 걷는다
/// (블루투스 거리 안에서 운영자가 옆을 따라간다).
///
/// 방향 버튼의 뜻은 **"그쪽으로 가요"(무용수 몸 기준)** 다. 문서 안 C의 "벗어난 쪽으로 울린다"는
/// 벗어난 쪽인지 가야 할 쪽인지 두 가지로 읽혀서, 화면에서는 가야 할 쪽으로 못 박는다.
/// 방향 신호는 "조용히"를 누를 때까지 반복된다 — 침묵이 "잘 가고 있다"는 뜻이다.
struct RemoteView: View {
    enum Output: String, CaseIterable, Identifiable {
        case airpods = "AirPods 소리", watch = "시계 진동"
        var id: String { rawValue }
    }

    @EnvironmentObject private var link: PhoneLink
    @EnvironmentObject private var cues: AudioCuePlayer

    @State var output: Output
    @State private var deviation: Deviation = .moderate
    @State private var repeating: GuideSignal?
    @State private var log: [String] = []

    private var ready: Bool { output == .watch ? link.isReachable : !cues.headphonesLost }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("신호를 어디로", selection: $output) {
                    ForEach(Output.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: output) { _, _ in silence() }

                GroupBox {
                    HowToCard(what: output == .watch ? "진동만으로 눈 감고 목표까지 가나"
                                                     : "소리만으로 눈 감고 목표까지 가나",
                              steps: steps)
                }

                if output == .watch {
                    ConnectionBanner()
                } else {
                    OutputBanner()
                    Picker("신호 종류", selection: $cues.style) {
                        ForEach(AudioCuePlayer.Style.allCases) { Text("신호: \($0.rawValue)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                nowPlaying

                HStack(spacing: 10) {
                    directionButton(.left, title: "왼쪽으로", symbol: "arrow.left")
                    directionButton(.back, title: "뒤로", symbol: "arrow.down")
                    directionButton(.right, title: "오른쪽으로", symbol: "arrow.right")
                }

                Button { silence() } label: {
                    Label("조용히 — 잘 가고 있어요", systemImage: "speaker.slash")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.bordered)
                .disabled(!ready)

                HStack(spacing: 10) {
                    onceButton(.arrive, title: "도착", symbol: "checkmark.circle", color: .green)
                    onceButton(.stop, title: "정지", symbol: "exclamationmark.octagon", color: .red)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("얼마나 벗어났나").font(.subheadline.weight(.semibold))
                        Picker("얼마나 벗어났나", selection: $deviation) {
                            ForEach(Deviation.allCases) { Text(label($0)).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: deviation) { _, _ in
                            if let s = repeating { send(s, repeating: true) }
                        }
                        Text("많이 벗어날수록 더 자주 울려요 · 지금 \(String(format: "%.1f", Double(deviation.repeatMs) / 1000))초마다")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if !log.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("보낸 기록").font(.caption).foregroundStyle(.secondary)
                        ForEach(log.suffix(6).reversed(), id: \.self) {
                            Text($0).font(.caption2.monospacedDigit())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(output == .watch ? "10 진동으로 목표까지" : "4 소리로 목표까지")
        .onChange(of: cues.headphonesLost) { _, lost in
            if lost, output == .airpods {
                repeating = nil
                log.append("\(stamp()) AirPods 빠짐 — 멈춤")
            }
        }
        .onDisappear { silence() }
    }

    private var steps: [String] {
        let first = output == .watch
            ? "걷는 사람: 시계 ‘폰 신호 받기’ → ‘끊김 감시’ 켜고 눈 감기"
            : "걷는 사람: 이 폰에 연결된 AirPods를 끼고 눈 감기. 폰 든 사람은 옆에서 따라가요"
        return [first,
                "잘 가고 있으면 아무것도 누르지 않아요",
                "벗어나면 가야 할 쪽 버튼을 눌러요. ‘조용히’를 누를 때까지 반복돼요",
                "도착하면 ‘도착’, 위험하면 ‘정지’. 목표마다 오차·시간·방향 헷갈림을 적어요"]
    }

    private var nowPlaying: some View {
        HStack {
            Text(output == .watch ? "지금 시계는" : "지금 AirPods는").foregroundStyle(.secondary)
            Spacer()
            if let s = repeating {
                Text("\(label(for: s)) 반복 중").fontWeight(.semibold).foregroundStyle(.blue)
            } else {
                Text("조용함").fontWeight(.semibold)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 4)
    }

    private func directionButton(_ s: GuideSignal, title: String, symbol: String) -> some View {
        let active = repeating == s
        return Button { send(s, repeating: true) } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.title)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 88)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? .blue : .indigo.opacity(0.75))
        .disabled(!ready)
    }

    private func onceButton(_ s: GuideSignal, title: String, symbol: String, color: Color) -> some View {
        Button { send(s, repeating: false) } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .disabled(!ready)
    }

    private func send(_ s: GuideSignal, repeating isRepeat: Bool) {
        switch output {
        case .watch:
            // 도착·정지는 시계에서 반복을 끊는다(HapticPlayer.play 가 이전 작업을 취소한다)
            link.send(GuideCommand(signal: s, deviation: isRepeat ? deviation : nil))
        case .airpods:
            if isRepeat {
                cues.startRepeating(s, every: deviation)
            } else {
                cues.stop()
                cues.play(s)
            }
        }
        repeating = isRepeat ? s : nil
        log.append("\(stamp()) \(label(for: s))\(isRepeat ? " · \(label(deviation))" : "")")
    }

    private func silence() {
        if output == .watch, link.isReachable {
            link.send(GuideCommand(signal: .heartbeat, silence: true))
        }
        cues.stop()
        if repeating != nil { log.append("\(stamp()) 조용히") }
        repeating = nil
    }

    private func label(for s: GuideSignal) -> String {
        switch s {
        case .left: return "왼쪽으로"
        case .right: return "오른쪽으로"
        case .back: return "뒤로"
        default: return s.korean
        }
    }

    private func label(_ d: Deviation) -> String {
        switch d {
        case .slight: return "조금"
        case .moderate: return "보통"
        case .severe: return "많이"
        }
    }

    private func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}
