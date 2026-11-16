import ARKit
import HearIAmCore

/// Camera frames and mesh anchors arriving from SessionBridge.
extension ARSessionController {
    func receive(_ sample: CameraSample, token incoming: UUID) {
        guard incoming==token, active, mode == .scanning || mode == .restoring else { return }
        let wasVerified=gate.verified
        let previousStability=gate.normalSince
        let anchorsPresent=referenceAnchorsPresent(sample)
        guard gate.observe(time:sample.time,normal:sample.normal && sample.world.valid && sample.forward.valid,anchorsPresent:wasVerified || alignment != nil || anchorsPresent) else { return }
        latest=sample
        // The main thread took this frame late (rendering or SwiftUI work), unlike an ARKit `frame_gap` (#198).
        if now-sample.time>0.25 { event("sample_late",detail:"ms=\(Int((now-sample.time)*1000))") }
        if alignment == nil && !measuredCheckpoints.isEmpty && previousStability != gate.normalSince {
            clearAlignment()
            status=L("추적이 변경됐어요. 확인점 1번부터 다시 확인해주세요.")
        }
        if tracking != sample.tracking { event("tracking",detail:sample.tracking) }
        if wasVerified && !gate.verified { invalidateWear(L("추적 제한 · 위치 재확인 중")) }
        if alignment != nil && !gate.verified && gate.canVerify(now:sample.time) {
            _=gate.verify(error:alignment?.residual ?? 0,tolerance:checkpointTolerance,now:sample.time)
            event("tracking_auto_recovered")
        }
        if sample.time-lastUI >= 0.05 {
            // Published values are set only when they change: every set redraws the whole preparation screen,
            // which ran 20 times a second and pushed camera frames past their 0.5 s freshness (#198).
            lastUI=sample.time
            update(\.tracking,sample.tracking); update(\.mapping,sample.mapping)
            update(\.ready,gate.isReady(now:now,validation:restorationValidation)); update(\.canVerify,gate.canVerify(now:now))
            if ready, restorationValidation == .relocalization {restoreStarted=nil}
            update(\.canSave,mode == .scanning && !busy && sample.normal && sample.mapped &&
                referenceAnchorsPresent(sample) && (!supportsMesh || !meshes.isEmpty) && stage != nil && routeIsValid)
            if let stage, ready {
                update(\.position,stagePosition(sample.world))
                update(\.heading,stage.heading(cameraForward:alignment?.inverseDirection(sample.forward) ?? sample.forward))
            } else { update(\.position,nil); update(\.heading,nil) }
            guidancePoseTime=sample.time
            if mode == .restoring {
                let candidate=sample.normal && referenceAnchorsPresent(sample)
                renderer.meshLayer.isHidden = !candidate || !showMesh; renderer.referenceLayer.isHidden = !candidate
                if !ready { status=canVerify ? L("복원 후보 확보 · 확인점 %@번을 선택하세요", nextCheckpointNumber) : L("공간 복원 중 · 기준 앵커와 안정된 추적을 기다립니다") }
            }
        }
        if sample.time-lastPoseLog>=0.05 {
            lastPoseLog=sample.time
            let raw=sample.world.valid ? stagePosition(sample.world) : nil
            event("pose",detail:"observing",position:raw,
                  heading:stage?.heading(cameraForward:alignment?.inverseDirection(sample.forward) ?? sample.forward),time:sample.time)
        }
    }
    func receiveMeshes(_ parts: [MeshSnapshot], removed: [UUID], token incoming: UUID) {
        guard incoming==token, mode == .scanning, active, !busy, !meshFrozen else { return }
        for id in removed { meshes[id]=nil }
        for part in parts { meshes[part.id]=part }
        let started=now
        renderer.updateMeshes(parts,removed:removed)
        if (now-started)*1000>30 { event("mesh_render_slow",detail:"ms=\(Int((now-started)*1000)) parts=\(parts.count)") }
        updateCounts()
        if vertexCount>800_000 { interrupt(L("메시가 너무 큽니다. 더 작은 영역으로 새 스캔을 시작하세요."),token:token) }
    }
    func updateCounts() { update(\.meshCount,meshes.count); update(\.vertexCount,meshes.values.reduce(0){$0+$1.vertices.count}) }
    /// Sets a published value only when it differs, so unchanged values do not redraw observing views.
    func update<Value: Equatable>(_ key: ReferenceWritableKeyPath<ARSessionController,Value>, _ value: Value) {
        if self[keyPath:key] != value { self[keyPath:key]=value }
    }
    var routeIsValid: Bool { preparedDraft?.errors.isEmpty ?? false }
    func stagePosition(_ world: Point3) -> Point3? {
        let world=alignment?.inverse(world) ?? world
        if let area {
            let floor=area.floor(world)
            return Point3(floor.x,floor.y,world.y-area.floorHeight)
        }
        return stage?.position(world)
    }
    func referenceAnchorsPresent(_ sample: CameraSample) -> Bool {
        guard let origin, let front, let checkpoint else { return false }
        var references=[(".origin",origin),(".front",front),(".check",checkpoint)]
        if let secondCheckpoint { references.append((".check2",secondCheckpoint)) }
        return references.allSatisfy { name, expected in
            sample.anchors[referencePrefix+name].map {$0.distance(to:expected)<0.05} ?? false
        }
    }
}
