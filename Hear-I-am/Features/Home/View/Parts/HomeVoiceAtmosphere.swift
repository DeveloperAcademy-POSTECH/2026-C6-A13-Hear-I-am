import SwiftUI
import HearIAmCore

/// Soft, slowly drifting light stays below the conversation text without covering controls.
struct HomeVoiceWaves: View {
    let awake: Bool
    let animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let colors = [
        Color(red: 0.14, green: 0.30, blue: 0.73),
        Color(red: 0.17, green: 0.65, blue: 0.76),
        Color(red: 0.33, green: 0.30, blue: 0.75)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating || reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                context.addFilter(.blur(radius: 38))
                for layer in 0..<3 {
                    let index = Double(layer)
                    let drift = sin(time * 0.24 + index * 2) * size.width * 0.08
                    let x = size.width * (0.18 + index * 0.30) + drift
                    let y = size.height * (0.95 + index * 0.04) + cos(time * 0.19 + index) * 12
                    let glow = CGRect(x: x - size.width * 0.55, y: y - size.height * 0.42,
                                      width: size.width * 1.1, height: size.height * 0.84)
                    context.fill(Path(ellipseIn: glow), with: .color(Self.colors[layer].opacity(0.65)))
                }
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                         .init(color: .white.opacity(0.35), location: 0.35),
                                         .init(color: .white, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .opacity(awake ? 0.8 : 0.5)
        .animation(.easeInOut(duration: reduceMotion ? 0 : 0.8), value: awake)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A quiet double pulse with soft outward rings, also present while waiting for the wake phrase.
struct HomeVoiceOrb: View {
    let awake: Bool
    let speaking: Bool
    let animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating || reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let cycle = (time / 3.2).truncatingRemainder(dividingBy: 1)
            let heartbeat = reduceMotion ? 0 : exp(-pow((cycle - 0.20) / 0.07, 2))
                + 0.45 * exp(-pow((cycle - 0.36) / 0.08, 2))
            let speakingPulse = speaking && !reduceMotion ? (sin(time * 3) + 1) * 0.008 : 0
            ZStack {
                Circle().fill(Color(red: 0.48, green: 0.66, blue: 1))
                    .frame(width: 116, height: 116).blur(radius: 22)
                    .opacity(0.10 + heartbeat * 0.07)
                ForEach(0..<2) { ring in
                    let progress = (time / 3.8 + Double(ring) / 2).truncatingRemainder(dividingBy: 1)
                    Circle().strokeBorder(Color.white, lineWidth: 1)
                        .frame(width: 98 + progress * 68, height: 98 + progress * 68)
                        .opacity(reduceMotion ? 0 : sin(progress * .pi) * (awake ? 0.20 : 0.12))
                }
                Image("HearV3Orb").resizable().scaledToFit().frame(width: 144, height: 144)
                    .scaleEffect(1 + heartbeat * (awake ? 0.04 : 0.025) + speakingPulse)
            }
            .frame(width: 176, height: 176)
        }
        .accessibilityHidden(true)
    }
}

/// Partial recognition replaces the current text directly; no artificial typing timer or speech announcements.
struct HomeConversationCaption: View {
    let caption: VoiceHomeCaption
    let speaking: Bool
    let listening: Bool
    let confirming: Bool
    var maximumTextHeight: CGFloat = 180

    private var hasRequest: Bool { !caption.transcript.isEmpty }
    private var title: String {
        if confirming && hasRequest { return "요청을 확인하고 있어요" }
        if hasRequest && listening { return "듣고 있어요" }
        if speaking { return "말하고 있어요" }
        return listening ? "듣고 있어요" : "음성 입력을 준비하고 있어요"
    }
    private var symbol: String {
        if confirming && hasRequest { return "clock" }
        return speaking && !hasRequest ? "speaker.wave.2" : "waveform"
    }
    private var displayedText: String {
        if hasRequest { return caption.transcript }
        if speaking && !caption.narration.isEmpty { return caption.narration }
        return "공연 이름을 말씀해주세요."
    }
    private var hint: String {
        if confirming && hasRequest { return "말씀하신 내용을 확인하고 있어요." }
        if speaking && !hasRequest { return "인사를 들은 뒤 한국어로 요청해주세요." }
        return "말씀이 끝나면 내용을 확인해요."
    }
    private var microphoneStatus: String {
        if confirming { return "말씀 확인 중 · 음성 입력 대기" }
        if listening { return speaking ? "마이크 켜짐 · 안내 중에도 요청할 수 있어요" : "마이크 켜짐 · 요청 듣는 중" }
        return "마이크 입력 준비 중"
    }

    var body: some View {
        VStack(spacing:16) {
            Label(title,systemImage:symbol).font(.subheadline)
                .accessibilityIdentifier("home.voice.caption.status")
            ViewThatFits(in:.vertical) {
                captionText
                ScrollView {captionText}.frame(height:maximumTextHeight)
            }.frame(maxHeight:maximumTextHeight).fixedSize(horizontal:false,vertical:true)
            Text(hint).font(.subheadline).foregroundStyle(HearV3.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            Text(microphoneStatus).font(.caption.weight(.medium)).multilineTextAlignment(.center)
                .accessibilityIdentifier("home.voice.caption.microphone")
        }.frame(maxWidth:.infinity).foregroundStyle(HearV3.text)
    }

    private var captionText: some View {
        Text(displayedText).font(.title3.bold()).multilineTextAlignment(.center)
            .frame(maxWidth:.infinity).fixedSize(horizontal:false,vertical:true)
            .accessibilityIdentifier("home.voice.caption.text")
    }
}
