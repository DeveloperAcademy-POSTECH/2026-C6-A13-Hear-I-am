import ARKit
import SceneKit
import AVFoundation
import SwiftUI
import Combine
import PoC4Core

@MainActor
final class ScanLabModel: ObservableObject {
    enum Mode: String { case idle, scanning, restoring, saved }
    @Published private(set) var mode: Mode = .idle
    @Published private(set) var status="새 스캔 또는 저장 공간을 선택하세요"
    @Published private(set) var tracking="대기"
    @Published private(set) var mapping="대기"
    @Published private(set) var meshCount=0
    @Published private(set) var vertexCount=0
    @Published private(set) var records: [ScanManifest]=[]
    @Published private(set) var position: Point3?
    @Published private(set) var heading: Double?
    @Published private(set) var ready=false
    @Published private(set) var canVerify=false
    @Published private(set) var canSave=false
    @Published private(set) var busy=false
    @Published private(set) var recordOn=false
    @Published private(set) var wearCountdown: Int?
    @Published private(set) var lastErrorMeters: Double?
    @Published private(set) var references="O → F → C를 선택하세요"
    @Published private(set) var exports: [URL]=[]
    @Published var scanName="무대 스캔"
    @Published var note=""
    @Published var errorMessage: String?
    @Published var showMesh=true { didSet { overlay.isHidden = !showMesh } }
    let checkpointTolerance=0.15 // Experiment threshold, NOT an accuracy guarantee.
    let supported=ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    let store: ScanStore
    let logDirectory: URL
    weak var view: ARSCNView?
    private var session: ARSession?
    private var bridge: SessionBridge?
    private var token=UUID()
    private var scanID=UUID()
    private var manifest: ScanManifest?
    private var meshes: [UUID:MeshSnapshot]=[:]
    let previewScene = SCNScene()
    let previewRoot = SCNNode()
    private var previewNodes: [UUID: SCNNode] = [:]
    private var previewDirty: Set<UUID> = []
    private var previewVisible = false
    private var lastPreviewUpdate = -Double.infinity
    @Published private(set) var previewRevision = 0

    func setPreviewVisible(_ visible: Bool) {
        previewVisible = visible
        if visible {
            previewDirty.formUnion(meshes.keys)
            updatePreview()
        } else {
            previewRoot.childNodes.forEach { $0.removeFromParentNode() }
            previewNodes.removeAll()
        }
    }

    private func updatePreview() {
        guard previewVisible, !previewDirty.isEmpty else { return }
        for id in previewDirty {
            previewNodes.removeValue(forKey: id)?.removeFromParentNode()
            guard let mesh = meshes[id] else { continue }
            let node = mesh.node(saved: mode != .scanning, solid: true)
            previewNodes[id] = node
            previewRoot.addChildNode(node)
        }
        previewDirty.removeAll()
        lastPreviewUpdate = now
        previewRevision += 1
    }

    private var nodes: [UUID:SCNNode]=[:]
    private let overlay=SCNNode()
    private let referenceOverlay=SCNNode()
    private var origin: Point3?
    private var front: Point3?
    private var checkpoint: Point3?
    private var stage: StageFrame?
    private var gate=TrackingGate()
    private var latest: CameraSample?
    private var lastUI = -Double.infinity
    private var lastPoseLog = -Double.infinity
    private var watchdog: Timer?
    private var restoreStarted: Double?
    private var logging: TrialLog?
    private var sequence=0
    private var active=true
    private var wearTask: Task<Void,Never>?
    private let cameraQueue=DispatchQueue(label:"PoC4.AR",qos:.userInitiated)
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var referencePrefix: String { "PoC4.reference."+scanID.uuidString }
    var stageLabel: String { manifest?.name ?? (mode == .scanning ? scanName : "없음") }

    init() {
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        store=ScanStore(root:docs.appendingPathComponent("Scans",isDirectory:true))
        logDirectory=docs.appendingPathComponent("Trials",isDirectory:true)
        previewScene.rootNode.addChildNode(previewRoot)
        refreshFiles()
        watchdog=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    func attach(_ arView: ARSCNView) {
        view=arView; arView.scene=SCNScene()
        arView.scene.rootNode.addChildNode(overlay)
        arView.scene.rootNode.addChildNode(referenceOverlay)
    }
    func refreshFiles() {
        Task {
            do { records=try await store.list() }
            catch { errorMessage="스캔 목록 오류: "+error.localizedDescription }
        }
        do {
            exports=try FileManager.default.contentsOfDirectory(at:logDirectory,includingPropertiesForKeys:nil)
                .filter {$0.pathExtension=="jsonl"}.sorted {$0.lastPathComponent>$1.lastPathComponent}
        } catch {
            if FileManager.default.fileExists(atPath:logDirectory.path) { errorMessage=error.localizedDescription }
        }
    }
    private func permission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for:.video)
        default: errorMessage="설정 앱에서 카메라 접근을 허용하세요."; return false
        }
    }
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
            guard logging != nil else {mode = .idle; return}
            startSession(map:nil)
            status="바닥을 스캔하고 중심 십자선을 O → F → C에 맞춰 선택하세요"
        }
    }
    func restore(_ item: ScanManifest) {
        guard !busy else { return }
        busy=true
        // Capture invalidation generation BEFORE an await; backgrounding cancels this operation.
        let operation=token
        Task {
            defer { if token==operation {busy=false} }
            guard supported, await permission(), active else { return }
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
                mode = .restoring
                for part in loaded.meshes { meshes[part.id]=part }
                updateCounts(); redrawReferences(); rebuildMesh(saved:true)
                overlay.isHidden=true; referenceOverlay.isHidden=true
                beginLog(source:"restore")
                guard logging != nil else {mode = .idle; return}
                restoreStarted=now
                startSession(map:map)
                references="저장된 O·F·C · C를 다시 선택해 검증"
                status="복원 중 · 스캔했던 주변과 기준점을 천천히 비추세요"
            } catch { if token==operation { errorMessage="불러오기 실패: "+error.localizedDescription } }
        }
    }
    private func reset() {
        cancelCountdown()
        stopLog()
        session?.delegate=nil; session?.pause()
        token=UUID(); gate=TrackingGate(); latest=nil
        position=nil; heading=nil; ready=false; canVerify=false; canSave=false
        previewRoot.childNodes.forEach { $0.removeFromParentNode() }
        previewNodes.removeAll(); previewDirty.removeAll()
        previewRevision += 1
        meshes=[:]; nodes.values.forEach {$0.removeFromParentNode()}; nodes=[:]
        referenceOverlay.childNodes.forEach {$0.removeFromParentNode()}
        overlay.isHidden = !showMesh; referenceOverlay.isHidden=false
        manifest=nil; origin=nil; front=nil; checkpoint=nil; stage=nil
        recordOn=false; lastErrorMeters=nil; references="O → F → C를 선택하세요"
        restoreStarted=nil; updateCounts(); lastUI = -.infinity; lastPoseLog = -.infinity
    }
    private func startSession(map: ARWorldMap?) {
        let config=ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity; config.planeDetection=[.horizontal]
        // Mesh creation only in pre-scan. During restoration use the saved snapshot.
        if mode == .scanning { config.sceneReconstruction = .mesh }
        config.initialWorldMap=map
        let newSession=ARSession()
        bridge=SessionBridge(model:self,token:token)
        newSession.delegate=bridge; newSession.delegateQueue=cameraQueue
        session=newSession; view?.session=newSession
        newSession.run(config,options:[.resetTracking,.removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled=true
    }
    private func referenceAnchorsPresent(_ sample: CameraSample) -> Bool {
        guard let origin, let front, let checkpoint else { return false }
        return [(".origin",origin),(".front",front),(".check",checkpoint)].allSatisfy { name, expected in
            sample.anchors[referencePrefix+name].map {$0.distance(to:expected)<0.05} ?? false
        }
    }
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
                referenceAnchorsPresent(sample) && !meshes.isEmpty && stage != nil
            if let stage, ready {
                position=stage.position(sample.world)
                heading=stage.heading(cameraForward:sample.forward)
                if heading == nil && recordOn { gate.invalidate(); invalidateWear("카메라 수평 방향 불명확 · 착용 자세와 C를 다시 확인하세요") }
            } else { position=nil; heading=nil }
            if mode == .restoring {
                let candidate=sample.normal && referenceAnchorsPresent(sample)
                overlay.isHidden = !candidate || !showMesh; referenceOverlay.isHidden = !candidate
                if !ready { status=canVerify ? "복원 후보 확보 · 실제 C를 다시 선택해 검증하세요" : "공간 복원 중 · 기준 앵커와 안정된 추적을 기다립니다" }
            }
        }
        if sample.time-lastPoseLog>=0.05 {
            lastPoseLog=sample.time
            let raw=sample.world.valid ? stage?.position(sample.world) : nil
            event("pose",detail:recordOn ? "wearing" : "observing",position:raw,
                  heading:stage?.heading(cameraForward:sample.forward),time:sample.time)
        }
    }
    func receiveMeshes(_ parts: [MeshSnapshot], removed: [UUID], token incoming: UUID) {
        guard incoming==token, mode == .scanning, active, !busy else { return }
        previewDirty.formUnion(removed)
        previewDirty.formUnion(parts.map(\.id))
        for id in removed { meshes[id]=nil; nodes.removeValue(forKey:id)?.removeFromParentNode() }
        for part in parts {
            meshes[part.id]=part
            nodes.removeValue(forKey:part.id)?.removeFromParentNode()
            let node=part.node(saved:false); nodes[part.id]=node; overlay.addChildNode(node)
        }
        updateCounts()
        if vertexCount>800_000 { interrupt("메시가 너무 큽니다. 더 작은 영역으로 새 스캔을 시작하세요.",token:token) }
    }
    private func updateCounts() { meshCount=meshes.count; vertexCount=meshes.values.reduce(0){$0+$1.vertices.count} }
    private func rebuildMesh(saved: Bool) {
        previewDirty.formUnion(meshes.keys)
        nodes.values.forEach {$0.removeFromParentNode()}; nodes=[:]
        for m in meshes.values { let n=m.node(saved:saved); nodes[m.id]=n; overlay.addChildNode(n) }
    }
    private func centerFloorPoint() throws -> Point3 {
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
    func capture(_ kind: String) {
        guard mode == .scanning, !busy else { return }
        do {
            let point=try centerFloorPoint()
            switch kind {
            case "O":
                origin=point; front=nil; checkpoint=nil; stage=nil
                removeReferenceAnchors()
                addReference(point,suffix:".origin")
            case "F":
                guard let origin else { throw LabError.invalid("O를 먼저 선택하세요.") }
                stage=try StageFrame(origin:origin,front:point); front=point; checkpoint=nil
                removeReference(suffix:".front"); removeReference(suffix:".check")
                addReference(point,suffix:".front")
            default:
                guard let origin, let front else { throw LabError.invalid("O와 F를 먼저 선택하세요.") }
                guard point.distance(to:origin)>=0.5, point.distance(to:front)>=0.5,
                      abs(point.y-origin.y)<=0.15 else { throw LabError.invalid("C는 O·F에서 0.5m 이상 떨어진 같은 바닥점이어야 합니다.") }
                checkpoint=point; removeReference(suffix:".check"); addReference(point,suffix:".check")
            }
            gate.invalidate(); invalidateWear("기준 변경 · C 확인 필요")
            references="O \(origin == nil ? "—" : "✓") · F \(front == nil ? "—" : "✓") · C \(checkpoint == nil ? "—" : "✓")"
            redrawReferences(); event("reference_"+kind,position:point)
        } catch { errorMessage=error.localizedDescription }
    }
    private func removeReferenceAnchors() {
        session?.currentFrame?.anchors.filter {$0.name?.hasPrefix(referencePrefix) == true}.forEach {session?.remove(anchor:$0)}
    }
    private func removeReference(suffix: String) {
        session?.currentFrame?.anchors.filter {$0.name==referencePrefix+suffix}.forEach {session?.remove(anchor:$0)}
    }
    private func addReference(_ p: Point3, suffix: String) {
        var t=matrix_identity_float4x4; t.columns.3=SIMD4(Float(p.x),Float(p.y),Float(p.z),1)
        session?.add(anchor:ARAnchor(name:referencePrefix+suffix,transform:t))
    }
    private func redrawReferences() {
        referenceOverlay.childNodes.forEach {$0.removeFromParentNode()}
        for (label,p) in [("O",origin),("F",front),("C",checkpoint)] {
            guard let p else { continue }
            let node=SCNNode(geometry:SCNSphere(radius:0.04)); node.geometry?.firstMaterial?.diffuse.contents=UIColor.systemYellow
            node.position=SCNVector3(Float(p.x),Float(p.y)+0.04,Float(p.z)); referenceOverlay.addChildNode(node)
            let text=SCNText(string:label,extrusionDepth:0); text.font = .boldSystemFont(ofSize:10)
            let n=SCNNode(geometry:text); n.scale=SCNVector3(0.015,0.015,0.015)
            n.position=SCNVector3(Float(p.x),Float(p.y)+0.12,Float(p.z)); n.constraints=[SCNBillboardConstraint()]
            referenceOverlay.addChildNode(n)
        }
    }
    func verifyCheckpoint() {
        guard !busy, let checkpoint else { return }
        do {
            let observed=try centerFloorPoint()
            let distance=observed.distance(to:checkpoint)
            lastErrorMeters=distance
            let ok=gate.verify(error:distance,tolerance:checkpointTolerance,now:now)
            ready=ok
            event("checkpoint",detail:ok ? "pass" : "fail",position:observed,error:distance)
            if ok { status="C 검증 통과 · 배에 카메라를 앞쪽으로 고정하고 추적 시작"; restoreStarted=nil }
            else { invalidateWear("C 검증 실패 · 표식과 공간 복원을 다시 확인하세요") }
        } catch { gate.invalidate(); invalidateWear("확인점 선택 실패"); errorMessage=error.localizedDescription }
    }
    func save() {
        guard canSave, !busy, let session, let stage, let checkpoint else { return }
        busy=true; canSave=false
        let operation=token
        session.getCurrentWorldMap { [weak self] map,error in
            Task { @MainActor in
                guard let self, self.token==operation, self.active else { return }
                guard let map, error==nil, let sample=self.latest, sample.normal,
                      sample.mapped, self.now-sample.time<=0.5,
                      self.referenceAnchorsPresent(sample) else {
                    self.busy=false; self.errorMessage=error?.localizedDescription ?? "공간 지도가 안정되지 않았습니다. 다시 시도하세요."; return
                }
                let parts=Array(self.meshes.values)
                let id=self.scanID, name=self.scanName.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !name.isEmpty else {self.busy=false; self.errorMessage="스캔 이름을 입력하세요."; return}
                guard [".origin",".front",".check"].allSatisfy({suffix in map.anchors.contains {$0.name==self.referencePrefix+suffix}}) else {
                    self.busy=false; self.errorMessage="공간 지도에 기준점이 아직 포함되지 않았습니다. 다시 저장하세요."; return
                }
                self.session?.pause(); self.mode = .saved; self.gate.invalidate(); self.ready=false
                self.cancelCountdown(); self.position=nil; self.heading=nil; self.recordOn=false
                do {
                    let data=try NSKeyedArchiver.archivedData(withRootObject:map,requiringSecureCoding:true)
                    let result=try await self.store.save(id:id,name:name,frame:stage,checkpoint:checkpoint,
                        worldMap:data,meshes:parts,device:UIDevice.current.model+" / "+UIDevice.current.systemVersion,
                        appVersion:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
                    guard self.token==operation else { return }
                    self.manifest=result; self.status="저장 완료 · 앱 재실행 후 저장 공간을 불러와 C를 검증하세요"
                    self.event("scan_saved",detail:result.id.uuidString); self.stopLog(); self.refreshFiles()
                } catch {
                    guard self.token==operation else { return }
                    self.errorMessage="저장 실패: "+error.localizedDescription; self.status="저장 실패 · 새 스캔으로 다시 시도하세요"
                    self.stopLog()
                }
                self.busy=false; UIApplication.shared.isIdleTimerDisabled=false
            }
        }
    }
    func startWear() {
        guard ready, logging != nil, !recordOn, wearCountdown == nil else { return }
        let operation=token
        wearTask=Task { [weak self] in
            guard let self else { return }
            for seconds in stride(from:8,through:1,by:-1) {
                guard !Task.isCancelled, self.token==operation, self.active, self.gate.isReady(now:self.now) else {
                    self.wearCountdown=nil; return
                }
                self.wearCountdown=seconds
                self.status="착용 준비 \(seconds)초 · 카메라를 앞쪽으로 고정하세요"
                do {try await Task.sleep(nanoseconds:1_000_000_000)} catch {return}
            }
            self.wearCountdown=nil
            guard self.token==operation, self.gate.isReady(now:self.now),
                  self.heading != nil, self.logging != nil else {
                self.status="착용 시작 취소 · C와 카메라 방향을 확인하세요"; return
            }
            self.recordOn=true; self.event("wear_start",detail:"rear camera outward, portrait")
            self.status="착용 추적 기록 중 · 카메라 위치의 추정값이며 발 위치가 아닙니다"
            UIAccessibility.post(notification:.announcement,argument:"착용 기록 시작")
        }
    }
    private func cancelCountdown() {wearTask?.cancel(); wearTask=nil; wearCountdown=nil}
    func stopWear() {cancelCountdown(); recordOn=false; event("wear_stop"); status="착용 구간 종료 · 관측 로그는 계속 기록"}
    func addNote() {
        let text=note.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        event("manual_note",detail:text); note=""
    }
    private func invalidateWear(_ message: String) {
        cancelCountdown()
        if recordOn { event("wear_invalidated",detail:message) }
        recordOn=false; ready=false; position=nil; heading=nil; status=message
    }
    func interrupt(_ message: String, token incoming: UUID) {
        guard incoming==token else { return }
        event("session_interrupted",detail:message)
        session?.pause(); session?.delegate=nil; token=UUID(); busy=false; gate.invalidate()
        canSave=false; canVerify=false; mode = .idle; restoreStarted=nil
        invalidateWear(message); stopLog(); UIApplication.shared.isIdleTimerDisabled=false
    }
    func setActive(_ value: Bool) {
        active=value
        if !value { interrupt("앱 비활성화 · 저장 공간을 다시 불러오거나 새 스캔을 시작하세요",token:token) }
    }
    func endSession() { interrupt("측정 종료",token:token) }
    private func tick() {
        if now-lastPreviewUpdate >= 0.5 { updatePreview() }
        let was=gate.verified; gate.expire(now:now)
        if was && !gate.verified { invalidateWear("센서 표본 만료 · C 재검증 필요"); event("sample_expired") }
        canVerify=gate.canVerify(now:now); ready=gate.isReady(now:now)
        if let latest, now-latest.time>0.5 { canSave=false }
        if let restoreStarted, now-restoreStarted>60, !ready, !canVerify {
            interrupt("복원 60초 초과 · 주변을 확인한 후 저장 공간을 다시 불러오세요",token:token)
        }
        let checkedToken=token
        logging?.checkFailure { [weak self] failure in
            guard let failure else { return }
            Task { @MainActor in
                guard let self, self.token==checkedToken else { return }
                self.errorMessage="로그 저장 실패: "+failure
                self.interrupt("로그 저장 실패로 측정 종료",token:checkedToken)
            }
        }
    }
    private func beginLog(source: String) {
        do {
            sequence=0
            logging=try TrialLog(directory:logDirectory,metadata:[
                "source":source,"scanID":scanID.uuidString,"sessionID":token.uuidString,
                "device":UIDevice.current.model,"os":UIDevice.current.systemVersion,
                "appVersion":Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "checkpointToleranceMeters":String(checkpointTolerance),"maxSampleAgeSeconds":"0.5",
                "coordinates":"X map-right; Y backstage; Z up; heading clockwise from audience",
                "positionMeaning":"phone horizontal projection; not foot or ground truth"])
            event("session_start",detail:source)
        } catch { errorMessage="로그를 만들 수 없습니다: "+error.localizedDescription; logging=nil }
    }
    private func event(_ name: String, detail: String="", position: Point3?=nil, heading: Double?=nil,
                       error: Double?=nil, time: Double?=nil) {
        sequence+=1
        logging?.append(TrialRecord(sequence:sequence,uptime:time ?? now,event:name,detail:detail,
            position:position,heading:heading,tracking:latest?.tracking ?? tracking,
            verified:gate.isReady(now:now),errorMeters:error,
            coordinateSpace:(name.hasPrefix("reference_") || name=="checkpoint") ? "ar-world" : "stage",
            mapping:latest?.mapping ?? mapping))
    }
    private func stopLog() {
        guard let logger=logging else { return }
        event("session_end"); logging=nil
        logger.close { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success: self?.refreshFiles()
                case .failure(let error): self?.errorMessage="로그 마무리 실패: "+error.localizedDescription
                }
            }
        }
    }
}
