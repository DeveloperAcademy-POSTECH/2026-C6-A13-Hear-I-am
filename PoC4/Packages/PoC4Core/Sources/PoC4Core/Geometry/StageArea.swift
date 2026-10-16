import Foundation

/// Corners are front-left, front-right, back-right, back-left as seen from the audience.
/// Coordinates are AR world metres, with the floor in world X/Z and world Y vertical.
public struct StageArea: Codable, Equatable, Sendable {
    public let corners: [Point3]
    public let frontLeft: Point3
    public let right: FloorPoint
    public let back: FloorPoint
    public let width: Double
    public let depth: Double
    public let floorHeight: Double
    public let maxResidual: Double
    public init(corners: [Point3]) throws {
        guard corners.count == 4, corners.allSatisfy(\.valid) else { throw LabError.invalid("무대 꼭짓점 네 개가 필요합니다.") }
        let a=corners[0], b=corners[1], c=corners[2], d=corners[3]
        let height=corners.map(\.y).reduce(0,+)/4
        guard corners.allSatisfy({abs($0.y-height) <= 0.10}) else { throw LabError.invalid("네 꼭짓점이 같은 바닥 평면에 있지 않습니다.") }
        func unit(_ x: Double,_ y: Double) -> FloorPoint? { let n=hypot(x,y); return n > 0.5 ? FloorPoint(x/n,y/n) : nil }
        guard let u=unit(b.x-a.x,b.z-a.z) else { throw LabError.invalid("앞 변이 너무 짧습니다.") }
        let v=FloorPoint(u.y,-u.x)
        func dot(_ p: Point3,_ axis: FloorPoint) -> Double { (p.x-a.x)*axis.x+(p.z-a.z)*axis.y }
        let frontWidth=dot(b,u), backWidth=dot(c,u)-dot(d,u)
        let leftDepth=dot(d,v), rightDepth=dot(c,v)-dot(b,v)
        let w=(frontWidth+backWidth)/2, h=(leftDepth+rightDepth)/2
        guard w > 0.5, h > 0.5, leftDepth > 0, rightDepth > 0,
              abs(backWidth-frontWidth) <= max(0.12,0.08*w),
              abs(leftDepth-rightDepth) <= max(0.12,0.08*h) else {
            throw LabError.invalid("선택 순서가 교차하거나 직사각형의 대변 길이가 다릅니다.")
        }
        let local=[FloorPoint(0,0),FloorPoint(dot(b,u),dot(b,v)),FloorPoint(dot(c,u),dot(c,v)),FloorPoint(dot(d,u),dot(d,v))]
        let expected=[FloorPoint(0,0),FloorPoint(w,0),FloorPoint(w,h),FloorPoint(0,h)]
        let residual=zip(local,expected).map {$0.distance(to:$1)}.max() ?? .infinity
        guard residual <= max(0.12,0.04*min(w,h)) else { throw LabError.invalid("직각 또는 꼭짓점 오차가 큽니다. 점을 다시 선택하세요.") }
        self.corners=corners; frontLeft=a; right=u; back=v; width=w; depth=h
        floorHeight=height; maxResidual=residual
    }
    public func validate() throws {
        let rebuilt=try StageArea(corners:corners)
        guard frontLeft == rebuilt.frontLeft,
              abs(right.x-rebuilt.right.x)<1e-8, abs(right.y-rebuilt.right.y)<1e-8,
              abs(back.x-rebuilt.back.x)<1e-8, abs(back.y-rebuilt.back.y)<1e-8,
              abs(width-rebuilt.width)<1e-8, abs(depth-rebuilt.depth)<1e-8,
              abs(floorHeight-rebuilt.floorHeight)<1e-8,
              abs(maxResidual-rebuilt.maxResidual)<1e-8 else {
            throw LabError.invalid("저장된 무대 E가 원본 꼭짓점과 일치하지 않습니다.")
        }
    }
    public func floor(_ p: Point3) -> FloorPoint {
        FloorPoint((p.x-frontLeft.x)*right.x+(p.z-frontLeft.z)*right.y,
                   (p.x-frontLeft.x)*back.x+(p.z-frontLeft.z)*back.y)
    }
    public func world(_ p: FloorPoint) -> Point3 {
        Point3(frontLeft.x+p.x*right.x+p.y*back.x,floorHeight,
               frontLeft.z+p.x*right.y+p.y*back.y)
    }
    public func contains(_ p: FloorPoint, margin: Double = 0) -> Bool {
        margin >= 0 && p.valid && p.x >= margin && p.y >= margin &&
        p.x <= width-margin && p.y <= depth-margin
    }
    /// Outward from the front edge toward the audience, in AR world space.
    public var stageFront: FloorPoint { FloorPoint(-back.x,-back.y) }
}
