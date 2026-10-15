import ARKit
import SceneKit
import PoC4Core

struct CameraSample {
    let time: Double
    let world: Point3
    let forward: Point3
    let normal: Bool
    let tracking: String
    let mapped: Bool
    let mapping: String
    let anchors: [String: Point3]
    init(_ frame: ARFrame) {
        time=frame.timestamp
        let t=frame.camera.transform
        world=Point3(SIMD3(t.columns.3.x,t.columns.3.y,t.columns.3.z))
        forward=Point3(-SIMD3(t.columns.2.x,t.columns.2.y,t.columns.2.z))
        switch frame.camera.trackingState {
        case .normal: normal=true; tracking="normal"
        case .notAvailable: normal=false; tracking="notAvailable"
        case .limited(let reason): normal=false; tracking="limited: \(reason)"
        }
        mapped=frame.worldMappingStatus == .mapped
        switch frame.worldMappingStatus {
        case .notAvailable: mapping="공간 인식 준비 중"
        case .limited: mapping="공간을 더 비춰주세요"
        case .extending: mapping="스캔 범위를 넓히고 있어요"
        case .mapped: mapping="공간 지도 안정됨"
        @unknown default: mapping="공간 확인 중"
        }
        anchors=Dictionary(frame.anchors.compactMap { anchor -> (String,Point3)? in
            guard let name=anchor.name, name.hasPrefix("PoC4.reference.") else { return nil }
            let p=anchor.transform.columns.3
            return (name,Point3(Double(p.x),Double(p.y),Double(p.z)))
        },uniquingKeysWith: {a,_ in a})
    }
}

/// Each session has its own bridge token; queued callbacks from a previous session are ignored.
final class SessionBridge: NSObject, ARSessionDelegate {
    weak var model: ScanLabModel?
    let token: UUID
    init(model: ScanLabModel, token: UUID) { self.model=model; self.token=token }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let sample=CameraSample(frame)
        Task { @MainActor [weak self] in
            guard let self else { return }; self.model?.receive(sample,token:self.token)
        }
    }
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { meshes(anchors,remove:false) }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { meshes(anchors,remove:false) }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) { meshes(anchors,remove:true) }
    private func meshes(_ anchors: [ARAnchor], remove: Bool) {
        // Copy Metal-backed geometry before leaving the callback.
        let meshAnchors=anchors.compactMap {$0 as? ARMeshAnchor}
        let ids=meshAnchors.map(\.identifier)
        let snapshots=remove ? [] : meshAnchors.compactMap(Self.copy)
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.model?.receiveMeshes(snapshots,removed:remove ? ids : [],token:self.token)
        }
    }
    static func copy(_ anchor: ARMeshAnchor) -> MeshSnapshot? {
        let g=anchor.geometry, source=g.vertices, faces=g.faces
        guard source.format == .float3, faces.indexCountPerPrimitive==3,
              [2,4].contains(faces.bytesPerIndex), source.count<=250_000, faces.count<=500_000 else { return nil }
        let vertices=(0..<source.count).map { i -> Point3 in
            let ptr=source.buffer.contents().advanced(by:source.offset+i*source.stride)
            let x=ptr.load(as:Float.self), y=ptr.advanced(by:4).load(as:Float.self), z=ptr.advanced(by:8).load(as:Float.self)
            return Point3(Double(x),Double(y),Double(z))
        }
        let indices=(0..<faces.count*3).map { i -> UInt32 in
            let ptr=faces.buffer.contents().advanced(by:i*faces.bytesPerIndex)
            return faces.bytesPerIndex==4 ? ptr.load(as:UInt32.self) : UInt32(ptr.load(as:UInt16.self))
        }
        let t=anchor.transform
        let matrix=(0..<4).flatMap { col in (0..<4).map { t[col][$0] } }
        let result=MeshSnapshot(id:anchor.identifier,transform:matrix,vertices:vertices,indices:indices)
        return (try? result.validate()) == nil ? nil : result
    }
    func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor [weak self] in guard let self else { return }; self.model?.interrupt("AR 세션 중단",token:self.token) }
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in guard let self else { return }; self.model?.interrupt("중단 종료 · 저장 공간을 다시 불러오세요",token:self.token) }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        let message=error.localizedDescription
        Task { @MainActor [weak self] in guard let self else { return }; self.model?.interrupt(message,token:self.token) }
    }
}

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
