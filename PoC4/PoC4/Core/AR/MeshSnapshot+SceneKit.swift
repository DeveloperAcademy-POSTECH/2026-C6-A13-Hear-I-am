import SceneKit
import PoC4Core

extension MeshSnapshot {
    func node(saved: Bool, solid: Bool = false) -> SCNNode {
        let verts=vertices.map {SCNVector3(Float($0.x),Float($0.y),Float($0.z))}
        var sources = [SCNGeometrySource(vertices: verts)]
        if solid {
            var normals = Array(repeating: SIMD3<Float>.zero, count: verts.count)
            for offset in stride(from: 0, to: indices.count, by: 3) {
                let a = Int(indices[offset]), b = Int(indices[offset + 1]), c = Int(indices[offset + 2])
                let va = SIMD3<Float>(verts[a].x, verts[a].y, verts[a].z)
                let vb = SIMD3<Float>(verts[b].x, verts[b].y, verts[b].z)
                let vc = SIMD3<Float>(verts[c].x, verts[c].y, verts[c].z)
                let normal = simd_cross(vb - va, vc - va)
                normals[a] += normal; normals[b] += normal; normals[c] += normal
            }
            sources.append(SCNGeometrySource(normals: normals.map {
                let n = simd_length_squared($0) > 0.00000001 ? simd_normalize($0) : SIMD3<Float>(0, 1, 0)
                return SCNVector3(n.x, n.y, n.z)
            }))
        }
        let geometry=SCNGeometry(sources:sources,
            elements:[SCNGeometryElement(indices:indices,primitiveType:.triangles)])
        let material=SCNMaterial(); material.diffuse.contents=saved ? UIColor.systemOrange : UIColor.systemMint
        material.fillMode = solid ? .fill : .lines; material.isDoubleSided=true
        material.lightingModel = solid ? .lambert : .constant
        geometry.materials=[material]
        let node=SCNNode(geometry:geometry)
        node.simdTransform=simd_float4x4(columns:(
            SIMD4(transform[0],transform[1],transform[2],transform[3]),
            SIMD4(transform[4],transform[5],transform[6],transform[7]),
            SIMD4(transform[8],transform[9],transform[10],transform[11]),
            SIMD4(transform[12],transform[13],transform[14],transform[15])))
        return node
    }
}
