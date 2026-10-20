import ARKit
import AVFoundation
import HearIAmCore

/// Starting, restoring, interrupting and expiring sessions.
extension ARSessionController {
    func newScan() {
        guard !busy else { return }
        busy=true
        let operation=token
        Task {
            defer { if token==operation {busy=false} }
            guard supported else { errorMessage="LiDAR 메시 스캔을 지원하는 실제 iPhone이 필요합니다."; return }
            guard await permission(), active, token==operation else { return }
            busy=false
            reset()
            scanID=UUID(); mode = .scanning
            beginLog(source:"new-scan")
            guard logger.isOpen else {mode = .idle; return}
            startSession(map:nil)
            status="네 꼭짓점, 경로, 장애물, 독립 확인점 C를 선택하세요"
        }
    }
    func restore(_ item: ScanManifest) {
        guard !busy else { return }
        busy=true
        // Capture invalidation generation BEFORE an await; backgrounding cancels this operation.
        let operation=token
        Task {
            defer { if token==operation {busy=false} }
            guard supported else { errorMessage="이 기기는 저장한 공간의 AR 안내를 지원하지 않습니다."; return }
            guard await permission(), active else { return }
            do {
                let loaded=try await store.load(item.id)
                guard token==operation, active else { return }
                guard let map=try NSKeyedUnarchiver.unarchivedObject(ofClass:ARWorldMap.self,from:loaded.worldMap) else {
                    throw LabError.invalid("공간 지도를 해제할 수 없습니다.")
                }
                let prefix=loaded.manifest.anchorName
                guard [".origin",".front",".check"].allSatisfy({suffix in map.anchors.contains {$0.name==prefix+suffix}}) else {
                    throw LabError.invalid("공간 지도에 기준 앵커가 없습니다.")
                }
                busy=false
                reset()
                manifest=loaded.manifest; scanID=item.id; stage=loaded.manifest.frame
                origin=loaded.manifest.frame.origin; front=loaded.manifest.frame.front; checkpoint=loaded.manifest.checkpoint
                if let route=loaded.manifest.route {
                    area=route.area; corners=route.area.corners.map { Optional($0) }
                    routePoints=route.points; obstacles=route.obstacles; settings=loaded.manifest.settings
                }
                mode = .restoring
                for part in loaded.meshes { meshes[part.id]=part }
                updateCounts(); redrawReferences(); renderer.rebuildMeshes(meshes.values,saved:true)
                renderer.meshLayer.isHidden=true; renderer.referenceLayer.isHidden=true
                beginLog(source:"restore")
                guard logger.isOpen else {mode = .idle; return}
                restoreStarted=now
                startSession(map:map)
                status="복원 중 · 스캔했던 주변과 기준점을 천천히 비추세요"
            } catch { if token==operation { errorMessage="불러오기 실패: "+error.localizedDescription } }
        }
    }
    func resumePreparation() {
        guard vertexCount<=800_000 else {errorMessage="스캔 범위가 너무 큽니다. 준비를 종료하고 더 작은 영역으로 다시 스캔해주세요."; return}
        guard active, mode == .scanning, let configuration=session?.configuration else { return }
        latest=nil; preparationInterrupted=false; session?.run(configuration)
        status="주변을 천천히 비추며 추적을 다시 확인해주세요."
    }
    /// Preparation keeps its input and waits for an explicit resume; guidance ends the session.
    func interrupt(_ message: String, token incoming: UUID) {
        guard incoming==token else { return }
        if purpose == .preparation, mode == .scanning, message != "측정 종료" {
            cancelPhotoCapture()
            session?.pause(); preparationInterrupted=true; canSave=false
            if !archiveWriteInProgress {saveAttempt=UUID(); busy=false}
            latest=nil; status="추적이 중단됐습니다. 같은 공간에서 추적을 다시 시작해주세요."
            return
        }
        event("session_interrupted",detail:message)
        session?.pause(); session?.delegate=nil; token=UUID(); busy=false; gate.invalidate()
        canSave=false; canVerify=false; mode = .idle; restoreStarted=nil
        invalidateWear(message); stopLog(); UIApplication.shared.isIdleTimerDisabled=false
    }
    func setActive(_ value: Bool) {
        active=value
        if purpose == .preparation {
            if !value {
                cancelPhotoCapture()
                session?.pause(); latest=nil; canSave=false; preparationInterrupted=true
                if !archiveWriteInProgress {saveAttempt=UUID(); busy=false}
            }
            return
        }
        if !value { interrupt("앱 비활성화 · 저장 공간을 다시 불러오거나 새 스캔을 시작하세요",token:token) }
    }
    func endSession() { interrupt("측정 종료",token:token); clearPhotos() }

    func permission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for:.video)
        default: errorMessage="설정 앱에서 카메라 접근을 허용하세요."; return false
        }
    }
    func audioInterrupted() {
        gate.invalidate(); invalidateWear("오디오 중단 · C 재검증 필요")
        event("audio_interrupted")
    }
    /// Revokes checkpoint verification; the wearer must verify the checkpoint again.
    func invalidateWear(_ message: String) {
        ready=false; position=nil; heading=nil; guidancePoseTime=nil; status=message
        if purpose == .guidance {renderer.referenceLayer.isHidden=true}
    }
    func tick() {
        let was=gate.verified; gate.expire(now:now)
        if was && !gate.verified { invalidateWear("센서 표본 만료 · C 재검증 필요"); event("sample_expired") }
        canVerify=gate.canVerify(now:now); ready=gate.isReady(now:now)
        if let latest, now-latest.time>0.5 { canSave=false }
        if purpose == .preparation { updateAim() }
        if let restoreStarted, now-restoreStarted>60, !ready, !canVerify {
            interrupt("복원 60초 초과 · 주변을 확인한 후 저장 공간을 다시 불러오세요",token:token)
        }
        let checkedToken=token
        logger.checkFailure { [weak self] failure in
            guard let failure else { return }
            Task { @MainActor in
                guard let self, self.token==checkedToken else { return }
                self.errorMessage="로그 저장 실패: "+failure
                self.interrupt("로그 저장 실패로 측정 종료",token:checkedToken)
            }
        }
    }
}
