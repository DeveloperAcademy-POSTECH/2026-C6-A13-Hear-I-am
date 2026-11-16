import ARKit
import SceneKit
import HearIAmCore

/// Each session has its own bridge token; queued callbacks from a previous session are ignored.
final class SessionBridge: NSObject, ARSessionDelegate {
    weak var controller: ARSessionController?
    let token: UUID
    let surfaceColors=ScanSurfaceColorCapture()
    /// The newest camera sample the main actor has not taken yet. While one is waiting, later frames replace it
    /// instead of queueing another main-actor task, so a busy main thread catches up on the newest frame (#198).
    private let sampleLock=NSLock()
    private var pendingSample: CameraSample?
    /// Delegate-queue only: when each mesh anchor was last copied. ARKit refines anchors many times a second;
    /// copying every refinement held up the camera queue while ARKit dropped frames (11/14 POS, #198).
    private var copiedAt: [UUID:Double]=[:]
    private var lastFrameTime: Double?
    static let meshCopyInterval=1.0
    init(controller: ARSessionController, token: UUID) { self.controller=controller; self.token=token }
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let sample=CameraSample(frame)
        // Frames ARKit itself never delivered, as opposed to frames the main thread took late (`sample_late`).
        if let lastFrameTime, sample.time-lastFrameTime>0.2 { report("frame_gap",milliseconds:(sample.time-lastFrameTime)*1000) }
        lastFrameTime=sample.time
        surfaceColors.capture(frame,session:session)
        sampleLock.lock(); let idle=pendingSample == nil; pendingSample=sample; sampleLock.unlock()
        guard idle else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let next=self.takePendingSample() { self.controller?.receive(next,token:self.token) }
        }
    }
    private func takePendingSample() -> CameraSample? {
        sampleLock.lock(); defer { sampleLock.unlock() }
        let next=pendingSample; pendingSample=nil; return next
    }
    private func report(_ name: String, milliseconds: Double, detail: String = "") {
        Task { @MainActor [weak self] in
            guard let self, let controller=self.controller, controller.token==self.token else { return }
            controller.event(name,detail:"ms=\(Int(milliseconds))"+detail)
        }
    }
    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) { if Self.building(session) {meshes(anchors,remove:false,force:true)} }
    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) { if Self.building(session) {meshes(anchors,remove:false,force:false)} }
    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) { if Self.building(session) {meshes(anchors,remove:true,force:true)} }
    /// Mesh callbacks are copied only while the mesh is being built. After the scan step (#198) the copy would
    /// hold up the camera queue for nothing, and anchors ARKit drops must not empty the scanned mesh.
    private static func building(_ session: ARSession) -> Bool {
        (session.configuration as? ARWorldTrackingConfiguration)?.sceneReconstruction != []
    }
    private func meshes(_ anchors: [ARAnchor], remove: Bool, force: Bool) {
        // Copy Metal-backed geometry before leaving the callback.
        let started=ProcessInfo.processInfo.systemUptime
        var meshAnchors=anchors.compactMap {$0 as? ARMeshAnchor}
        if remove { meshAnchors.forEach {copiedAt[$0.identifier]=nil} }
        else if !force { meshAnchors=meshAnchors.filter {started-(copiedAt[$0.identifier] ?? -.infinity) >= Self.meshCopyInterval} }
        guard !meshAnchors.isEmpty else { return }
        let ids=meshAnchors.map(\.identifier)
        let snapshots=remove ? [] : meshAnchors.compactMap(Self.copy)
        if !remove { ids.forEach {copiedAt[$0]=started} }
        let milliseconds=(ProcessInfo.processInfo.systemUptime-started)*1000
        if milliseconds>30 {
            report("mesh_copy_slow",milliseconds:milliseconds,detail:" parts=\(snapshots.count) vertices=\(snapshots.reduce(0){$0+$1.vertices.count})")
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.controller?.receiveMeshes(snapshots,removed:remove ? ids : [],token:self.token)
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
        Task { @MainActor [weak self] in guard let self else { return }; self.controller?.interrupt(L("AR 세션 중단"),token:self.token) }
    }
    func sessionInterruptionEnded(_ session: ARSession) {
        Task { @MainActor [weak self] in guard let self else { return }; self.controller?.interrupt(L("중단 종료 · 저장 공간을 다시 불러오세요"),token:self.token) }
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        let message=error.localizedDescription
        Task { @MainActor [weak self] in guard let self else { return }; self.controller?.interrupt(message,token:self.token) }
    }
}
