import SwiftUI
import HearIAmCore

/// Soft, slowly drifting light stays below the waiting screen without covering controls.
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
