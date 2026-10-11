import SwiftUI
import OrientationCore

/// Place outside NavigationStack (and on top of a settings sheet) to cover the entire display.
struct SignalOverlay: View {
    let angle: Int
    let currentAngle: Double
    var isPreview = false
    var mode: SignalMode = .haptic
    var displayMode: DirectionDisplayMode = .angle
    @ScaledMetric(relativeTo: .largeTitle) private var angleFontSize = 132.0

    private var direction: String { displayMode == .clock ? "기준 정면 · 12시" : "기준에서 시계방향" }
    private var currentText: String {
        displayMode.value(currentAngle)
    }

    var body: some View {
        ZStack {
            Self.backgroundColor(for: angle).ignoresSafeArea()
            VStack(spacing: 18) {
                if isPreview {
                    Text("화면 미리보기")
                        .font(.headline)
                }
                Text("\(mode.title) 신호").font(.headline)
                Text(direction)
                    .font(.largeTitle.bold())
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(displayMode.value(Double(angle)))
                    .font(.system(size: angleFontSize, weight: .black, design: .rounded))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.3)
                Text("현재 \(currentText)")
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(Self.foregroundColor(for: angle))
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isPreview ? "화면 미리보기. " : "")\(displayMode.accessibilityLabel(Double(angle))) \(mode.title) 신호. 현재 \(displayMode.accessibilityLabel(currentAngle))")
        .accessibilityIdentifier("signal-overlay")
    }

    static func backgroundColor(for angle: Int) -> Color {
        switch angle {
        case -30: Color(red: 0.078, green: 0.341, blue: 0.769)
        case -60: Color(red: 0.188, green: 0.212, blue: 0.627)
        case -90: Color(red: 0.424, green: 0.153, blue: 0.663)
        case 30: Color(red: 1.0, green: 0.835, blue: 0.310)
        case 60: Color(red: 1.0, green: 0.541, blue: 0.239)
        case 90: Color(red: 0.718, green: 0.098, blue: 0.141)
        default: Color(red: 0.12, green: 0.15, blue: 0.20)
        }
    }

    static func foregroundColor(for angle: Int) -> Color {
        angle == 30 || angle == 60 ? .black : .white
    }
}
