import Foundation

public enum RouteNarrationCue: Equatable, Sendable {
    case distance(DistanceAnnouncement)
    case landmarks([SideLandmark])
    public var line: String {
        switch self {
        case .distance(let distance): return distance.line
        case .landmarks(let items): return items.map(\.line).joined(separator:", ")
        }
    }
    public var detail: String {
        switch self {
        case .distance(let distance): return String(format:"remaining=%.2fm spoken=%@",distance.meters,distance.line)
        case .landmarks(let items): return items.map {
            String(format:"id=%@ side=%@ distance=%.2fm name=%@",$0.id.uuidString,$0.side.rawValue,$0.distance,$0.name)
        }.joined(separator:" | ")
        }
    }
    public var logName: String {
        switch self { case .distance: return "distance";case .landmarks: return "side_landmark" }
    }
}

/// Low-priority narration. Caller supplies current alignment/audio eligibility on every fresh pose.
/// There is no speech queue: distance and landmark candidates are recalculated at playback time.
public struct RouteNarrationGate: Sendable {
    public static let minimumInterval=1.5
    private var targetIndex: Int?
    private var distance=RemainingDistanceGate()
    private var landmarks=SideLandmarkGate()
    private var lastSpokenAt: Double?
    public init() {}
    public mutating func reset() { self=Self() }
    public mutating func suspendMotion() { landmarks.suspendMotion() }
    public mutating func observe(targetIndex: Int, time: Double, position: FloorPoint, heading: Double, obstacles: [StageObstacle]) {
        if self.targetIndex != targetIndex { self.targetIndex=targetIndex;distance.reset() }
        landmarks.observe(time:time,position:position,heading:heading,obstacles:obstacles)
    }
    public func candidate(time: Double, meters: Double, eligible: Bool, position: FloorPoint, heading: Double, obstacles: [StageObstacle]) -> RouteNarrationCue? {
        guard eligible, time.isFinite, lastSpokenAt.map({time-$0 >= Self.minimumInterval}) ?? true else { return nil }
        let next=distance.candidate(meters:meters)
        // The first distance follows alignment. Afterwards an ephemeral side landmark gets its turn
        // before routine distance updates; the next distance is always recomputed, not queued.
        if !distance.hasAnnounced, let next { return .distance(next) }
        let beside=landmarks.candidates(position:position,heading:heading,obstacles:obstacles)
        if !beside.isEmpty { return .landmarks(beside) }
        return next.map { .distance($0) }
    }
    public mutating func didSpeak(_ cue: RouteNarrationCue, time: Double) {
        lastSpokenAt=time
        switch cue { case .distance(let next): distance.didSpeak(next);case .landmarks(let items): landmarks.didSpeak(items) }
    }
}
