import Foundation

/// User-confirmed footprint in the saved AR world. Only faces wholly inside the footprint are kept.
/// This deliberately leaves unobserved edges open instead of inventing geometry or filling holes.
public struct ObjectScanRegion: Sendable, Equatable {
    public let outline: [Point3]
    public let floorHeight: Double
    private let polygon: StageObstacle
    public init(outline: [Point3], floorHeight: Double) throws {
        guard floorHeight.isFinite, outline.allSatisfy({$0.valid && abs($0.y-floorHeight)<=0.10}) else {
            throw LabError.invalid("추가 스캔 둘레를 같은 바닥에 지정해주세요.")
        }
        self.outline=outline;self.floorHeight=floorHeight
        polygon=try StageObstacle(name:"추가 스캔",kind:.other,vertices:outline.map {FloorPoint($0.x,$0.z)})
    }
    public func overlaps(_ other: Self) -> Bool {
        polygon.vertices.indices.contains { i in
            other.polygon.overlaps(polygon.vertices[i],polygon.vertices[(i+1)%polygon.vertices.count],clearance:0)
        } || polygon.contains(other.polygon.vertices[0]) || other.polygon.contains(polygon.vertices[0])
    }
    public func contains(_ point: Point3) -> Bool {
        point.y > floorHeight+0.035 && point.y <= floorHeight+ObjectHeight.ceiling && polygon.contains(FloorPoint(point.x,point.z))
    }
    public func selecting(_ mesh: MeshSnapshot, inside: Bool) -> MeshSnapshot? {
        Self.filter(mesh) { a,b,c in
            let vertices=[a,b,c]
            let samples=vertices+[Point3((a.x+b.x)/2,0,(a.z+b.z)/2),Point3((b.x+c.x)/2,0,(b.z+c.z)/2),Point3((c.x+a.x)/2,0,(c.z+a.z)/2),Point3((a.x+b.x+c.x)/3,0,(a.z+b.z+c.z)/3)]
            // Keep vertical sides touching the floor, but do not duplicate the floor itself.
            let enclosed=vertices.allSatisfy {$0.y>=floorHeight-0.03 && $0.y<=floorHeight+ObjectHeight.ceiling}
                && vertices.contains {$0.y>floorHeight+0.035}
                && samples.allSatisfy {polygon.contains(FloorPoint($0.x,$0.z))}
            return inside ? enclosed : !enclosed
        }
    }
    public static func compose(base: [MeshSnapshot], regions: [ObjectScanRegion], additions: [MeshSnapshot]) -> [MeshSnapshot] {
        base.compactMap {mesh in
            regions.reduce(Optional(mesh)) {part,region in part.flatMap {region.selecting($0,inside:false)}}
        } + additions
    }
    private static func filter(_ mesh: MeshSnapshot, include: (Point3,Point3,Point3) -> Bool) -> MeshSnapshot? {
        guard (try? mesh.validate()) != nil else {return nil}
        let t=mesh.transform
        let world=mesh.vertices.map {p in Point3(
            Double(t[0])*p.x+Double(t[4])*p.y+Double(t[8])*p.z+Double(t[12]),
            Double(t[1])*p.x+Double(t[5])*p.y+Double(t[9])*p.z+Double(t[13]),
            Double(t[2])*p.x+Double(t[6])*p.y+Double(t[10])*p.z+Double(t[14]))}
        var vertices: [Point3]=[],indices: [UInt32]=[],remap: [UInt32:UInt32]=[:]
        for i in stride(from:0,to:mesh.indices.count,by:3) {
            let face=Array(mesh.indices[i..<i+3])
            guard include(world[Int(face[0])],world[Int(face[1])],world[Int(face[2])]) else {continue}
            for old in face {
                if let index=remap[old] {indices.append(index)}
                else {let index=UInt32(vertices.count);remap[old]=index;vertices.append(world[Int(old)]);indices.append(index)}
            }
        }
        guard !indices.isEmpty else {return nil}
        return MeshSnapshot(id:mesh.id,transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:vertices,indices:indices)
    }
}
