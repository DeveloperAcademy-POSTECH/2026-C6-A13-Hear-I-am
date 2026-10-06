import SwiftUI

enum Theme {
    static let accent = Color.blue
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let amber = Color(red: 0.7, green: 0.35, blue: 0.04)
}

struct LabCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct LabButtonStyle: PrimitiveButtonStyle {
    var prominent = true
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if prominent {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 24)
            }.buttonStyle(.borderedProminent).controlSize(.large)
        } else {
            Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 24)
            }.buttonStyle(.bordered).controlSize(.large)
        }
    }
}

struct CodeBadge: View {
    let code: String
    var body: some View {
        Text(code).font(.headline).frame(width: 36, height: 36)
            .foregroundStyle(.white).background(Theme.accent, in: RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
    }
}

struct DeviceBanner: View {
    @EnvironmentObject private var haptics: HapticService
    var body: some View {
        if haptics.isPreview || !haptics.supportsHaptics {
            Label(haptics.isPreview ? "화면 미리보기 · 실제 진동 없음" : "실제 iPhone에서 진동을 체험해 주세요", systemImage: "iphone.radiowaves.left.and.right")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PatternTimeline: View {
    let pattern: HapticPattern
    var height: CGFloat = 62
    var minimumDuration: Double = 0
    var body: some View {
        Canvas { context, size in
            let total = max(pattern.steps.reduce(0) { $0 + $1.scheduledDuration }, max(minimumDuration, 0.1))
            var time = 0.0
            var baseline = Path()
            baseline.move(to: CGPoint(x: 0, y: size.height - 2))
            baseline.addLine(to: CGPoint(x: size.width, y: size.height - 2))
            context.stroke(baseline, with: .color(.secondary.opacity(0.2)), lineWidth: 1)
            for step in pattern.steps {
                let x = time / total * size.width
                let width = max(3, step.scheduledDuration / total * size.width - 3)
                if step.kind != .pause {
                    let levels = step.kind == .tap ? [1.0, 1.0] : step.envelope.levels
                    let amplitude = max(8, (size.height - 6) * step.intensity)
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height - 2))
                    for (index, value) in levels.enumerated() {
                        path.addLine(to: CGPoint(x: x + width * Double(index) / Double(levels.count - 1), y: size.height - 2 - amplitude * value))
                    }
                    path.addLine(to: CGPoint(x: x + width, y: size.height - 2)); path.closeSubpath()
                    context.fill(path, with: .color(Theme.accent.opacity(0.45 + step.sharpness * 0.5)))
                }
                time += step.scheduledDuration
            }
        }
        .frame(height: height)
        .accessibilityLabel("설계 타임라인. \(pattern.summary). \(pattern.repetitions)회 반복.")
    }
}

struct DirectionSelector: View {
    @Binding var selection: Direction
    var body: some View {
        Picker("방향", selection: $selection) {
            ForEach(Direction.allCases) { Text("\($0.arrow) \($0.title)").tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("directionPicker")
    }
}

struct DirectionPad: View {
    var enabled = true
    var action: (Direction) -> Void
    var body: some View {
        VStack(spacing: 10) {
            directionButton(.front).frame(maxWidth: 170)
            HStack(spacing: 10) { directionButton(.left); directionButton(.right) }
            directionButton(.back).frame(maxWidth: 170)
        }.disabled(!enabled).opacity(enabled ? 1 : 0.5)
    }
    private func directionButton(_ direction: Direction) -> some View {
        Button { action(direction) } label: {
            Label(direction.title, systemImage: direction.symbol).frame(minHeight: 24)
        }.buttonStyle(LabButtonStyle(prominent: false))
            .accessibilityIdentifier("direction_\(direction.rawValue)")
    }
}

struct ParameterControl: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var scale: Double = 1
    var unit = ""
    var identifier = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                TextField(title, value: scaled, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .frame(width: 64).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(title) 값")
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button { value = max(range.lowerBound, value - step) } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                    .accessibilityLabel("\(title) 줄이기")
                Slider(value: $value, in: range, step: step).accessibilityLabel(title)
                Button { value = min(range.upperBound, value + step) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("\(title) 늘리기")
                    .accessibilityIdentifier(identifier.isEmpty ? "" : "\(identifier)_increase")
            }.buttonStyle(.borderless)
        }
    }
    private var scaled: Binding<Double> {
        Binding(get: { value * scale }, set: { if $0.isFinite { value = min(range.upperBound, max(range.lowerBound, $0 / scale)) } })
    }
}

struct ContextFields: View {
    @Binding var context: StudyContext
    var body: some View {
        Group {
            Picker("휴대 위치", selection: $context.placement) {
                ForEach(["손에 쥠", "앞주머니", "몸에 고정", "기타"], id: \.self) { Text($0).tag($0) }
            }
            Picker("활동", selection: $context.activity) {
                ForEach(["정지", "걷기", "공연 동작"], id: \.self) { Text($0).tag($0) }
            }
            Picker("응답 입력", selection: $context.inputMode) {
                ForEach(InputMode.allCases) { Text($0.title).tag($0) }
            }
        }.pickerStyle(.menu)
    }
}

func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0 * 100) } ?? "—" }

struct Metric: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(.title, design: .rounded).bold()).monospacedDigit().foregroundStyle(Theme.accent)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
