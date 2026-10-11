import Foundation

/// One destination, relative to the front confirmed at the previous spot.
public struct RouteSpot: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var clock: Int
    public var steps: Int
    public init(name: String = "다음 스팟", clock: Int = 12, steps: Int = 12) {
        self.name = name; self.clock = clock; self.steps = steps
    }
    public var instruction: String { "\(clock)시 방향 · \(steps)걸음" }
}

public struct Route: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var spots: [RouteSpot]
    public init(name: String = "새 경로", spots: [RouteSpot] = [.init()]) {
        self.name = name; self.spots = spots
    }
    public var totalSteps: Int { spots.reduce(0) { $0 + $1.steps } }
    public var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "경로 이름을 입력해 주세요." }
        if !(1...20).contains(spots.count) { return "스팟은 1~20개로 설정해 주세요." }
        if spots.contains(where: { !(1...12).contains($0.clock) || !(1...300).contains($0.steps) }) {
            return "방향은 1~12시, 걸음은 1~300으로 설정해 주세요."
        }
        return nil
    }
    public static var example: Route {
        Route(name: "실내 POC", spots: [
            .init(name: "첫 스팟", clock: 12, steps: 12),
            .init(name: "두 번째 스팟", clock: 3, steps: 10),
            .init(name: "도착점", clock: 9, steps: 10)
        ])
    }
}

public struct TrackingSettings: Codable, Equatable, Sendable {
    public var voice = true
    public var haptics = true
    public init() {}
}

public enum RunPhase: String, Codable, Sendable {
    case reference, aiming, walking, arrival, paused, completed, ended
    public var isFinished: Bool { self == .completed || self == .ended }
    public var title: String {
        switch self {
        case .reference: return "출발 정면 설정"
        case .aiming: return "방향 맞추기"
        case .walking: return "이동 중"
        case .arrival: return "자동 도착 대기"
        case .paused: return "일시정지"
        case .completed: return "경로 완료"
        case .ended: return "측정 종료"
        }
    }
}

public struct MotionObservation: Sendable {
    public var time: Double
    public var heading: Double
    public var rotationRate: Double
    public var acceleration: Double
    public var horizontalProjection: Double
    public var verticalAcceleration: Double
    public var gravityResidual: Double
    public init(time: Double, heading: Double, rotationRate: Double = 0, acceleration: Double = 0,
                horizontalProjection: Double = 1, verticalAcceleration: Double = 0, gravityResidual: Double = 0) {
        self.time = time; self.heading = heading; self.rotationRate = rotationRate
        self.acceleration = acceleration; self.horizontalProjection = horizontalProjection
        self.verticalAcceleration = verticalAcceleration
        self.gravityResidual = gravityResidual
    }
    public var isValid: Bool {
        [time, heading, rotationRate, acceleration, horizontalProjection, verticalAcceleration, gravityResidual].allSatisfy(\.isFinite)
            && rotationRate >= 0 && acceleration >= 0 && (0.6...1.01).contains(horizontalProjection)
            && (0...0.15).contains(gravityResidual)
    }
}

public enum HapticCue: String, Codable, CaseIterable, Sendable {
    case none, start, turn, stop, success, warning
    public var title: String {
        switch self {
        case .none: return "없음"; case .start: return "출발"; case .turn: return "방향 안내"
        case .stop: return "정지"; case .success: return "완료"; case .warning: return "확인 필요"
        }
    }
    public var patternDescription: String {
        switch self {
        case .none: return "진동 없음"; case .start: return "짧게 한 번"; case .turn: return "짧게 두 번"
        case .stop: return "길게 한 번"; case .success: return "부드럽게 두 번"; case .warning: return "강하게 세 번"
        }
    }
    public var exampleSpeech: String {
        switch self {
        case .none: return ""; case .start: return "12걸음."; case .turn: return "3시로."
        case .stop: return "정지."; case .success: return "완료."; case .warning: return "정지. 착용 확인."
        }
    }
}
public enum GuidancePriority: Int, Codable, Sendable {
    case status, navigation, safety
}
public struct GuidanceCue: Codable, Equatable, Sendable {
    public var speech: String
    public var haptic: HapticCue
    // Optional keeps saved records from before priority selection decodable.
    public var priority: GuidancePriority?
    public init(_ speech: String, haptic: HapticCue = .none, priority: GuidancePriority = .navigation) {
        self.speech = speech; self.haptic = haptic; self.priority = priority
    }
    public static func preferred(in cues: [GuidanceCue]) -> GuidanceCue? {
        cues.reduce(nil) { selected, next in
            guard let selected else { return next }
            return (next.priority ?? .navigation).rawValue >= (selected.priority ?? .navigation).rawValue ? next : selected
        }
    }
}
public struct RunEvent: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var time: Double
    public var spot: Int
    public var kind: String
    public var message: String
    public var guidance: GuidanceCue?
}
public struct TraceSample: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var time: Double
    public var spot: Int
    public var revision: Int
    public var phase: RunPhase
    public var relativeHeading: Double
    public var targetHeading: Double
    public var error: Double
    public var steps: Int
    public var stepGoal: Int
    public var estimatedTotal: Int
    public var systemTotal: Int
    public var verticalAcceleration: Double
    public var sensorAge: Double
    public var sensorValid: Bool
    public var rotationRate: Double = 0
    public var accelerationMagnitude: Double = 0
    public var horizontalProjection: Double = 1
    public var gravityResidual: Double = 0
}
public struct SessionRecord: Identifiable, Codable, Sendable {
    public var schemaVersion = 2
    public var id = UUID()
    public var startedAt: Date
    public var endedAt: Date?
    public var route: Route
    public var settings: TrackingSettings
    public var isDemo: Bool
    public var outcome = "측정 중"
    public var samples: [TraceSample] = []
    public var events: [RunEvent] = []
    public var estimatedTotal = 0
    public var systemTotal = 0
    public var confirmedSpots = 0
    public var duration: Double { max(samples.last?.time ?? 0, events.last?.time ?? 0) }
}

public enum Angles {
    public static func signed(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }; if d <= -180 { d += 360 }
        return d
    }
    public static func difference(target: Double, current: Double) -> Double { signed(target - current) }
    public static func clockOffset(_ clock: Int) -> Double { signed(Double(clock % 12) * 30) }
    public static func clock(_ offset: Double) -> Int {
        let sector = Int((signed(offset) / 30).rounded())
        let hour = (sector % 12 + 12) % 12
        return hour == 0 ? 12 : hour
    }
    /// Instructions are relative to the wearer's CURRENT front, not the original reference.
    public static func instruction(error: Double) -> String {
        if abs(error) <= 12 { return "정면." }
        let hour = clock(error)
        if hour == 12 { return "조금 \(error > 0 ? "오른쪽" : "왼쪽")." }
        return "\(hour)시로."
    }
    /// Core Motion's DCM maps reference vectors to device vectors. Its transpose maps
    /// device +Z (the outward screen normal) to reference: (m31, m32, m33).
    /// Using the matrix directly avoids assuming a quaternion-to-matrix convention.
    public static func heading(screenX x: Double, screenY y: Double, screenZ z: Double) -> (degrees: Double, projection: Double) {
        let norm = sqrt(x*x + y*y + z*z)
        guard norm.isFinite, (0.8...1.2).contains(norm) else { return (.nan, .nan) }
        return (-atan2(y, x) * 180 / .pi, hypot(x, y) / norm)
    }
}
