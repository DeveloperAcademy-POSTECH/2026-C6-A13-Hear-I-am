import ARKit
import SceneKit
import PoC4Core

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
