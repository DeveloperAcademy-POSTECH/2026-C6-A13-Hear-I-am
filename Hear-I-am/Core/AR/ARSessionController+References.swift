import ARKit
import HearIAmCore

/// Floor picking, reference anchors and checkpoint verification.
extension ARSessionController {
    /// The horizontal floor point under the screen-centre crosshair, in AR world metres.
    func centerFloorPoint() throws -> Point3 {
        guard let view, let session, let latest, latest.normal,
              now-latest.time>=0, now-latest.time<=0.5 else { throw LabError.invalid("정상 추적 중에 바닥을 선택하세요.") }
        let center=CGPoint(x:view.bounds.midX,y:view.bounds.midY)
        guard let query=view.raycastQuery(from:center,allowing:.existingPlaneGeometry,alignment:.horizontal),
              let hit=session.raycast(query).first,
              let plane=hit.anchor as? ARPlaneAnchor, plane.alignment == .horizontal else {
            throw LabError.invalid("십자선 아래 인식된 수평면이 없어요. 바닥이나 기물 윗면을 여러 각도에서 천천히 비춰주세요.")
        }
        let p=hit.worldTransform.columns.3
        let point=Point3(Double(p.x),Double(p.y),Double(p.z))
        guard point.valid, point.distance(to:latest.world)<=5,
              point.y < latest.world.y-0.15 else { throw LabError.invalid("휴대폰보다 15cm 이상 아래에 있는 수평면을 5m 이내에서 선택해주세요.") }
        return point
    }
    /// Lets the route step tell whether a point can go here before it is placed (#38). Changes under 1 cm
    /// are not published, so the screen does not redraw while the phone is held still.
    func updateAim() {
        let next=canPlacePoint ? try? centerFloorPoint() : nil
        switch (aimPoint,next) {
        case (nil,nil): return
        case let (current?,new?) where current.distance(to:new) < 0.01: return
        default: aimPoint=next
        }
    }
    /// Mirrors the preparation draft into anchors and the overlay. World coordinates stay authoritative.
    func applyPreparation(_ draft: PreparationDraft, pendingObject world: [Point3], pendingFacingEdge: Int? = nil) {
        preparedDraft=draft; self.pendingFacingEdge=pendingFacingEdge
        corners=draft.corners; checkpoint=draft.checkpoint; secondCheckpoint=draft.secondCheckpoint; area=draft.area
        removeReferenceAnchors(); addCornerAnchors()
        if let area {
            origin=area.world(FloorPoint(0,0)); front=area.world(FloorPoint(0,-1))
            stage=try? StageFrame(origin:origin!,front:front!)
            addReference(origin!,suffix:".origin"); addReference(front!,suffix:".front")
            routePoints=draft.route.map(area.floor)
            obstacles=draft.objects.compactMap {try? $0.projected(in:area)}
            pendingObject=world.map(area.floor)
            settings.obstacleClearance=draft.effectiveObstacleClearance
        } else { origin=nil; front=nil; stage=nil; routePoints=[]; obstacles=[]; pendingObject=[] }
        if let checkpoint {addReference(checkpoint,suffix:".check")}
        if let secondCheckpoint {addReference(secondCheckpoint,suffix:".check2")}
        canSave=false; redrawReferences()
    }
    /// Visual settings do not change spatial anchors or invalidate an already mapped stage.
    func updatePreparationDangerZones(_ zones: [StageDangerZone]) {
        guard purpose == .preparation, preparedDraft?.area != nil else { return }
        preparedDraft?.dangerZones=zones
        redrawReferences()
    }
    func clearAlignment() {
        measuredCheckpoints=[]; checkpointStableSince=nil; alignment=nil
        renderer.applyAlignment(nil)
    }
    func verifyCheckpoint() {
        guard !busy, gate.canVerify(now:now), let checkpoint, let secondCheckpoint else { return }
        do {
            if !measuredCheckpoints.isEmpty && checkpointStableSince != gate.normalSince { clearAlignment() }
            let observed=try centerFloorPoint()
            event("checkpoint",detail:"point \(nextCheckpointNumber)",position:observed)
            measuredCheckpoints.append(observed)
            if measuredCheckpoints.count == 1 {
                checkpointStableSince=gate.normalSince
                status="확인점 1 측정 완료 · 저장한 확인점 2를 선택하세요"
                return
            }
            let correction=try CheckpointAlignment(saved:[checkpoint,secondCheckpoint],observed:measuredCheckpoints)
            guard gate.verify(error:correction.residual,tolerance:checkpointTolerance,now:now) else {
                throw LabError.invalid("위치 추적이 불안정해요. 1번부터 다시 확인해주세요.")
            }
            alignment=correction; renderer.applyAlignment(correction)
            ready=true; restoreStarted=nil
            status="두 확인점 보정 완료 · 휴대폰 착용을 진행하세요"
            event("checkpoint_alignment",detail:"translation=\(correction.translation)m yaw=\(correction.yawDegrees)deg lengthDifference=\(correction.lengthDifference)m residual=\(correction.residual)m",error:correction.residual)
        } catch {
            event("checkpoint_alignment",detail:"fail: \(error.localizedDescription)")
            gate.invalidate(); invalidateWear("두 확인점 보정 실패")
            errorMessage=error.localizedDescription
        }
    }

    private func removeReferenceAnchors() {
        cornerAnchors.values.forEach {session?.remove(anchor:$0)}
        cornerAnchors.removeAll()
        session?.currentFrame?.anchors.filter {$0.name?.hasPrefix(referencePrefix) == true}.forEach {session?.remove(anchor:$0)}
    }
    private func addCornerAnchors() {
        for (index,point) in corners.enumerated() {
            guard let point else {continue}
            var transform=matrix_identity_float4x4
            transform.columns.3=SIMD4(Float(point.x),Float(point.y),Float(point.z),1)
            let anchor=ARAnchor(name:referencePrefix+".corner.\(index)",transform:transform)
            cornerAnchors[index]=anchor
            session?.add(anchor:anchor)
        }
    }
    private func addReference(_ p: Point3, suffix: String) {
        var t=matrix_identity_float4x4; t.columns.3=SIMD4(Float(p.x),Float(p.y),Float(p.z),1)
        session?.add(anchor:ARAnchor(name:referencePrefix+suffix,transform:t))
    }
}
