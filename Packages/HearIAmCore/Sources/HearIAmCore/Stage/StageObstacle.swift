import Foundation

// `platform` is the legacy persisted identifier for the chair option; keep it for saved-data compatibility.
public enum ObstacleKind: String, Codable, CaseIterable, Sendable { case stairs, box, other, platform }
public enum PassagePolicy: String, Codable, Sendable { case prohibited, passable }
public struct StageObstacle: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ObstacleKind
    public var passage: PassagePolicy
    public var vertices: [FloorPoint]
    /// Top above the stage floor in metres, measured from the scan mesh; nil for older saves or when not measured.
    public var height: Double?
    /// nil preserves unrestricted access in older saves; an empty list closes every edge.
    public var entryEdges: [Int]?
    public var exitEdges: [Int]?
    /// Single edge index whose outward normal is the direction to face after arriving on a chair or stairs (#76).
    public var facingEdge: Int?
    public var appearance: ObjectAppearance?
    public init(id: UUID = UUID(), name: String, kind: ObstacleKind, passage: PassagePolicy = .prohibited, vertices: [FloorPoint], height: Double? = nil, entryEdges: [Int]? = nil, exitEdges: [Int]? = nil, facingEdge: Int? = nil, appearance: ObjectAppearance? = nil) throws {
        self.id=id; self.name=name; self.kind=kind; self.passage=passage; self.vertices=vertices; self.height=height
        self.entryEdges=entryEdges; self.exitEdges=exitEdges; self.facingEdge=facingEdge; self.appearance=appearance
        try validate()
    }
    public func validate() throws {
        try appearance?.validate()
        if let facingEdge, !vertices.indices.contains(facingEdge) {
            throw LabError.invalid("바라볼 방향의 변 번호가 올바르지 않습니다.")
        }
        for edges in [entryEdges,exitEdges].compactMap({$0}) {
            guard Set(edges).count == edges.count, edges.allSatisfy({vertices.indices.contains($0)}) else {
                throw LabError.invalid("승하강 변 번호가 올바르지 않습니다.")
            }
        }
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              (3...8).contains(vertices.count), vertices.allSatisfy(\.valid),
              abs(Self.area(vertices)) >= 0.0005 else { throw LabError.invalid("기물 영역에 유효한 꼭짓점 3~8개가 필요합니다.") }
        for i in vertices.indices {
            for j in vertices.indices where j > i+1 && !(i == 0 && j == vertices.count-1) {
                if Self.intersects(vertices[i],vertices[(i+1)%vertices.count],vertices[j],vertices[(j+1)%vertices.count]) {
                    throw LabError.invalid("기물 영역이 자기 교차합니다.")
                }
            }
        }
    }
    private static func area(_ p: [FloorPoint]) -> Double {
        p.indices.reduce(0) { $0+p[$1].x*p[($1+1)%p.count].y-p[($1+1)%p.count].x*p[$1].y }/2
    }
    private static func cross(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint) -> Double {
        (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
    }
    static func intersects(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint,_ d: FloorPoint) -> Bool {
        let e=1e-9
        let ab1=cross(a,b,c), ab2=cross(a,b,d), cd1=cross(c,d,a), cd2=cross(c,d,b)
        if ab1*ab2 < -e && cd1*cd2 < -e { return true }
        func on(_ p: FloorPoint,_ q: FloorPoint,_ r: FloorPoint) -> Bool {
            abs(cross(p,q,r)) <= e && r.x >= min(p.x,q.x)-e && r.x <= max(p.x,q.x)+e &&
            r.y >= min(p.y,q.y)-e && r.y <= max(p.y,q.y)+e
        }
        return on(a,b,c) || on(a,b,d) || on(c,d,a) || on(c,d,b)
    }
    public func contains(_ p: FloorPoint) -> Bool {
        var inside=false
        for i in vertices.indices {
            let a=vertices[i], b=vertices[(i+1)%vertices.count]
            if Self.distancePointSegment(p,a,b) < 1e-8 { return true }
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
        }
        return inside
    }
    private static func distancePointSegment(_ p: FloorPoint,_ a: FloorPoint,_ b: FloorPoint) -> Double {
        let dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
        let t=n > 0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/n)) : 0
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
    static func segmentDistance(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint,_ d: FloorPoint) -> Double {
        if intersects(a,b,c,d) { return 0 }
        return min(distancePointSegment(a,c,d),distancePointSegment(b,c,d),
                   distancePointSegment(c,a,b),distancePointSegment(d,a,b))
    }
    /// Platforms and stairs can be approached and left from any side (#76); `facingEdge` defines the
    /// direction to face after arriving on the step. Non-step obstacles still block travel.
    public func permitsEntry(_ edge: Int) -> Bool { true }
    public func permitsExit(_ edge: Int) -> Bool { true }
    /// Body-relative bearing in [-180, 180] toward the outward normal of `facingEdge`, or nil when none is set (#76).
    public func facingBearing(headingDegrees: Double) -> Double? {
        guard isStep, let edge=facingEdge, vertices.indices.contains(edge), headingDegrees.isFinite else { return nil }
        let a=vertices[edge], b=vertices[(edge+1)%vertices.count]
        let dx=b.x-a.x, dy=b.y-a.y
        guard hypot(dx,dy) > 1e-9 else { return nil }
        let winding=Self.area(vertices) >= 0 ? 1.0 : -1.0
        let outward=FloorPoint(winding*dy,-winding*dx)
        return StageHeading.bearing(from:.init(0,0),to:outward,headingDegrees:headingDegrees)
    }
    public func blocksTravel(from a: FloorPoint, to b: FloorPoint, clearance: Double) -> Bool {
        blocksPath && overlaps(a,b,clearance:clearance)
    }
    /// Nearest outline point of an object to keep away from. Chairs and stairs are walked onto, so they
    /// never give one: on 10/26 their closed sides beeped for 34.9 s of a 51 s run past a chair (#72).
    public func blockingPoint(from p: FloorPoint) -> FloorPoint? { blocksPath ? closestPoint(to:p) : nil }
    public var isStep: Bool { kind == .platform || kind == .stairs }
    /// Routes must keep clear of this outline. Platforms and stairs never block, even when an older
    /// save still marks them prohibited, because the performer walks onto them (decided 10/17).
    public var blocksPath: Bool { passage == .prohibited && !isStep }
    /// Distance to the polygon boundary, including for points inside the polygon.
    public func boundaryDistance(to p: FloorPoint) -> Double {
        vertices.indices.map { Self.distancePointSegment(p,vertices[$0],vertices[($0+1)%vertices.count]) }.min() ?? .infinity
    }
    /// Shortest distance from `p` to the outline; 0 when inside.
    public func distance(to p: FloorPoint) -> Double { contains(p) ? 0 : p.distance(to:closestPoint(to:p)) }
    /// Closest point on the outline, or `p` itself when inside.
    public func closestPoint(to p: FloorPoint) -> FloorPoint {
        if contains(p) { return p }
        return vertices.indices.map { i -> FloorPoint in
            let a=vertices[i], b=vertices[(i+1)%vertices.count], dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
            let t=n > 0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/n)) : 0
            return FloorPoint(a.x+t*dx,a.y+t*dy)
        }.min { p.distance(to:$0) < p.distance(to:$1) } ?? p
    }
    /// Fractions t ∈ [0, 1] along a→b where the segment crosses the outline, ascending.
    public func crossings(from a: FloorPoint, to b: FloorPoint) -> [Double] {
        let rx=b.x-a.x, ry=b.y-a.y
        return vertices.indices.compactMap { i -> Double? in
            let c=vertices[i], d=vertices[(i+1)%vertices.count], sx=d.x-c.x, sy=d.y-c.y
            let denominator=rx*sy-ry*sx
            guard abs(denominator) > 1e-12 else { return nil }
            let t=((c.x-a.x)*sy-(c.y-a.y)*sx)/denominator, u=((c.x-a.x)*ry-(c.y-a.y)*rx)/denominator
            return (0...1).contains(t) && (0...1).contains(u) ? t : nil
        }.sorted()
    }
    public func overlaps(_ a: FloorPoint,_ b: FloorPoint, clearance: Double) -> Bool {
        distance(from:a,to:b) <= clearance+1e-9
    }
}
