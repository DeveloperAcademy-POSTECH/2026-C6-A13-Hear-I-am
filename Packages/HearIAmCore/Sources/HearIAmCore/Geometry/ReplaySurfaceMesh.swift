import Foundation
import simd

/// Display-only surfaces in stage-local metres (+Y up, -Z toward the back).
/// Never writes inferred floor heights or materials into a saved scan or guidance data.
public struct ReplaySurfaceMesh: Sendable {
    public let vertices: [Point3]
    public let floorIndices: [UInt32]
    public let surfaceIndices: [UInt32]
    public static let textureRepeatMetres = 2.4

    public init(mesh: MeshSnapshot, route: StageRoute) {
        let t=mesh.transform, area=route.area
        vertices=mesh.vertices.map { p in
            let world=Point3(Double(t[0])*p.x+Double(t[4])*p.y+Double(t[8])*p.z+Double(t[12]),
                             Double(t[1])*p.x+Double(t[5])*p.y+Double(t[9])*p.z+Double(t[13]),
                             Double(t[2])*p.x+Double(t[6])*p.y+Double(t[10])*p.z+Double(t[14]))
            let local=area.floor(world)
            return Point3(local.x,world.y-area.floorHeight,-local.y)
        }
        let replacements=route.obstacles.map { object in
            (object:object,height:ObjectPlacement(object).height,
             minX:object.vertices.map(\.x).min()!,maxX:object.vertices.map(\.x).max()!,
             minZ:object.vertices.map(\.y).min()!,maxZ:object.vertices.map(\.y).max()!)
        }
        var floor=[UInt32](), surfaces=[UInt32]()
        for i in stride(from:0,to:mesh.indices.count,by:3) {
            let ids=[mesh.indices[i],mesh.indices[i+1],mesh.indices[i+2]]
            let a=vertices[Int(ids[0])], b=vertices[Int(ids[1])], c=vertices[Int(ids[2])]
            let normal=simd_cross(b.vector-a.vector,c.vector-a.vector)
            let length=simd_length(normal)
            guard length>1e-10 else {continue}
            let points=[a,b,c]
            // Only near-horizontal faces at the registered floor level become wood.
            // Raised platforms, ramps and holes outside the stage keep their observed shape.
            if points.allSatisfy({abs($0.y)<=0.08}) && abs(normal.y)/length>=0.85 {
                floor.append(contentsOf:ids)
                continue
            }
            let covered=replacements.contains { replacement in
                guard points.allSatisfy({p in
                    p.y >= -0.08 && p.y <= replacement.height+0.04 &&
                    p.x >= replacement.minX && p.x <= replacement.maxX &&
                    -p.z >= replacement.minZ && -p.z <= replacement.maxZ
                }) else {return false}
                // Keep boundary-straddling triangles and surrounding walls/furniture.
                let samples=points+[Point3((a.x+b.x+c.x)/3,0,(a.z+b.z+c.z)/3),
                                    Point3((a.x+b.x)/2,0,(a.z+b.z)/2),
                                    Point3((b.x+c.x)/2,0,(b.z+c.z)/2),
                                    Point3((c.x+a.x)/2,0,(c.z+a.z)/2)]
                return samples.allSatisfy {replacement.object.contains(.init($0.x,-$0.z))}
            }
            if !covered {surfaces.append(contentsOf:ids)}
        }
        floorIndices=floor;surfaceIndices=surfaces
    }

    /// Shared UV origin/scale across every AR mesh anchor and the registered stage floor.
    public static func textureCoordinate(_ point: Point3) -> FloorPoint {
        FloorPoint(point.x/textureRepeatMetres,-point.z/textureRepeatMetres)
    }
}
