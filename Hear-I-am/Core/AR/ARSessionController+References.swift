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
            throw LabError.invalid("십자선 아래 확인된 수평면이 없습니다. 실제 무대 바닥을 천천히 비추세요.")
        }
        let p=hit.worldTransform.columns.3
        let point=Point3(Double(p.x),Double(p.y),Double(p.z))
        guard point.valid, point.distance(to:latest.world)<=5,
              point.y < latest.world.y-0.15 else { throw LabError.invalid("기기 아래의 바닥을 5m 이내에서 선택하세요.") }
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
    func applyPreparation(_ draft: PreparationDraft, pendingObject world: [Point3]) {
        preparedDraft=draft
        corners=draft.corners; checkpoint=draft.checkpoint; area=draft.area
        removeReferenceAnchors(); addCornerAnchors()
        if let area {
            origin=area.world(FloorPoint(0,0)); front=area.world(FloorPoint(0,-1))
            stage=try? StageFrame(origin:origin!,front:front!)
            addReference(origin!,suffix:".origin"); addReference(front!,suffix:".front")
            routePoints=draft.route.map(area.floor)
            obstacles=draft.objects.compactMap {try? $0.projected(in:area)}
            pendingObject=world.map(area.floor)
        } else { origin=nil; front=nil; stage=nil; routePoints=[]; obstacles=[]; pendingObject=[] }
        if let checkpoint {addReference(checkpoint,suffix:".check")}
        canSave=false; redrawReferences()
    }
    func verifyCheckpoint() {
        guard !busy, let checkpoint else { return }
        do {
            let observed=try centerFloorPoint()
            let distance=observed.distance(to:checkpoint)
            let ok=gate.verify(error:distance,tolerance:checkpointTolerance,now:now)
            ready=ok
            event("checkpoint",detail:ok ? "pass" : "fail",position:observed,error:distance)
            if ok { status="C 검증 통과 · 배에 카메라를 앞쪽으로 고정하고 추적 시작"; restoreStarted=nil }
            else { invalidateWear("C 검증 실패 · 표식과 공간 복원을 다시 확인하세요") }
        } catch { gate.invalidate(); invalidateWear("확인점 선택 실패"); errorMessage=error.localizedDescription }
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
