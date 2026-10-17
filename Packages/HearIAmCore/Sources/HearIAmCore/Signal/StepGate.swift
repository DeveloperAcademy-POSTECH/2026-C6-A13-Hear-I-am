import Foundation

/// Announces once when the straight way to the target enters a platform or stairs within 1 m
/// (step up), or leaves the one the performer stands on within 1 m (step down), as decided 10/17.
/// An announced edge is armed again after moving 1.5 m away from that platform.
public struct StepGate: Sendable {
    public static let notice=1.0, rearm=1.5
    private var announced: [UUID: StepCue.Kind]=[:]
    public init() {}
    public mutating func reset() { announced=[:] }

    public mutating func update(position: FloorPoint, target: FloorPoint, obstacles: [StageObstacle]) -> StepCue? {
        guard position.valid, target.valid else { return nil }
        let length=position.distance(to:target)
        for step in obstacles where step.isStep {
            let inside=step.contains(position)
            if !inside && step.distance(to:position) > Self.rearm { announced[step.id]=nil;continue }
            let kind: StepCue.Kind=inside ? .down : .up
            guard announced[step.id] != kind, let t=step.crossings(from:position,to:target).first, t*length <= Self.notice else { continue }
            announced[step.id]=kind
            return StepCue(kind:kind,stairs:step.kind == .stairs,obstacleID:step.id,name:step.name,distance:t*length)
        }
        return nil
    }
}
