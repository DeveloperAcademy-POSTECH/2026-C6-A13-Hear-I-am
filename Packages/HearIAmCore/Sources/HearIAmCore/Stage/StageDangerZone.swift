import Foundation

/// A visual caution strip measured inward from an audience-relative stage edge.
/// Kept separate from obstacles and guidance stopping thresholds.
public struct StageDangerZone: Codable, Equatable, Sendable, Identifiable {
    public enum Edge: String, Codable, CaseIterable, Sendable, Identifiable {
        case front, back, left, right
        public var id: Self { self }
        public var label: String {
            switch self {
            case .front: return "앞 (객석 쪽)"
            case .back: return "뒤"
            case .left: return "왼쪽"
            case .right: return "오른쪽"
            }
        }
    }
    public enum Distance: Double, Codable, CaseIterable, Sendable, Identifiable {
        case halfMetre = 0.5, oneMetre = 1.0
        public var id: Self { self }
        public var label: String { self == .halfMetre ? "0.5m" : "1m" }
    }
    public let edge: Edge
    public var distance: Distance
    public var id: Edge { edge }
    public init(edge: Edge, distance: Distance) { self.edge=edge; self.distance=distance }

    /// Clockwise floor-plan polygon, clipped to the stage even on a small stage.
    public func vertices(width: Double, depth: Double) -> [FloorPoint] {
        guard width.isFinite, depth.isFinite, width > 0, depth > 0 else { return [] }
        var x0=0.0, x1=width, y0=0.0, y1=depth
        switch edge {
        case .front: y1=min(distance.rawValue,depth)
        case .back: y0=max(0,depth-distance.rawValue)
        case .left: x1=min(distance.rawValue,width)
        case .right: x0=max(0,width-distance.rawValue)
        }
        return [.init(x0,y0),.init(x1,y0),.init(x1,y1),.init(x0,y1)]
    }
    /// Includes the strip boundary; points outside the stage are not in a danger zone.
    public func contains(_ point: FloorPoint, width: Double, depth: Double) -> Bool {
        let polygon=vertices(width:width,depth:depth)
        guard point.valid, polygon.count == 4 else { return false }
        return point.x >= polygon[0].x && point.x <= polygon[2].x &&
               point.y >= polygon[0].y && point.y <= polygon[2].y
    }
    /// Floor distance from `point` to the strip; 0 inside it or on its border.
    public func distance(to point: FloorPoint, width: Double, depth: Double) -> Double {
        let polygon=vertices(width:width,depth:depth)
        guard point.valid, polygon.count == 4 else { return .infinity }
        let dx=max(polygon[0].x-point.x,0,point.x-polygon[2].x), dy=max(polygon[0].y-point.y,0,point.y-polygon[2].y)
        return (dx*dx+dy*dy).squareRoot()
    }
    public static func summary(_ zones: [Self]) -> String {
        let entries=Edge.allCases.compactMap { edge in
            zones.first(where: { $0.edge == edge }).map { "\(edge.label) \($0.distance.label)" }
        }
        return entries.isEmpty ? "위험 구역 없음" : "위험 구역 · " + entries.joined(separator:" · ")
    }
}
