import Foundation

/// Picks the obstacle warning stage from the nearest obstacle (platforms and stairs excluded).
/// Stages start at 1 m · 0.6 m · 0.35 m (decided 10/17). A stage is kept until the distance
/// is 5 cm past its threshold, so standing on a boundary does not flip the sound on and off.
public struct WarningGate: Sendable {
    /// Closest stage first.
    public static let thresholds: [(level: WarningLevel, distance: Double)]=[(.close,0.35),(.near,0.6),(.far,1.0)]
    public static let release=0.05
    public private(set) var current: ObstacleWarning?
    public init() {}
    public mutating func reset() { current=nil }

    /// nil when no obstacle is within range or the sample is invalid.
    @discardableResult public mutating func update(position: FloorPoint, headingDegrees: Double, obstacles: [StageObstacle]) -> ObstacleWarning? {
        guard position.valid, headingDegrees.isFinite,
              let nearest=obstacles.filter({ !$0.isStep }).map({ ($0,$0.distance(to:position)) }).min(by: { $0.1 < $1.1 }),
              let level=Self.level(distance:nearest.1,previous:current?.level) else { current=nil;return nil }
        let point=nearest.0.closestPoint(to:position)
        current=ObstacleWarning(level:level,obstacleID:nearest.0.id,name:nearest.0.name,distance:nearest.1,
                                bearing:StageHeading.bearing(from:position,to:point,headingDegrees:headingDegrees))
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
