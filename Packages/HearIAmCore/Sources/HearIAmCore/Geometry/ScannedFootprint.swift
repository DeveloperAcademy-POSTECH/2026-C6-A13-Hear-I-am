import Foundation

/// Saved LiDAR surfaces projected into the route's stage-floor coordinates, including outside the stage.
/// A footprint is evidence of a scan, not a walkability map: saved meshes have no floor classification.
public struct ScannedFootprint: Sendable {
    private struct Cell: Hashable, Sendable { let x: Int; let y: Int }
    private struct Triangle: Sendable {
        let a: FloorPoint, b: FloorPoint, c: FloorPoint
        var winding: Double { cross(a,b,c) > 0 ? 1 : -1 }
        func interval(from start: FloorPoint, to end: FloorPoint) -> ClosedRange<Double>? {
            var lo=0.0, hi=1.0
            for (p,q) in [(a,b),(b,c),(c,a)] {
                let f0=cross(p,q,start)*winding, f1=cross(p,q,end)*winding, delta=f1-f0
                if abs(delta) < 1e-12 {
                    if f0 < -1e-8 { return nil }
                } else {
                    let t=(-1e-8-f0)/delta
                    if delta > 0 { lo=max(lo,t) } else { hi=min(hi,t) }
                    if lo > hi { return nil }
                }
            }
            return lo...hi
        }
        func distance(to p: FloorPoint) -> Double {
            if interval(from:p,to:p) != nil { return 0 }
            return min(p.distance(toSegmentFrom:a,to:b),p.distance(toSegmentFrom:b,to:c),p.distance(toSegmentFrom:c,to:a))
        }
    }
    /// Allows only small seams between adjacent AR mesh anchors, not entire unscanned gaps.
    public static let seamTolerance = 0.05
    private static let cellSize = 1.0
    private let triangles: [Triangle]
    private let cells: [Cell:[Int]]

    public init(meshes: [MeshSnapshot], area: StageArea) throws {
        try area.validate()
        var triangles=[Triangle](), cells=[Cell:[Int]]()
        for mesh in meshes {
            try mesh.validate()
            let m=mesh.transform.map(Double.init)
            let world=mesh.vertices.map { p in
                Point3(m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12],
                       m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13],
                       m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14])
            }
            let projected=world.map(area.floor)
            guard world.allSatisfy(\.valid), projected.allSatisfy(Self.validCoordinate) else {
                throw LabError.invalid("저장된 스캔 범위의 좌표가 올바르지 않습니다.")
            }
            for i in stride(from:0,to:mesh.indices.count,by:3) {
                let indices=(0..<3).map {Int(mesh.indices[i+$0])}
                let a=world[indices[0]], b=world[indices[1]], c=world[indices[2]]
                let ux=b.x-a.x, uy=b.y-a.y, uz=b.z-a.z
                let vx=c.x-a.x, vy=c.y-a.y, vz=c.z-a.z
                let nx=uy*vz-uz*vy, ny=uz*vx-ux*vz, nz=ux*vy-uy*vx
                // Vertical walls alone cannot establish coverage of the space between them.
                guard abs(ny) > 1e-8, abs(ny) >= sqrt(nx*nx+ny*ny+nz*nz)*0.5 else { continue }
                let t=Triangle(a:projected[indices[0]],b:projected[indices[1]],c:projected[indices[2]])
                let first=Self.cell(.init(min(t.a.x,t.b.x,t.c.x),min(t.a.y,t.b.y,t.c.y)))
                let last=Self.cell(.init(max(t.a.x,t.b.x,t.c.x),max(t.a.y,t.b.y,t.c.y)))
                guard (last.x-first.x+1)*(last.y-first.y+1) <= 100_000 else { throw LabError.invalid("저장된 스캔 삼각형이 너무 큽니다.") }
                let index=triangles.count;triangles.append(t)
                for x in first.x...last.x { for y in first.y...last.y { cells[Cell(x:x,y:y),default:[]].append(index) } }
            }
        }
        guard !triangles.isEmpty else { throw LabError.invalid("저장된 스캔에서 접근 범위를 확인할 수 없어요. 무대 주변 바닥까지 다시 스캔해주세요.") }
        self.triangles=triangles;self.cells=cells
    }
    public func contains(_ point: FloorPoint) -> Bool {
        guard Self.validCoordinate(point) else { return false }
        return candidates(near:point).contains { triangles[$0].distance(to:point) <= Self.seamTolerance }
    }
    public func covers(from start: FloorPoint, to end: FloorPoint) -> Bool {
        guard contains(start), contains(end) else { return false }
        let length=start.distance(to:end)
        guard length > 1e-9 else { return true }
        // Half-cell sampling with neighbouring buckets visits every cell the segment can intersect.
        let count=Int(ceil(length/(Self.cellSize/2)))
        var candidates=Set<Int>()
        for i in 0...count {
            let f=Double(i)/Double(count)
            candidates.formUnion(self.candidates(near:.init(start.x+(end.x-start.x)*f,start.y+(end.y-start.y)*f)))
        }
        let intervals=candidates.compactMap {triangles[$0].interval(from:start,to:end)}.sorted {$0.lowerBound < $1.lowerBound}
        let tolerance=Self.seamTolerance/length
        var reached=0.0
        for interval in intervals {
            if interval.lowerBound > reached+tolerance { return false }
            reached=max(reached,interval.upperBound)
            if reached >= 1-tolerance { return true }
        }
        return false
    }
    private func candidates(near point: FloorPoint) -> Set<Int> {
        let cell=Self.cell(point)
        var result=Set<Int>()
        for x in (cell.x-1)...(cell.x+1) { for y in (cell.y-1)...(cell.y+1) { result.formUnion(cells[Cell(x:x,y:y)] ?? []) } }
        return result
    }
    private static func validCoordinate(_ p: FloorPoint) -> Bool { p.valid && abs(p.x) < 10_000 && abs(p.y) < 10_000 }
    private static func cell(_ p: FloorPoint) -> Cell { Cell(x:Int(floor(p.x/cellSize)),y:Int(floor(p.y/cellSize))) }
}

private func cross(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint) -> Double {
    (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
}
