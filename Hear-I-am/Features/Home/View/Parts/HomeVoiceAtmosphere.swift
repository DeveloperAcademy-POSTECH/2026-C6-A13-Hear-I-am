import SwiftUI

/// The home atmosphere keeps its own clock, independent of recognition turns and narration.
struct HomeVoiceWaves: View {
    let awake: Bool
    let animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let colors = [
        Color(red: 0.14, green: 0.30, blue: 0.73),
        Color(red: 0.17, green: 0.73, blue: 0.81),
        Color(red: 0.39, green: 0.35, blue: 0.87)
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animating || reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Image("HearV3Ambient")
                    .resizable().scaledToFill().rotationEffect(.degrees(180)).opacity(0.7)
                Canvas { context, size in
                    for layer in 0..<3 {
                        let index = Double(layer)
                        let center = size.height * (0.20 + index * 0.11)
                        let amplitude = 12 + index * 5
                        let phase = time * (0.42 + index * 0.07) + index * 1.8
                        let points = stride(from: 0.0, through: Double(size.width) + 6, by: 6).map { x in
                            let position = x / max(1, size.width)
                            let wave = sin(position * .pi * 2.4 - phase)
                                + 0.35 * sin(position * .pi * 4 + phase * 0.7)
                            return CGPoint(x: x, y: center + wave * amplitude)
                        }
                        var crest = Path()
                        crest.addLines(points)
                        var ribbon = crest
                        ribbon.addLines(points.reversed().map { CGPoint(x: $0.x, y: $0.y + 54) })
                        ribbon.closeSubpath()
                        let color = Self.colors[layer]
                        context.fill(ribbon, with: .linearGradient(
                            Gradient(colors: [color.opacity(0.35), color.opacity(0.02)]),
                            startPoint: CGPoint(x: 0, y: center - amplitude),
                            endPoint: CGPoint(x: 0, y: center + 80)))
                        var glow = context
                        glow.addFilter(.blur(radius: 16))
                        glow.stroke(crest, with: .color(color.opacity(0.6)), lineWidth: 22)
                        context.stroke(crest, with: .color(color.opacity(0.5)), lineWidth: 1.5)
                    }
                }
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .white, location: 0),
                                         .init(color: .white, location: 0.5),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
        }
        .opacity(awake ? 1 : 0.72)
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
