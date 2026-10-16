import ARKit
import HearIAmCore

/// Saving the world map, mesh and prepared route as one scan bundle.
extension ARSessionController {
    func save(name rawName: String) {
        guard canSave, !busy, let session, let stage, let checkpoint, let area else { return }
        let route: StageRoute
        do { route = try preparedDraft?.stageRoute() ?? StageRoute(area:area,points:routePoints,obstacles:obstacles) }
        catch { errorMessage=error.localizedDescription; return }
        busy=true; canSave=false
        let operation=token
        saveAttempt=UUID(); let attempt=saveAttempt
        Task { [weak self] in
            try? await Task.sleep(for:.seconds(15))
            guard let self, self.token==operation, self.saveAttempt==attempt, self.busy, !self.archiveWriteInProgress else {return}
            self.saveAttempt=UUID(); self.busy=false
            self.errorMessage="공간 지도를 가져오는 데 시간이 걸립니다. 주변을 비추고 다시 저장해주세요."
        }
        session.getCurrentWorldMap { [weak self] map,error in
            Task { @MainActor in
                guard let self, self.token==operation, self.saveAttempt==attempt else { return }
                guard self.active else {self.busy=false; return}
                guard let map, error==nil, let sample=self.latest, sample.normal,
                      sample.mapped, self.now-sample.time<=0.5,
                      self.referenceAnchorsPresent(sample) else {
                    self.busy=false; self.errorMessage=error?.localizedDescription ?? "공간 지도가 안정되지 않았습니다. 다시 시도하세요."; return
                }
                let parts=Array(self.meshes.values)
                let id=self.scanID, name=rawName.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !name.isEmpty else {self.busy=false; self.errorMessage="스캔 이름을 입력하세요."; return}
                guard [".origin",".front",".check"].allSatisfy({suffix in map.anchors.contains {$0.name==self.referencePrefix+suffix}}) else {
                    self.busy=false; self.errorMessage="공간 지도에 기준점이 아직 포함되지 않았습니다. 다시 저장하세요."; return
                }
                self.session?.pause(); self.gate.invalidate(); self.ready=false
                self.position=nil; self.heading=nil
                do {
                    let data=try NSKeyedArchiver.archivedData(withRootObject:map,requiringSecureCoding:true)
                    self.archiveWriteInProgress=true
                    let result=try await self.store.save(id:id,name:name,frame:stage,checkpoint:checkpoint,
                        worldMap:data,meshes:parts,device:UIDevice.current.model+" / "+UIDevice.current.systemVersion,
                        appVersion:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                        route:route,settings:self.settings)
                    guard self.token==operation else { return }
                    self.mode = .saved; self.savedID=result.id; self.manifest=result; self.status="저장 완료 · 앱 재실행 후 저장 공간을 불러와 C를 검증하세요"
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
}
