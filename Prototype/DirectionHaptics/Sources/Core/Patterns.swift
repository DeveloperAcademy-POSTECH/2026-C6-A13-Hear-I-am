import Foundation

public enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
    case front, back, left, right
    public var id: String { rawValue }
    public var title: String {
        switch self { case .front: return "앞"; case .back: return "뒤"; case .left: return "왼쪽"; case .right: return "오른쪽" }
    }
    public var symbol: String {
        switch self { case .front: return "arrow.up"; case .back: return "arrow.down"; case .left: return "arrow.left"; case .right: return "arrow.right" }
    }
    public var arrow: String {
        switch self { case .front: return "↑"; case .back: return "↓"; case .left: return "←"; case .right: return "→" }
    }
}

public enum StepKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case tap, continuous, pause
    public var id: String { rawValue }
    public var title: String {
        switch self { case .tap: return "짧은 탭"; case .continuous: return "연속 진동"; case .pause: return "쉼" }
    }
}

public enum Envelope: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat, rise, fall, hill, valley
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .flat: return "일정하게"
        case .rise: return "점점 강하게"
        case .fall: return "점점 약하게"
        case .hill: return "약 → 강 → 약"
        case .valley: return "강 → 약 → 강"
        }
    }
    /// Relative multipliers, not physical acceleration or frequency.
    public var levels: [Double] {
        switch self {
        case .flat: return [1, 1]
        case .rise: return [0.2, 1]
        case .fall: return [1, 0.2]
        case .hill: return [0.2, 1, 0.2]
        case .valley: return [1, 0.2, 1]
        }
    }
}

public struct HapticStep: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: StepKind
    public var duration: Double
    public var intensity: Double
    public var sharpness: Double
    public var envelope: Envelope

    public init(kind: StepKind, duration: Double = 0.35, intensity: Double = 1,
                sharpness: Double = 0.5, envelope: Envelope = .flat, id: UUID = UUID()) {
        self.id = id; self.kind = kind; self.duration = duration
        self.intensity = intensity; self.sharpness = sharpness; self.envelope = envelope
    }
    /// A transient has no configurable duration; reserve a 70 ms scheduling slot.
    public var scheduledDuration: Double { kind == .tap ? 0.07 : duration }
    public static func tap(_ intensity: Double = 1, sharpness: Double = 0.5) -> Self {
        .init(kind: .tap, intensity: intensity, sharpness: sharpness)
    }
    public static func buzz(_ duration: Double, intensity: Double = 1,
                            sharpness: Double = 0.5, envelope: Envelope = .flat) -> Self {
        .init(kind: .continuous, duration: duration, intensity: intensity, sharpness: sharpness, envelope: envelope)
    }
    public static func rest(_ duration: Double) -> Self { .init(kind: .pause, duration: duration) }
}

public struct HapticPattern: Codable, Equatable, Sendable {
    public var steps: [HapticStep]
    public var repetitions: Int
    public var repeatGap: Double
    public init(steps: [HapticStep], repetitions: Int = 1, repeatGap: Double = 0.4) {
        self.steps = steps; self.repetitions = repetitions; self.repeatGap = repeatGap
    }
    public var duration: Double {
        steps.reduce(0) { $0 + $1.scheduledDuration } * Double(repetitions)
        + Double(max(0, repetitions - 1)) * repeatGap
    }
    public var summary: String {
        steps.map {
            switch $0.kind {
            case .tap: return "탭"
            case .continuous: return "진동 \(Int($0.duration * 1_000))ms"
            case .pause: return "쉼 \(Int($0.duration * 1_000))ms"
            }
        }.joined(separator: " · ")
    }
    public var validationIssue: String? {
        guard (1...16).contains(steps.count) else { return "블록은 1~16개로 구성해 주세요." }
        guard steps.contains(where: { $0.kind != .pause }) else { return "탭 또는 연속 진동을 하나 이상 넣어 주세요." }
        guard (1...5).contains(repetitions), repeatGap.isFinite, (0.1...2).contains(repeatGap) else {
            return "반복은 1~5회, 반복 간격은 100~2000ms로 설정해 주세요."
        }
        for step in steps {
            guard step.intensity.isFinite, (0.1...1).contains(step.intensity),
                  step.sharpness.isFinite, (0...1).contains(step.sharpness) else {
                return "강도는 10~100%, 촉감은 0~100%로 설정해 주세요."
            }
            if step.kind != .tap && (!step.duration.isFinite || !(0.03...2).contains(step.duration)) {
                return "진동과 쉼의 길이는 30~2000ms로 설정해 주세요."
            }
        }
        guard duration.isFinite, duration <= 12 else { return "전체 패턴은 12초 이내로 설정해 주세요." }
        return nil
    }
}

public struct PatternSet: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var code: String
    public var detail: String
    public var isBuiltIn: Bool
    public var revision: Int
    public var sourceID: UUID?
    public var updatedAt: Date
    public var patterns: [Direction: HapticPattern]

    public init(id: UUID = UUID(), name: String, code: String = "MY", detail: String = "",
                isBuiltIn: Bool = false, revision: Int = 1, sourceID: UUID? = nil,
                updatedAt: Date = Date(), patterns: [Direction: HapticPattern]) {
        self.id = id; self.name = name; self.code = code; self.detail = detail
        self.isBuiltIn = isBuiltIn; self.revision = revision; self.sourceID = sourceID
        self.updatedAt = updatedAt; self.patterns = patterns
    }
    public func pattern(for direction: Direction) -> HapticPattern {
        patterns[direction] ?? HapticPattern(steps: [])
    }
    public var validationIssue: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "세트 이름을 입력해 주세요." }
        for direction in Direction.allCases {
            if let issue = pattern(for: direction).validationIssue { return "\(direction.title): \(issue)" }
        }
        return nil
    }
    public func userCopy(named name: String? = nil) -> Self {
        var copy = self
        copy.id = UUID(); copy.sourceID = id; copy.revision = 1; copy.isBuiltIn = false
        copy.name = name ?? "\(self.name) · 나의 세트"; copy.code = "MY"; copy.updatedAt = Date()
        return copy
    }
    public mutating func swap(_ first: Direction, _ second: Direction) {
        let value = patterns[first]; patterns[first] = patterns[second]; patterns[second] = value
    }
}

public struct ScheduledPulse: Equatable, Sendable {
    public var kind: StepKind
    public var start: Double
    public var duration: Double
    public var intensity: Double
    public var sharpness: Double
    public var envelope: Envelope
}

public struct CompiledPattern: Sendable {
    public var pulses: [ScheduledPulse]
    public var duration: Double
}

public enum PatternError: LocalizedError { case invalid(String)
    public var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

public enum PatternCompiler {
    public static func compile(_ pattern: HapticPattern, gain: Double = 1) throws -> CompiledPattern {
        if let issue = pattern.validationIssue { throw PatternError.invalid(issue) }
        guard gain.isFinite, (0.2...1).contains(gain) else { throw PatternError.invalid("전체 세기는 20~100%로 설정해 주세요.") }
        var time = 0.0
        var pulses: [ScheduledPulse] = []
        for repeatIndex in 0..<pattern.repetitions {
            for step in pattern.steps {
                if step.kind != .pause {
                    pulses.append(.init(kind: step.kind, start: time,
                                        duration: step.kind == .tap ? 0 : step.duration,
                                        intensity: step.intensity * gain, sharpness: step.sharpness,
                                        envelope: step.kind == .tap ? .flat : step.envelope))
                }
                time += step.scheduledDuration
            }
            if repeatIndex < pattern.repetitions - 1 { time += pattern.repeatGap }
        }
        return .init(pulses: pulses, duration: time)
    }
}
