import SwiftUI
import HearIAmCore

// Listening feedback uses the existing audio session; these views never request microphone access.
private enum VoiceGlassPalette {
    static let cyan = Color(red: 0.18, green: 0.77, blue: 0.88)
    static let blue = Color(red: 0.30, green: 0.48, blue: 0.90)
    static let violet = Color(red: 0.62, green: 0.43, blue: 0.88)
}

/// Covers the screen while the voice agent listens; a tap (or the VoiceOver action) closes it (#92).
struct VoiceDismissLayer: View {
    let dismiss: () -> Void
    var body: some View {
        Color.clear.contentShape(Rectangle()).ignoresSafeArea()
            .onTapGesture(perform: dismiss)
            .accessibilityElement()
            .accessibilityLabel("음성 비서 닫기")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dismiss() }
    }
}

/// Siri-style light around the screen edge while the app takes requests (#90). It never covers what is
/// on screen, and it swells and wavers with the speaker's voice.
struct VoiceEdgeGlow: View {
    @ObservedObject var visualization: VoiceInputVisualization
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let colors = [VoiceGlassPalette.cyan, VoiceGlassPalette.blue, VoiceGlassPalette.violet,
                                 Color(red: 0.96, green: 0.42, blue: 0.62), Color(red: 1.0, green: 0.62, blue: 0.30), VoiceGlassPalette.cyan]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let level = active ? visualization.level : 0
            let waver = reduceMotion ? 0 : (sin(time * 7.3) + sin(time * 11.9)) * 0.5 * level
            let width = 4 + level * 10 + waver * 4
            let turn = reduceMotion ? 0 : (time * 45).truncatingRemainder(dividingBy: 360)
            let gradient = AngularGradient(gradient: Gradient(colors: Self.colors), center: .center,
                                           startAngle: .degrees(turn), endAngle: .degrees(turn + 360))
            let shape = RoundedRectangle(cornerRadius: 56, style: .continuous)
            ZStack {
                shape.strokeBorder(gradient, lineWidth: width * 2.2).blur(radius: 20 + level * 16).opacity(0.75)
                shape.strokeBorder(gradient, lineWidth: width).blur(radius: 6)
                shape.strokeBorder(gradient, lineWidth: 2.5)
            }
        }
        .ignoresSafeArea()
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: reduceMotion ? 0.1 : 0.35), value: active)
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
