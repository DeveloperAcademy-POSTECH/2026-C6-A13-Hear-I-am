import Foundation

/// Picks the obstacle warning stage from the nearest obstacle ahead (platforms and stairs excluded).
/// Stages start at 1 m · 0.6 m · 0.35 m (decided 10/17). Only obstacles within ±45° of the body's
/// front count, so passing one beside the route stays quiet (field test 10/17: the beeping hid the
/// arrival ding); inside 0.35 m every direction counts. A stage is kept until the distance is 5 cm
/// past its threshold, and the warned obstacle stays in view up to ±55°, so boundaries do not flicker.
public struct WarningGate: Sendable {
    /// Closest stage first.
    public static let thresholds: [(level: WarningLevel, distance: Double)]=[(.close,WarningLevel.closeDistance),(.near,0.6),(.far,1.0)]
    public static let release=0.05
    public static let fieldOfView=45.0, keptFieldOfView=55.0
    public private(set) var current: ObstacleWarning?
    public init() {}
    public mutating func reset() { current=nil }

    /// nil when no obstacle is within range or the sample is invalid.
    @discardableResult public mutating func update(position: FloorPoint, headingDegrees: Double, obstacles: [StageObstacle]) -> ObstacleWarning? {
        guard position.valid, headingDegrees.isFinite else { current=nil;return nil }
        let candidates=obstacles.filter { !$0.isStep }.map { o -> (StageObstacle,Double,Double) in
            (o,o.distance(to:position),StageHeading.bearing(from:position,to:o.closestPoint(to:position),headingDegrees:headingDegrees))
        }.filter { o,distance,bearing in
            let view=o.id == current?.obstacleID ? Self.keptFieldOfView : Self.fieldOfView
            return distance <= WarningLevel.closeDistance || abs(bearing) <= view
        }
        guard let nearest=candidates.min(by: { $0.1 < $1.1 }),
              let level=Self.level(distance:nearest.1,previous:current?.obstacleID == nearest.0.id ? current?.level : nil) else { current=nil;return nil }
        current=ObstacleWarning(level:level,obstacleID:nearest.0.id,name:nearest.0.name,distance:nearest.1,bearing:nearest.2)
        return current
    }

    static func level(distance: Double, previous: WarningLevel?) -> WarningLevel? {
        for stage in thresholds {
            let kept=previous.map { $0 >= stage.level } ?? false
            if distance <= stage.distance+(kept ? release : 0) { return stage.level }
        }
        return nil
    }
}
