import Foundation

/// Stage +X is right on the plan; +Y points backstage. A participant facing
/// the audience has heading (0,-1), so their RIGHT points toward stage -X.
enum BodyNavigationMath {
    static func wrap(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return .nan }
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value > 180 ? value - 360 : value < -180 ? value + 360 : value
    }

    /// Core Motion reference->device rotation: transpose(R) * device +Z is row 3.
    static func outwardHeading(m31: Double, m32: Double, m33: Double) -> Double? {
        guard m31.isFinite, m32.isFinite, m33.isFinite else { return nil }
        let horizontal = hypot(m31, m32)
        let norm = hypot(horizontal, m33)
        guard abs(norm - 1) < 0.03, horizontal / norm >= 0.25 else { return nil }
        return wrap(-atan2(m32, m31) * 180 / .pi)
    }

    static func stageHeading(relativeDegrees: Double) -> MapPoint {
        let radians = relativeDegrees * .pi / 180
        return MapPoint(-sin(radians), -cos(radians))
    }

    static func validPoint(_ p: MapPoint) -> Bool {
        p.x.isFinite && p.y.isFinite && abs(p.x) <= 200 && abs(p.y) <= 200
    }

    static func instruction(position: MapPoint, target: MapPoint, relativeDegrees: Double) -> BodyInstruction? {
        guard validPoint(position), validPoint(target), relativeDegrees.isFinite else { return nil }
        let cue = GuidanceMath.cue(position: position, target: target,
                                   heading: stageHeading(relativeDegrees: relativeDegrees))
        let angle = cue.turnRadians * 180 / .pi
        if cue.state == .arrived { return BodyInstruction(kind: .arrived, degrees: 0, distance: cue.distanceMeters) }
        let kind: BodyInstruction.Kind = abs(angle) <= 12 ? .forward : angle > 0 ? .right : .left
        return BodyInstruction(kind: kind, degrees: angle, distance: cue.distanceMeters)
    }
}

enum DirectionSpeechStyle: String, CaseIterable {
    case angle, clock
    var title: String { self == .angle ? "각도" : "시계 방향" }
    static func hour(degrees: Double) -> Int {
        guard degrees.isFinite else { return 12 }
        let index = (Int((BodyNavigationMath.wrap(degrees) / 30).rounded()) % 12 + 12) % 12
        return index == 0 ? 12 : index
    }
}

enum DistanceSpeechStyle: String, CaseIterable {
    case meters, steps
    var title: String { self == .meters ? "미터" : "걸음 수" }
}

enum StepLengthUnit: String, CaseIterable {
    case cm, m
    func meters(_ value: Double) -> Double { self == .cm ? value / 100 : value }
    func value(meters: Double) -> Double { self == .cm ? meters * 100 : meters }
}

enum StepGuidance {
    static func validLength(_ meters: Double) -> Bool { meters.isFinite && (0.1...2).contains(meters) }
    static func parse(_ text: String, unit: StepLengthUnit) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")) else { return nil }
        let meters = unit.meters(value)
        return validLength(meters) ? meters : nil
    }
    static func forward(distance: Double, stepLength: Double) -> String {
        guard distance.isFinite, distance >= 0, distance <= 600, validLength(stepLength) else { return "거리와 보폭을 확인해주세요" }
        if distance < stepLength { return "앞으로 작게 한 걸음" }
        let steps = max(1, Int(floor(distance / stepLength + 1e-9)))
        return "앞으로 약 \(steps)걸음"
    }
}

struct BodyInstruction: Equatable {
    enum Kind: String { case left, right, forward, arrived }
    let kind: Kind
    let degrees: Double
    let distance: Double
    var spoken: String { spoken(style: .angle) }
    func spoken(style: DirectionSpeechStyle, distanceStyle: DistanceSpeechStyle = .meters, stepLength: Double = 0.6) -> String {
        if style == .clock, kind == .left || kind == .right {
            let hour = DirectionSpeechStyle.hour(degrees: degrees)
            if hour == 12 { return "12시 방향에 가깝습니다. \(kind == .left ? "왼쪽" : "오른쪽")으로 조금 돌아주세요" }
            return "\(hour)시 방향으로 돌아주세요"
        }
        switch kind {
        case .arrived: return "도착했습니다. 멈추세요."
        case .forward:
            return distanceStyle == .steps ? StepGuidance.forward(distance: distance, stepLength: stepLength) : String(format: "앞으로 %.1f미터", distance)
        case .left, .right:
            let rounded = max(15, Int((abs(degrees) / 15).rounded()) * 15)
            return "\(kind == .left ? "왼쪽" : "오른쪽")으로 \(rounded)도 돌아주세요"
        }
    }
}

struct WearerPoll: Codable {
    var id = UUID()
    var calibratedReference: UUID?
    var relativeDegrees: Double?
    var speakerReady = false
    var bodyReady = false
    var stoppedRun: UUID?
    var arrivedRun: UUID?
}

struct StageReply: Codable {
    let pollID: UUID
    let revision: UInt64
    let routeID: UUID
    let referenceID: UUID?
    let runID: UUID?
    let polygon: [MapPoint]
    let start: MapPoint?
    let position: MapPoint?
    let target: MapPoint?
    /// Age measured ONLY on the operator device; never compare different devices' uptime.
    let positionAge: Double
    let message: String
}

enum PeerMessage: Codable {
    case poll(WearerPoll)
    case stage(StageReply)
    case stop(UUID?)
}

/// Matches replies against local requests. An old queued response cannot rejuvenate a pose.
struct ReplyClock {
    private var pending: [UUID: Double] = [:]
    private var lastAccepted = -Double.infinity
    mutating func issue(_ id: UUID, at now: Double) {
        pending = pending.filter { now - $0.value <= 1 }
        pending[id] = now
    }
    mutating func accept(_ id: UUID, at now: Double) -> Double? {
        guard let sent = pending.removeValue(forKey: id), sent > lastAccepted,
              now >= sent, now - sent <= 0.5 else { return nil }
        lastAccepted = sent
        return sent
    }
    static func positionDeadline(sent: Double, age: Double) -> Double? {
        guard sent.isFinite, age.isFinite, age >= 0, age <= 0.5 else { return nil }
        return sent + 0.5 - age
    }
}

/// Completion requires continuous fresh in-radius samples, then remains latched for this run.
struct ArrivalGate {
    private var entered: Double?
    private(set) var completed = false
    mutating func update(inside: Bool, now: Double) -> Bool {
        if completed { return true }
        guard inside else { entered = nil; return false }
        if entered == nil { entered = now }
        if let entered, now - entered >= 0.6 { completed = true }
        return completed
    }
}

/// A late start packet must not restart a run already stopped locally or remotely.
struct RunLedger {
    private var retired = Set<UUID>()
    private var revision: UInt64 = 0
    mutating func accept(revision incoming: UInt64) -> Bool {
        guard incoming >= revision else { return false }
        revision = incoming
        return true
    }
    mutating func retire(_ run: UUID) { retired.insert(run) }
    func permits(_ run: UUID) -> Bool { !retired.contains(run) }
}
