import ARKit
import HearIAmCore

/// Saving the world map, mesh and prepared route as one scan bundle.
extension ARSessionController {
    func awaitSaveRecovery(_ detail: String) {
        busy=false; canSave=false; saveRecoveryPending=true
        errorMessage=nil
        status="입력한 내용은 유지됩니다. 주변을 천천히 비춰주세요. 추적과 공간 지도가 안정되면 다시 저장할 수 있어요."
        event("save_recovery",detail:detail)
    }
    func save(name rawName: String) {
        guard canSave, !busy, !photoCapturing, let session, let stage, let checkpoint, let secondCheckpoint, let area else { return }
        let route: StageRoute
        do { route = try preparedDraft?.stageRoute() ?? StageRoute(area:area,points:routePoints,obstacles:obstacles) }
        catch { errorMessage=error.localizedDescription; return }
        busy=true; canSave=false; errorMessage=nil
        let operation=token
        saveAttempt=UUID(); let attempt=saveAttempt
        Task { [weak self] in
            try? await Task.sleep(for:.seconds(15))
            guard let self, self.token==operation, self.saveAttempt==attempt, self.busy, !self.archiveWriteInProgress else {return}
            self.saveAttempt=UUID()
            self.awaitSaveRecovery("world map timeout")
        }
        session.getCurrentWorldMap { [weak self] map,error in
            Task { @MainActor in
                guard let self, self.token==operation, self.saveAttempt==attempt else { return }
                guard self.active else {self.busy=false; return}
                guard let map, error==nil, let sample=self.latest, sample.normal,
                      sample.mapped, self.now-sample.time<=0.5,
                      self.referenceAnchorsPresent(sample) else {
                    self.awaitSaveRecovery(error?.localizedDescription ?? "tracking or map not ready"); return
                }
                let parts=self.meshes.isEmpty ? Self.fallbackFloorMesh(area:area) : Array(self.meshes.values)
                let id=self.scanID, name=rawName.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !name.isEmpty else {self.busy=false; self.errorMessage="스캔 이름을 입력하세요."; return}
                guard [".origin",".front",".check",".check2"].allSatisfy({suffix in map.anchors.contains {$0.name==self.referencePrefix+suffix}}) else {
                    self.awaitSaveRecovery("reference anchors missing"); return
                }
                guard self.photoSources.allSatisfy({source in
                    guard let anchor=self.photoAnchors[source.photo.id] else {return false}
                    return map.anchors.contains {$0.identifier==anchor.identifier}
                }) else {
                    self.awaitSaveRecovery("photo anchors missing");return
                }
                self.session?.pause(); self.gate.invalidate(); self.ready=false
                self.position=nil; self.heading=nil
                do {
                    let data=try NSKeyedArchiver.archivedData(withRootObject:map,requiringSecureCoding:true)
                    self.archiveWriteInProgress=true
                    let photoOwner=self.photoCapture
                    let photos=self.photosForSaving(route:route,map:map)
                    let result=try await self.store.save(id:id,name:name,frame:stage,checkpoint:checkpoint,
                        worldMap:data,meshes:parts,device:UIDevice.current.model+" / "+UIDevice.current.systemVersion,
                        appVersion:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                        route:route,settings:self.settings,photos:photos,secondCheckpoint:secondCheckpoint)
                    withExtendedLifetime(photoOwner) {}
                    guard self.token==operation else { return }
                    self.saveRecoveryPending=false
                    self.mode = .saved; self.savedID=result.id; self.manifest=result; self.status="저장 완료 · 앱 재실행 후 저장 공간을 불러와 확인점 1·2를 확인하세요"
                    self.event("scan_saved",detail:result.id.uuidString); self.stopLog()
                } catch {
                    guard self.token==operation else { return }
                    self.errorMessage="저장 실패: "+error.localizedDescription; self.status="입력은 유지됩니다. 다시 저장해주세요."
                    if let configuration=self.session?.configuration, self.active { self.session?.run(configuration) }
                }
                self.archiveWriteInProgress=false; self.busy=false; UIApplication.shared.isIdleTimerDisabled = self.mode == .scanning
            }
        }
    }
    private static func fallbackFloorMesh(area: StageArea) -> [MeshSnapshot] {
        let identity: [Float] = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]
        return [MeshSnapshot(id:UUID(), transform:identity, vertices:area.corners, indices:[0,1,2, 0,2,3])]
    }
}
