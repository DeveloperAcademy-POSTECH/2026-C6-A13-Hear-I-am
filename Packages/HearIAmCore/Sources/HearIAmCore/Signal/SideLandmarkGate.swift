import Foundation

public struct SideLandmark: Equatable, Sendable {
    public enum Side: String, Sendable { case right, left }
    public let id: UUID
    public let name: String
    public let side: Side
    public let distance: Double
    public var line: String { (side == .right ? "오른쪽 " : "왼쪽 ")+name }
}

/// Speaks nearby registered objects only while moving forward, with no queued historical encounter.
/// The nearest polygon boundary is used, so a long bookcase is not reduced to its centre point.
public struct SideLandmarkGate: Sendable {
    public static let range=1.5, sideTolerance=20.0, rearmDistance=2.0
    public static let motionWindow=0.8, minimumDisplacement=0.12, minimumForward=0.08
    private struct Sample: Sendable { let time: Double; let position: FloorPoint; let heading: Double }
    private var samples: [Sample]=[]
    private var announced: Set<UUID>=[]
    public private(set) var isMoving=false
    public init() {}
    public mutating func reset() { self=Self() }
    public mutating func suspendMotion() { samples=[];isMoving=false }

    public mutating func observe(time: Double, position: FloorPoint, heading: Double, obstacles: [StageObstacle]) {
        guard time.isFinite, position.valid, heading.isFinite else { suspendMotion();return }
        if let last=samples.last, time <= last.time || time-last.time > 0.5 { suspendMotion() }
        announced=Set(announced.filter { id in
            obstacles.first(where:{$0.id == id}).map {$0.distance(to:position) <= Self.rearmDistance} ?? false
        })
        samples.append(Sample(time:time,position:position,heading:heading))
        samples.removeAll {time-$0.time > Self.motionWindow}
        guard let first=samples.first, let last=samples.last, time-first.time >= 0.25 else { isMoving=false;return }
        let dx=position.x-first.position.x, dy=position.y-first.position.y, radians=heading * .pi/180
        let forward=dx * -sin(radians)+dy * -cos(radians)
        // Require recent forward progress too: a stationary tail must not coast on the old window.
        let recent=samples.last(where:{time-$0.time >= 0.2}) ?? first
        let recentProgress=(position.x-recent.position.x) * -sin(radians)+(position.y-recent.position.y) * -cos(radians)
        isMoving=first.position.distance(to:last.position) >= Self.minimumDisplacement &&
            forward >= Self.minimumForward && recentProgress >= 0.025 &&
            abs(HeadingMath.signedDeltaDegrees(from:first.heading,to:heading)) <= 20
    }
    public func candidates(position: FloorPoint, heading: Double, obstacles: [StageObstacle]) -> [SideLandmark] {
        guard isMoving else { return [] }
        let nearby=Self.nearby(position:position,heading:heading,obstacles:obstacles).filter {!announced.contains($0.id)}
        // At most one nearest object on each side, in a predictable right/left order.
        return [SideLandmark.Side.right,.left].compactMap { side in
            nearby.filter {$0.side == side}.min { a,b in a.distance == b.distance ? a.id.uuidString < b.id.uuidString : a.distance < b.distance }
        }
    }
    public mutating func didSpeak(_ items: [SideLandmark]) { announced.formUnion(items.map(\.id)) }
    public static func stillBeside(_ items: [SideLandmark], position: FloorPoint, heading: Double, obstacles: [StageObstacle]) -> Bool {
        let now=nearby(position:position,heading:heading,obstacles:obstacles)
        return items.allSatisfy { item in now.contains {$0.id == item.id && $0.side == item.side} }
    }
    private static func nearby(position: FloorPoint, heading: Double, obstacles: [StageObstacle]) -> [SideLandmark] {
        guard position.valid, heading.isFinite else { return [] }
        return obstacles.compactMap { obstacle in
            let point=obstacle.closestPoint(to:position), distance=position.distance(to:point)
            guard distance > WarningLevel.closeDistance, distance <= Self.range else { return nil }
            let bearing=StageHeading.bearing(from:position,to:point,headingDegrees:heading)
            guard abs(abs(bearing)-90) <= Self.sideTolerance else { return nil }
            let name=obstacle.name.split(whereSeparator:{$0.isWhitespace}).joined(separator:" ")
            guard !name.isEmpty else { return nil }
            return SideLandmark(id:obstacle.id,name:name,side:bearing > 0 ? .right : .left,distance:distance)
        }
    }
}
