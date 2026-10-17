import ARKit
import HearIAmCore

/// Camera frames and mesh anchors arriving from SessionBridge.
extension ARSessionController {
    func receive(_ sample: CameraSample, token incoming: UUID) {
        guard incoming==token, active, mode == .scanning || mode == .restoring else { return }
        let wasVerified=gate.verified
        guard gate.observe(time:sample.time,normal:sample.normal && sample.world.valid && sample.forward.valid,anchorsPresent:referenceAnchorsPresent(sample)) else { return }
        latest=sample
        if tracking != sample.tracking { event("tracking",detail:sample.tracking) }
        if wasVerified && !gate.verified { invalidateWear("추적 제한 · C 재검증 필요") }
        if sample.time-lastUI >= 0.05 {
            lastUI=sample.time; tracking=sample.tracking; mapping=sample.mapping
            ready=gate.isReady(now:now); canVerify=gate.canVerify(now:now)
            canSave=mode == .scanning && !busy && sample.normal && sample.mapped &&
                referenceAnchorsPresent(sample) && !meshes.isEmpty && stage != nil && routeIsValid
            if let stage, ready {
                position=stagePosition(sample.world)
                heading=stage.heading(cameraForward:sample.forward)
                guidanceHorizontalRatio=StageFrame.horizontalForwardRatio(sample.forward)
            } else { position=nil; heading=nil; guidanceHorizontalRatio=nil }
            guidancePoseTime=sample.time
            if mode == .restoring {
                let candidate=sample.normal && referenceAnchorsPresent(sample)
                renderer.meshLayer.isHidden = !candidate || !showMesh; renderer.referenceLayer.isHidden = !candidate
                if !ready { status=canVerify ? "복원 후보 확보 · 실제 C를 다시 선택해 검증하세요" : "공간 복원 중 · 기준 앵커와 안정된 추적을 기다립니다" }
            }
        }
        if sample.time-lastPoseLog>=0.05 {
            lastPoseLog=sample.time
            let raw=sample.world.valid ? stagePosition(sample.world) : nil
            event("pose",detail:"observing",position:raw,
                  heading:stage?.heading(cameraForward:sample.forward),time:sample.time)
        }
    }
    func receiveMeshes(_ parts: [MeshSnapshot], removed: [UUID], token incoming: UUID) {
        guard incoming==token, mode == .scanning, active, !busy else { return }
        for id in removed { meshes[id]=nil }
        for part in parts { meshes[part.id]=part }
        renderer.updateMeshes(parts,removed:removed)
        updateCounts()
        if vertexCount>800_000 { interrupt("메시가 너무 큽니다. 더 작은 영역으로 새 스캔을 시작하세요.",token:token) }
    }
    func updateCounts() { meshCount=meshes.count; vertexCount=meshes.values.reduce(0){$0+$1.vertices.count} }
    var routeIsValid: Bool { preparedDraft?.errors.isEmpty ?? false }
    func stagePosition(_ world: Point3) -> Point3? {
        if let area {
            let floor=area.floor(world)
            return Point3(floor.x,floor.y,world.y-area.floorHeight)
        }
        return stage?.position(world)
    }
    func referenceAnchorsPresent(_ sample: CameraSample) -> Bool {
        guard let origin, let front, let checkpoint else { return false }
        return [(".origin",origin),(".front",front),(".check",checkpoint)].allSatisfy { name, expected in
            sample.anchors[referencePrefix+name].map {$0.distance(to:expected)<0.05} ?? false
        }
    }
}
