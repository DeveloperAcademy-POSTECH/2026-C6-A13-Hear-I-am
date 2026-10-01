import Foundation

struct GuidePerson: Identifiable, Equatable {
    var id: Int
    var point: MapPoint
}

/// Audio adapter contract. Positive angle/pan means P should turn RIGHT.
/// A consumer must mute unless state == guiding, and expire packets after 0.5s.
struct GuidanceCue: Codable, Equatable {
    enum State: String, Codable { case paused, guiding, arrived }
    var state: State = .paused
    var distanceMeters: Double = 0
    var turnRadians: Double = 0
    var pan: Double = 0
    var gain: Double = 0
    var pulseIntervalSeconds: Double = 0.6
    var validForSeconds: Double = 0.5
    var sampleUptimeSeconds: Double = 0
}

enum GuidanceMath {
    /// Conservative: touching the boundary is also rejected. No obstacle detection.
    static func routeInside(_ a: MapPoint, _ b: MapPoint, polygon: [MapPoint]) -> Bool {
        guard StageGeometry.contains(a, polygon: polygon), StageGeometry.contains(b, polygon: polygon) else { return false }
        return !polygon.indices.contains {
            StageGeometry.intersects(a, b, polygon[$0], polygon[($0 + 1) % polygon.count])
        }
    }
    static func cue(position: MapPoint, target: MapPoint, heading: MapPoint) -> GuidanceCue {
        let delta = target - position
        let distance = delta.length
        if distance <= 0.3 { return GuidanceCue(state: .arrived, distanceMeters: distance) }
        guard heading.length > 0.001 else { return GuidanceCue(distanceMeters: distance) }
        let angle = atan2(-heading.cross(delta), heading.dot(delta))
        return GuidanceCue(state: .guiding, distanceMeters: distance, turnRadians: angle,
                           pan: max(-1, min(1, angle / (.pi / 2))),
                           gain: BeaconMath.distanceGain(distance))
    }
}

struct GuidanceState {
    init(polygon: [MapPoint] = [], usesHeadTracking: Bool = false) {
        self.polygon = polygon
        self.usesHeadTracking = usesHeadTracking
    }
    let usesHeadTracking: Bool
    var polygon: [MapPoint] = []
    private(set) var people: [GuidePerson] = []
    private(set) var selectedID: Int?
    private(set) var trackingMessage = "P를 한 번 선택해주세요."
    private(set) var hasVisualContact = false
    private var visualTime: Double = -.infinity
    private(set) var target: MapPoint?
    private(set) var heading: MapPoint?
    private(set) var cue = GuidanceCue()
    private(set) var message = "P 한 명을 카메라에 담아주세요."
    private(set) var active = false
    private var lastObservation: Double = -.infinity
    private var motionPoint: MapPoint?
    private var motionTime: Double = 0
    private var headingTime: Double = -.infinity
    private var startTime: Double = -.infinity
    var position: MapPoint? { people.first { $0.id == selectedID }?.point }

    mutating func receive(_ detections: [GuidePerson], time: Double,
                          visualContact: Bool? = nil, detail: String? = nil) {
        // This PoC assumes ONE person. Identity is an operator latch, not per-frame IDs.
        hasVisualContact = visualContact ?? !detections.isEmpty
        if hasVisualContact { visualTime = time }
        trackingMessage = detail ?? (hasVisualContact ? "P 영상 추적 중" : "P 화면 밖 · 선택 유지")
        guard let detection = detections.first else {
            // An isolated depth miss must not chop a pulse while the same visible P's
            // last measurement is still valid. Never advance its measurement timestamp.
            if hasVisualContact, position != nil, BeaconMath.fresh(lastObservation, now: time) {
                trackingMessage = "P 영상 유지 · 최근 위치 사용 (최대 0.5초)"
                if active { evaluate(time: time) }
                return
            }
            waitForPosition(trackingMessage); return
        }
        let wasWaiting = people.isEmpty
        people = [GuidePerson(id: selectedID ?? detection.id, point: detection.point)]
        lastObservation = time
        guard let p = position else { return }
        if wasWaiting && !active { message = "P 위치 복구 · 목적지와 방향을 확인해주세요." }
        if active {
            if motionPoint == nil { motionPoint = p; motionTime = time }
            if !usesHeadTracking, let origin = motionPoint, time - motionTime >= 0.5 {
                let delta = p - origin
                if delta.length >= 0.15 {
                    heading = delta * (1 / delta.length); headingTime = time
                    motionPoint = p; motionTime = time
                } else if time - motionTime > 1.2 {
                    motionPoint = p; motionTime = time
                }
            }
            evaluate(time: time)
        }
    }
    mutating func select(_ id: Int, time: Double) {
        guard time - lastObservation <= 0.5, people.count == 1, people.first?.id == id else { return }
        pause("P 선택 완료 · D와 P가 바라보는 방향을 지정하세요.")
        selectedID = id
        trackingMessage = "P 지정 유지 · 1인 추적"
    }
    mutating func setTarget(_ point: MapPoint) {
        guard StageGeometry.contains(point, polygon: polygon) else { message = "D는 무대 내부에 지정해주세요."; return }
        if let position, !GuidanceMath.routeInside(position, point, polygon: polygon) {
            message = "P→D 직선이 무대 경계에 닿거나 밖으로 나갑니다."; return
        }
        pause("D 지정 완료 · P의 방향을 맞춘 뒤 방향을 지정하세요.")
        target = point
    }
    @discardableResult
    mutating func setHeading(toward point: MapPoint, time: Double) -> Bool {
        guard selectedID != nil else {
            message = "P를 먼저 선택해주세요."; return false
        }
        guard let position, BeaconMath.fresh(lastObservation, now: time) else {
            message = "P 위치 측정 대기 · 몸통이 보이도록 촬영한 뒤 방향을 다시 찍으세요."; return false
        }
        guard point.x.isFinite, point.y.isFinite, (point - position).length >= 0.2 else {
            message = "P에서 20cm 이상 떨어진 방향을 찍으세요."; return false
        }
        pause("초기 방향 지정 완료 · P를 그 방향으로 정렬한 뒤 안내를 시작하세요.")
        heading = (point - position) * (1 / (point - position).length)
        headingTime = time
        return true
    }
    /// Audio and displayed direction share the calibrated HEAD direction in live mode.
    mutating func receiveHeadHeading(_ value: MapPoint, time: Double) {
        guard usesHeadTracking, heading != nil, value.length > 0.001 else { return }
        heading = value * (1 / value.length)
        headingTime = time
    }
    mutating func start(time: Double) {
        guard let position, let target, heading != nil, time - lastObservation <= 0.5,
              time - headingTime <= (usesHeadTracking ? 0.5 : 15) else { message = "P·D·초기 방향을 다시 확인해주세요."; return }
        guard GuidanceMath.routeInside(position, target, polygon: polygon) else {
            pause("직선 이동 불가 · 무대 안쪽으로 P 또는 D를 변경하세요."); return
        }
        active = true; motionPoint = position; motionTime = time; startTime = time
        evaluate(time: time)
    }
    mutating func pause(_ reason: String = "일시 정지 · P의 방향을 다시 지정해주세요.") {
        active = false; heading = nil; motionPoint = nil; cue = GuidanceCue(); message = reason
    }
    /// Keep P selection and fresh head calibration, but NEVER emit a stale position cue.
    mutating func waitForPosition(_ reason: String) {
        people = []; cue = GuidanceCue()
        motionPoint = nil
        message = selectedID == nil ? "P를 먼저 선택해주세요." : "P 지정 유지 · 위치 측정 대기"
        trackingMessage = reason
    }
    mutating func clearSelection() {
        selectedID = nil; pause("P 선택을 해제했습니다.")
    }
    /// Only a session reset invalidates the operator's identity latch.
    mutating func invalidate(_ reason: String) {
        people = []; selectedID = nil; hasVisualContact = false; pause(reason)
    }
    mutating func expire(time: Double) {
        if time - visualTime > 0.5 { hasVisualContact = false }
        if time - lastObservation > 0.5 {
            waitForPosition(hasVisualContact ? trackingMessage : "영상/위치 측정 대기 · P 선택은 유지됩니다.")
        } else if active && position != nil { evaluate(time: time) }
    }
    private mutating func evaluate(time: Double) {
        guard let position, let target, let heading else { pause(); return }
        guard GuidanceMath.routeInside(position, target, polygon: polygon) else {
            pause("P→D 직선이 무대 경계에 닿습니다 · 안내 정지"); return
        }
        if usesHeadTracking && time - headingTime > 0.5 {
            if BeaconMath.retainsHeadCalibration(headingTime, now: time) {
                cue = GuidanceCue()
                message = "머리 방향 수신 지연 · 잠시 무음, 방향 보정 유지"
            } else {
                pause("머리 방향이 2초 이상 갱신되지 않았습니다 · 수신 확인 후 방향을 다시 지정해주세요.")
            }
            return
        }
        var next = GuidanceMath.cue(position: position, target: target, heading: heading)
        next.sampleUptimeSeconds = lastObservation
        if next.state == .arrived {
            cue = next; active = false; self.heading = nil; message = "도착 · D의 0.3m 이내"; return
        }
        // Brief startup grace allows the first forward step; never infer body yaw at rest.
        if !usesHeadTracking && time - startTime > 3 && time - headingTime > 1.5 {
            pause("이동 방향 확인 불가 · 정렬 후 방향을 다시 지정해주세요."); return
        }
        cue = next
        let degrees = next.turnRadians * 180 / .pi
        let reference = usesHeadTracking ? "머리 기준" : "P 기준"
        message = abs(degrees) <= 12 ? "목표 방향과 일치" : degrees > 0 ? "\(reference) 오른쪽에 목표" : "\(reference) 왼쪽에 목표"
    }
}


/// HapticLab's inverse distance idea, applied ONCE as player gain (engine reference distance covers the stage).
/// This has no 5m/8m plateau: moving farther continues to reduce the cue.
enum BeaconMath {
    /// Grace keeps calibration/intent only. Audio still requires a sample <= 0.5s old.
    static func retainsHeadCalibration(_ timestamp: Double, now: Double) -> Bool {
        timestamp.isFinite && now.isFinite && now >= timestamp && now - timestamp <= 2
    }
    static func distanceGain(_ meters: Double) -> Double {
        guard meters.isFinite, meters >= 0 else { return 0 }
        return 0.6 * 0.5 / max(0.5, meters)
    }
    static func smoothGain(_ current: Double, target: Double, elapsed: Double) -> Double {
        current + (target - current) * (1 - exp(-max(0, elapsed) / 0.15))
    }
    /// Stage +Y = back (audio -Z). Clockwise from +Y; headphone yaw is counterclockwise.
    static func heading(initial: MapPoint, calibrationYaw: Double, currentYaw: Double) -> MapPoint {
        let clockwise = atan2(initial.x, initial.y) - (currentYaw - calibrationYaw)
        return MapPoint(sin(clockwise), cos(clockwise))
    }
    static func fresh(_ timestamp: Double, now: Double) -> Bool {
        timestamp.isFinite && now.isFinite && now >= timestamp && now - timestamp <= 0.5
    }
    static func mayPlay(sample: Double, head: Double, now: Double,
                        prepared: Bool, headphones: Bool, calibrated: Bool) -> Bool {
        prepared && headphones && calibrated && fresh(sample, now: now) && fresh(head, now: now)
    }
}


/// Route reason alone cannot tell whether headphones were disconnected.
enum BeaconAudioPolicy {
    enum RouteAction { case keep, recover, stop }
    static func routeAction(headphones: Bool, sameDevice: Bool, engineRunning: Bool) -> RouteAction {
        if !headphones { return .stop }
        if !sameDevice || !engineRunning { return .recover }
        return .keep
    }
}
