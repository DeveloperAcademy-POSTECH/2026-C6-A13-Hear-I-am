import Foundation

struct GuidePerson: Identifiable, Equatable {
    var id: Int
    var point: MapPoint
}

struct GuidanceCue {
    enum State { case paused, guiding, arrived }
    var state: State = .paused
    var distanceMeters: Double = 0
    var turnRadians: Double = 0
}

enum GuidanceMath {
    /// Adapted from StageVision_iphone: touching the boundary is also rejected.
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
        return GuidanceCue(state: .guiding, distanceMeters: distance,
                           turnRadians: atan2(-heading.cross(delta), heading.dot(delta)))
    }
    static func fresh(_ timestamp: Double, now: Double) -> Bool {
        timestamp.isFinite && now.isFinite && now >= timestamp && now - timestamp <= 0.5
    }
}

/// Single-participant identity latch retained across occlusion. Never infer body
/// orientation from their travel direction: that now comes from the worn iPhone.
struct GuidanceState {
    var polygon: [MapPoint] = []
    private(set) var people: [GuidePerson] = []
    private(set) var selectedID: Int?
    private(set) var candidateAvailable = false
    private var candidateID = 1
    private var lastVisual = -Double.infinity
    private(set) var trackingMessage = "P를 선택하세요"
    private(set) var lastObservation = -Double.infinity
    var position: MapPoint? { people.first { $0.id == selectedID }?.point }

    mutating func receive(_ detections: [GuidePerson], time: Double,
                          visualContact: Bool? = nil, detail: String? = nil) {
        trackingMessage = detail ?? "P 위치 수신 중"
        guard time.isFinite, time >= lastObservation else { return }
        if visualContact == true || !detections.isEmpty {
            lastVisual = time; candidateAvailable = true
            if let id = detections.first?.id { candidateID = id }
        }
        guard let person = detections.first, BodyNavigationMath.validPoint(person.point) else {
            if visualContact == true && position != nil && GuidanceMath.fresh(lastObservation, now: time) { return }
            waitForPosition(detail ?? "P 위치 측정 대기 · P 선택 유지"); return
        }
        people = [GuidePerson(id: selectedID ?? person.id, point: person.point)]
        lastObservation = time
    }
    mutating func select(_ id: Int, time: Double) {
        guard candidateAvailable, time >= lastVisual, time - lastVisual <= 1 else { return }
        selectedID = people.first?.id ?? candidateID
    }
    mutating func waitForPosition(_ reason: String) { people = []; trackingMessage = reason }
    mutating func expire(time: Double) {
        if time - lastVisual > 1 { candidateAvailable = false }
        if !GuidanceMath.fresh(lastObservation, now: time) { waitForPosition("P 위치 측정 대기 · P 선택 유지") }
    }
    mutating func clearSelection() { selectedID = nil }
    mutating func invalidate(_ reason: String) {
        candidateAvailable = false; lastVisual = -.infinity
        people = []; selectedID = nil; lastObservation = -.infinity; trackingMessage = reason
    }
}
