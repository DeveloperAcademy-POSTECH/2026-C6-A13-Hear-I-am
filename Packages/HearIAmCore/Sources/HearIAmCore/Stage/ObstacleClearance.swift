import Foundation

/// The floor a route keeps clear of: a blocking object's outline grown by the clearance (#38).
/// Route checks always used it, but the screen drew only the outline, so points were refused with
/// no visible reason (10/18). Preparation now draws it and refuses a point before it is placed.
public struct ClearanceHit: Equatable, Sendable {
    public let name: String
    /// How far the point or the segment reaches into the clearance, in metres.
    public let overlap: Double
    /// True when the point itself is inside; false when only the segment from the previous point passes through.
    public let pointInside: Bool

    public var message: String {
        let cm=max(1,Int((overlap*100).rounded()))
        return pointInside ? "십자선이 \(name) 여유 영역 안이에요 · \(cm)cm 겹침"
                           : "직전 점에서 오는 선이 \(name) 여유 영역을 지나요 · \(cm)cm 겹침"
    }
}

extension StageObstacle {
    /// Shortest distance from the segment a→b to this outline; 0 when it touches or enters it.
    public func distance(from a: FloorPoint, to b: FloorPoint) -> Double {
        if contains(a) || contains(b) { return 0 }
        return vertices.indices.map { Self.segmentDistance(a,b,vertices[$0],vertices[($0+1)%vertices.count]) }.min() ?? .infinity
    }
    /// Centres of `cell`-sized squares whose centre is within `clearance` of the outline, inside included.
    /// Drawn as one patch, so the area shows exactly what the route check refuses, to the cell size.
    public func clearanceCells(clearance: Double, cell: Double) -> [FloorPoint] {
        guard cell > 0, clearance >= 0, let minX=vertices.map(\.x).min(), let maxX=vertices.map(\.x).max(),
              let minY=vertices.map(\.y).min(), let maxY=vertices.map(\.y).max() else { return [] }
        let columns=Int(((maxX-minX+2*clearance)/cell).rounded(.up)), rows=Int(((maxY-minY+2*clearance)/cell).rounded(.up))
        return (0..<rows).flatMap { row in (0..<columns).compactMap { column -> FloorPoint? in
            let p=FloorPoint(minX-clearance+(Double(column)+0.5)*cell,minY-clearance+(Double(row)+0.5)*cell)
            return distance(to:p) <= clearance ? p : nil
        }}
    }
}

extension PreparationDraft {
    /// The blocking object that the next route point, or the segment to it from the last point, comes
    /// deepest into the clearance of; nil when the point can be placed.
    public func clearanceHit(adding point: Point3, clearance: Double = Self.obstacleClearance) -> ClearanceHit? {
        guard let area else { return nil }
        let p=area.floor(point), previous=route.last.map(area.floor) ?? p
        return objects.compactMap { try? $0.projected(in:area) }.filter(\.blocksPath).compactMap { o -> ClearanceHit? in
            let line=o.distance(from:previous,to:p)
            guard line <= clearance else { return nil }
            let own=o.distance(to:p)
            return ClearanceHit(name:o.name,overlap:clearance-line,pointInside:own <= clearance)
        }.max { $0.overlap < $1.overlap }
    }
}
