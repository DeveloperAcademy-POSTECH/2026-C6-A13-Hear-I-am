import Foundation

/// Announces once when the straight way to the target enters a platform or stairs within 1 m
/// (step up), or leaves the one the performer stands on within 1 m (step down), as decided 10/17.
/// When the far edge on that way is also within 1 m of the near edge, the step down would be due the
/// moment the performer steps up, so both are said at once (field test 10/17: a small platform gave
/// "step down" only 0.08 m before its edge). An announced edge is armed again after moving 1.5 m away.
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
            let edge: StepCue.Kind=inside ? .down : .up
            let crossings=step.crossings(from:position,to:target)
            // `over` already covered both edges of this platform.
            guard announced[step.id] != edge, announced[step.id] != .over,
                  let t=crossings.first, t*length <= Self.notice else { continue }
            // Width on the way between entering and leaving; nil when the target lies on the platform.
            // A way through a corner reports that corner twice, so the leaving edge must be 1 cm further.
            let across=edge == .up ? crossings.first(where:{ ($0-t)*length > 0.01 }).map { ($0-t)*length } : nil
            let kind: StepCue.Kind=(across ?? .infinity) <= Self.notice ? .over : edge
            announced[step.id]=kind
            return StepCue(kind:kind,stairs:step.kind == .stairs,obstacleID:step.id,name:step.name,distance:t*length,across:across,height:step.height)
        }
        return nil
    }
}
