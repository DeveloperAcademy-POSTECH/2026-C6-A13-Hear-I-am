import Foundation

public struct FloorPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x=x; self.y=y }
    public var valid: Bool { x.isFinite && y.isFinite && abs(x) <= 500 && abs(y) <= 500 }
    public func distance(to p: FloorPoint) -> Double { hypot(x-p.x,y-p.y) }
}

extension FloorPoint {
    public func distance(toSegmentFrom a: FloorPoint, to b: FloorPoint) -> Double {
        let dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
        let t=n > 0 ? max(0,min(1,((x-a.x)*dx+(y-a.y)*dy)/n)) : 0
        return hypot(x-a.x-t*dx,y-a.y-t*dy)
    }
}
