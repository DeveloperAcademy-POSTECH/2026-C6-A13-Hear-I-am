import ARKit
import SceneKit
import AVFoundation
import MediaPlayer
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
    @Published private(set) var references="앞왼쪽 → 앞오른쪽 → 뒤오른쪽 → 뒤왼쪽 → C"
    @Published private(set) var corners: [Point3?] = Array(repeating:nil,count:4)
    @Published private(set) var routePoints: [FloorPoint] = []
    @Published private(set) var obstacles: [StageObstacle] = []
    @Published private(set) var obstacleDraft: [FloorPoint] = []
    @Published var obstacleName="장애물"
    @Published var obstacleKind: ObstacleKind = .box
    @Published var settings=GuideSettings() { didSet { updateRouteStatus() } }
    @Published private(set) var routeConflicts: [String] = []
    @Published private(set) var guideState: GuideState = .idle
    @Published private(set) var guideTargetIndex: Int?
    @Published private(set) var autoResumePending=false
    @Published private(set) var guideMessage="경로를 저장하고 C를 검증하세요"
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
    private var saveAttempt=UUID()
    private var archiveWriteInProgress=false
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
            updatePreview(); redrawReferences()
        } else {
            previewRoot.childNodes.forEach { $0.removeFromParentNode() }
            previewNodes.removeAll()
            previewAnnotations.childNodes.forEach {$0.removeFromParentNode()}
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
    private var cornerAnchors: [Int: ARAnchor] = [:]
    private var origin: Point3?
    private var front: Point3?
    private var checkpoint: Point3?
    private var stage: StageFrame?
    private var area: StageArea?
    private var guide: RouteGuide?
    private var suspendedGuide: RouteGuide?
    private var suspendedScanID: UUID?
    private let speech=AVSpeechSynthesizer()
    private var remoteTargets: [Any] = []
    private let previewAnnotations=SCNNode()
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

    @Published private(set) var preparation: PreparationDraft?
    @Published private(set) var scanConfirmed = false
    @Published private(set) var savedID: UUID?
    @Published private(set) var preparationInterrupted = false
    @Published private(set) var pendingObjectWorld: [Point3] = []
    private var editingObjectID: UUID?
    var canConfirmScan: Bool { mode == .scanning && !busy && !meshes.isEmpty && latest?.mapped == true && latest?.normal == true && now-(latest?.time ?? 0) < 0.5 }
    var canPlacePoint: Bool { mode == .scanning && !busy && !preparationInterrupted && latest?.normal == true && now-(latest?.time ?? 0) < 0.5 }

    init(preparing: Bool = false) {
        preparation = preparing ? PreparationDraft() : nil
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        store=ScanStore(root:docs.appendingPathComponent("Scans",isDirectory:true))
        logDirectory=docs.appendingPathComponent("Trials",isDirectory:true)
        if preparing {
            settings.boundaryMargin=PreparationDraft.boundaryMargin
            settings.obstacleClearance=PreparationDraft.obstacleClearance
        }
        previewScene.rootNode.addChildNode(previewRoot)
        previewScene.rootNode.addChildNode(previewAnnotations)
        if !preparing { installRemoteCommands() }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object:nil, queue:.main) { [weak self] notification in
            guard let raw=notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue:raw) == .began else { return }
            Task { @MainActor in self?.audioInterrupted() }
        }
        refreshFiles()
        watchdog=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    deinit { watchdog?.invalidate() }
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
            suspendedGuide=nil; suspendedScanID=nil
            scanID=UUID(); mode = .scanning
            beginLog(source:"new-scan")
            guard logging != nil else {mode = .idle; return}
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
                if let route=loaded.manifest.route {
                    area=route.area; corners=route.area.corners.map { Optional($0) }
                    routePoints=route.points; obstacles=route.obstacles; settings=loaded.manifest.settings
                    if suspendedScanID == item.id, let suspendedGuide, suspendedGuide.route == route {
                        guide=suspendedGuide; guideState = .paused; guideMessage="C·착용 위치 재검증 후 명시적 재개"
                    } else { guide=RouteGuide(route:route,settings:settings) }
                    guideTargetIndex=guide?.targetIndex
                }
                mode = .restoring
                for part in loaded.meshes { meshes[part.id]=part }
                updateCounts(); redrawReferences(); rebuildMesh(saved:true)
                overlay.isHidden=true; referenceOverlay.isHidden=true
                beginLog(source:"restore")
                guard logging != nil else {mode = .idle; return}
                restoreStarted=now
                startSession(map:map)
                references="저장된 네 꼭짓점과 C · 실제 C를 다시 선택해 검증"
                status="복원 중 · 스캔했던 주변과 기준점을 천천히 비추세요"
            } catch { if token==operation { errorMessage="불러오기 실패: "+error.localizedDescription } }
        }
    }
    private func reset() {
        cancelCountdown()
        stopLog()
        session?.delegate=nil; session?.pause()
        token=UUID(); gate=TrackingGate(); latest=nil
        if preparation != nil { preparation=PreparationDraft(); scanConfirmed=false; savedID=nil; pendingObjectWorld=[]; editingObjectID=nil }
        position=nil; heading=nil; ready=false; canVerify=false; canSave=false
        previewRoot.childNodes.forEach { $0.removeFromParentNode() }
        previewNodes.removeAll(); previewDirty.removeAll()
        previewAnnotations.childNodes.forEach {$0.removeFromParentNode()}
        previewRevision += 1
        meshes=[:]; nodes.values.forEach {$0.removeFromParentNode()}; nodes=[:]
        referenceOverlay.childNodes.forEach {$0.removeFromParentNode()}
        cornerAnchors.removeAll()
        overlay.isHidden = !showMesh; referenceOverlay.isHidden=false
        manifest=nil; origin=nil; front=nil; checkpoint=nil; stage=nil; area=nil
        corners=Array(repeating:nil,count:4); routePoints=[]; obstacles=[]; obstacleDraft=[]; routeConflicts=[]
        guide=nil; guideState = .idle; guideTargetIndex=nil; autoResumePending=false; speech.stopSpeaking(at:.immediate); clearNowPlaying()
        recordOn=false; lastErrorMeters=nil; references="앞왼쪽 → 앞오른쪽 → 뒤오른쪽 → 뒤왼쪽 → C"
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
                referenceAnchorsPresent(sample) && !meshes.isEmpty && stage != nil && routeIsValid
            if let stage, ready {
                position=stagePosition(sample.world)
                heading=stage.heading(cameraForward:sample.forward)
                if heading == nil, recordOn, var guide, guide.state == .guiding {
                    guide.pauseForUnclearHeading()
                    self.guide=guide; guideState=guide.state; autoResumePending=true
                    speech.stopSpeaking(at:.immediate); updateNowPlaying(active:false)
                    guideMessage="카메라가 거의 바닥·천장을 향함 · 렌즈를 전방으로 고정하면 자동 재개"
                    let forward=sample.forward
                    let length=sqrt(forward.x*forward.x+forward.y*forward.y+forward.z*forward.z)
                    let horizontalRatio=length > 0 ? hypot(forward.x,forward.z)/length : 0
                    event("guide_paused",detail:String(format:"unclearHeading:p%d:horizontalRatio=%.3f",guide.targetIndex,horizontalRatio))
                }
                if recordOn, let position, let heading, var guide {
                    let floor=FloorPoint(position.x,position.y)
                    if guide.state == .guiding {
                        let previousTarget=guide.targetIndex
                        let update=guide.observe(time:sample.time,position:floor,headingDegrees:heading,trackingValid:ready)
                        self.guide=guide; guideState=update.state; guideTargetIndex=update.targetIndex
                        if update.targetIndex != previousTarget {
                            event("guide_target_advanced",detail:"p\(previousTarget)→p\(update.targetIndex)/p\(routePoints.count-1)")
                        }
                        if let spoken=update.announcement { announce(spoken); event("guide_announcement",detail:spoken,position:position,heading:heading) }
                        if update.state == .completed { updateNowPlaying(active:false); event("guide_complete",detail:"p\(update.targetIndex)") }
                        if update.state == .paused {
                            speech.stopSpeaking(at:.immediate); updateNowPlaying(active:false)
                            autoResumePending=guide.canAutomaticallyRecover
                            guideMessage=autoResumePending
                                ? "위치 확인 중 · 무대 안쪽에서 1초 안정되면 자동 재개"
                                : "위치·추적을 확인한 뒤 명시적 재개"
                            event("guide_paused",detail:"\(guide.pauseReason.map { String(describing:$0) } ?? "unknown")")
                        }
                    } else if guide.state == .paused && autoResumePending {
                        if guide.observeAutomaticRecovery(time:sample.time,position:floor,headingDegrees:heading,trackingValid:ready) {
                            self.guide=guide; guideState=guide.state; autoResumePending=false
                            updateNowPlaying(active:true); guideMessage="p\(guide.targetIndex) 안내 재개"
                            event("guide_auto_resumed",detail:"p\(guide.targetIndex)")
                        } else { self.guide=guide }
                    }
                }
            } else { position=nil; heading=nil }
            if mode == .restoring {
                let candidate=sample.normal && referenceAnchorsPresent(sample)
                overlay.isHidden = !candidate || !showMesh; referenceOverlay.isHidden = !candidate
                if !ready { status=canVerify ? "복원 후보 확보 · 실제 C를 다시 선택해 검증하세요" : "공간 복원 중 · 기준 앵커와 안정된 추적을 기다립니다" }
            }
        }
        if sample.time-lastPoseLog>=0.05 {
            lastPoseLog=sample.time
            let raw=sample.world.valid ? stagePosition(sample.world) : nil
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
    private func stagePosition(_ world: Point3) -> Point3? {
        if let area {
            let floor=area.floor(world)
            return Point3(floor.x,floor.y,world.y-area.floorHeight)
        }
        return stage?.position(world)
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
    private var routeIsValid: Bool {
        if let preparation { return preparation.errors.isEmpty }
        guard let area, routePoints.count >= 2, checkpoint != nil,
              let route=try? StageRoute(area:area,points:routePoints,obstacles:obstacles) else { return false }
        return route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty
    }
    private func updateRouteStatus() {
        if let preparation { routeConflicts=preparation.errors; canSave=false; redrawReferences(); return }
        guard let area, routePoints.count >= 2 else {routeConflicts=[]; canSave=false; redrawReferences(); return}
        do {
            let route=try StageRoute(area:area,points:routePoints,obstacles:obstacles)
            routeConflicts=route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance)
        } catch { routeConflicts=[error.localizedDescription] }
        canSave=false
        redrawReferences()
    }
    func captureCorner(_ index: Int) {
        guard mode == .scanning, corners.indices.contains(index), !busy else { return }
        var changed=false
        do {
            let p=try centerFloorPoint()
            var selected=corners
            selected[index]=p
            if let first=selected[0], let second=selected[1] {
                _ = try FrontEdgeGuide(frontLeft:first,frontRight:second)
            }
            corners=selected; changed=true
            area=nil; stage=nil; origin=nil; front=nil; checkpoint=nil
            routePoints=[]; obstacles=[]; obstacleDraft=[]; removeReferenceAnchors()
            addCornerAnchors()
            if corners.allSatisfy({$0 != nil}) {
                let completed=try StageArea(corners:corners.compactMap {$0})
                area=completed
                let o=completed.world(FloorPoint(0,0))
                let f=completed.world(FloorPoint(0,-1))
                stage=try StageFrame(origin:o,front:f); origin=o; front=f
                addReference(o,suffix:".origin"); addReference(f,suffix:".front")
            }
            gate.invalidate(); invalidateWear("무대 변경 · C 확인 필요")
            if area != nil {status="무대 E 확정 · 스캔 공간 3D 보기에서 확인하세요"}
            else if corners[0] != nil && corners[1] != nil {
                status="E1·E2 고정 · 주황색 수직 점선을 따라 뒤쪽 꼭짓점을 찾으세요"
            } else {status="첫 꼭짓점 앵커 표시 · 앞오른쪽 점을 선택하세요"}
            references="네 꼭짓점 \(corners.compactMap {$0}.count)/4 · \(area == nil ? "직사각형 미확정" : "E 확정") · C —"
            updateRouteStatus(); event("corner_\(index)",position:p)
        } catch {
            if changed {
                canSave=false; gate.invalidate(); invalidateWear("무대 E 미확정 · 꼭짓점을 다시 선택하세요")
                references="네 꼭짓점 \(corners.compactMap {$0}.count)/4 · E 미확정 · C —"
                redrawReferences()
            }
            errorMessage=error.localizedDescription
        }
    }
    func captureRoutePoint(_ index: Int? = nil) {
        guard mode == .scanning, let area, !busy else { return }
        do {
            let p=try centerFloorPoint()
            guard abs(p.y-area.floorHeight)<=0.10 else { throw LabError.invalid("무대 바닥 평면 위의 점을 선택하세요.") }
            let q=area.floor(p)
            guard area.contains(q) else { throw LabError.invalid("무대 E 안의 점을 선택하세요.") }
            if let index { guard routePoints.indices.contains(index) else { return }; routePoints[index]=q }
            else { guard routePoints.count<6 else {throw LabError.invalid("p0과 목적지 p1~p5까지만 등록할 수 있습니다.")}; routePoints.append(q) }
            updateRouteStatus(); event("route_point",detail:"p\(index ?? routePoints.count-1)",position:p)
        } catch {errorMessage=error.localizedDescription}
    }
    func removeRoutePoint(_ index: Int) {
        guard mode == .scanning, routePoints.indices.contains(index) else {return}
        routePoints.remove(at:index); updateRouteStatus(); event("route_point_removed",detail:String(index))
    }
    func captureObstacleVertex(_ index: Int? = nil) {
        guard mode == .scanning, let area, !busy else {return}
        do {
            let p=try centerFloorPoint()
            guard abs(p.y-area.floorHeight)<=0.10, area.contains(area.floor(p)), (index != nil || obstacleDraft.count<8) else {
                throw LabError.invalid("무대 바닥의 장애물 꼭짓점 3~8개를 선택하세요.")
            }
            if let index {
                guard obstacleDraft.indices.contains(index) else {return}
                obstacleDraft[index]=area.floor(p)
            } else {obstacleDraft.append(area.floor(p))}
            redrawReferences()
        } catch {errorMessage=error.localizedDescription}
    }
    func removeLastObstacleVertex() {if !obstacleDraft.isEmpty {obstacleDraft.removeLast(); redrawReferences()}}
    func removeObstacleVertex(_ index: Int) {
        guard obstacleDraft.indices.contains(index) else {return}
        obstacleDraft.remove(at:index); redrawReferences()
    }
    func registerObstacle() {
        guard mode == .scanning else {return}
        do {
            let obstacle=try StageObstacle(name:obstacleName,kind:obstacleKind,passage:.prohibited,vertices:obstacleDraft)
            obstacles.append(obstacle); obstacleDraft=[]; updateRouteStatus()
            event("obstacle_registered",detail:"\(obstacle.kind.rawValue):\(obstacle.name):prohibited")
        } catch {errorMessage=error.localizedDescription}
    }
    func editObstacle(_ index: Int) {
        guard mode == .scanning, obstacles.indices.contains(index) else {return}
        let o=obstacles.remove(at:index); obstacleName=o.name; obstacleKind=o.kind; obstacleDraft=o.vertices
        updateRouteStatus(); event("obstacle_edit",detail:o.id.uuidString)
    }
    func removeObstacle(_ index: Int) {
        guard mode == .scanning, obstacles.indices.contains(index) else {return}
        let o=obstacles.remove(at:index); updateRouteStatus(); event("obstacle_removed",detail:o.id.uuidString)
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
                guard let area, let origin, let front else { throw LabError.invalid("O와 F를 먼저 선택하세요.") }
                guard area.corners.allSatisfy({point.distance(to:$0)>=0.5}),
                      point.distance(to:origin)>=0.5, point.distance(to:front)>=0.5,
                      abs(point.y-origin.y)<=0.15 else { throw LabError.invalid("C는 O·F에서 0.5m 이상 떨어진 같은 바닥점이어야 합니다.") }
                checkpoint=point; removeReference(suffix:".check"); addReference(point,suffix:".check")
            }
            gate.invalidate(); invalidateWear("기준 변경 · C 확인 필요")
            references="네 꼭짓점 \(corners.compactMap {$0}.count)/4 · E \(area == nil ? "—" : "✓") · C \(checkpoint == nil ? "—" : "✓")"
            redrawReferences(); event("reference_"+kind,position:point)
        } catch { errorMessage=error.localizedDescription }
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
    private func removeReference(suffix: String) {
        session?.currentFrame?.anchors.filter {$0.name==referencePrefix+suffix}.forEach {session?.remove(anchor:$0)}
    }
    private func addReference(_ p: Point3, suffix: String) {
        var t=matrix_identity_float4x4; t.columns.3=SIMD4(Float(p.x),Float(p.y),Float(p.z),1)
        session?.add(anchor:ARAnchor(name:referencePrefix+suffix,transform:t))
    }
    private func redrawReferences() {
        referenceOverlay.childNodes.forEach {$0.removeFromParentNode()}
        previewAnnotations.childNodes.forEach {$0.removeFromParentNode()}
        let referenceLabels: [(String,Point3?)] = preparation == nil ? [("O",origin),("F",front),("C",checkpoint)] : [("확인점",checkpoint)]
        for (label,p) in referenceLabels {
            guard let p else { continue }
            let node=SCNNode(geometry:SCNSphere(radius:0.04)); node.geometry?.firstMaterial?.diffuse.contents=UIColor.systemYellow
            node.position=SCNVector3(Float(p.x),Float(p.y)+0.04,Float(p.z)); referenceOverlay.addChildNode(node)
            let text=SCNText(string:label,extrusionDepth:0); text.font = .boldSystemFont(ofSize:10)
            let n=SCNNode(geometry:text); n.scale=SCNVector3(0.015,0.015,0.015)
            n.position=SCNVector3(Float(p.x),Float(p.y)+0.12,Float(p.z)); n.constraints=[SCNBillboardConstraint()]
            referenceOverlay.addChildNode(n)
        }
        for (i,p) in corners.enumerated() {
            guard let p else {continue}; cornerMarker(p,label:preparation == nil ? "E\(i+1)" : ["앞 왼쪽","앞 오른쪽","뒤 오른쪽","뒤 왼쪽"][i])
        }
        if preparation != nil {
            let order=PreparationDraft.captureOrder
            for i in 1..<4 {
                if let a=corners[order[i-1]], let b=corners[order[i]] {line(a,b,color:.systemGreen)}
            }
        }
        if area == nil, let first=corners[0], let second=corners[1],
           let guide=try? FrontEdgeGuide(frontLeft:first,frontRight:second) {
            line(guide.leftStart,guide.rightStart,color:.systemOrange)
            dashedGuide(guide.leftStart,guide.leftEnd)
            dashedGuide(guide.rightStart,guide.rightEnd)
        }
        if let area {
            let edge=[FloorPoint(0,0),FloorPoint(area.width,0),FloorPoint(area.width,area.depth),FloorPoint(0,area.depth)]
            for i in 0..<4 { line(area.world(edge[i]),area.world(edge[(i+1)%4]),color:.systemCyan) }
            for (i,p) in routePoints.enumerated() {
                let label=preparation == nil ? "p\(i)" : (i == 0 ? "출발" : (preparation?.routeFinished == true && i == routePoints.count-1 ? "도착" : "P\(i)"))
                marker(area.world(p),label:label,color:.systemGreen)
                if i>0 {line(area.world(routePoints[i-1]),area.world(p),color:.systemGreen)}
            }
            for o in obstacles {
                for i in o.vertices.indices {line(area.world(o.vertices[i]),area.world(o.vertices[(i+1)%o.vertices.count]),color:.systemRed)}
            }
            for p in obstacleDraft {marker(area.world(p),label:"물체",color:.systemOrange)}
        }
    }
    private func cornerMarker(_ p: Point3,label: String) {
        let group=SCNNode()
        group.name="stage-corner-"+label
        group.position=SCNVector3(Float(p.x),Float(p.y),Float(p.z))
        let ring=SCNNode(geometry:SCNTorus(ringRadius:0.08,pipeRadius:0.009))
        ring.geometry?.firstMaterial?.diffuse.contents=UIColor.systemCyan
        ring.position.y=0.012
        group.addChildNode(ring)
        let stem=SCNNode(geometry:SCNCylinder(radius:0.005,height:0.14))
        stem.geometry?.firstMaterial?.diffuse.contents=UIColor.systemCyan
        stem.position.y=0.07
        group.addChildNode(stem)
        let pin=SCNNode(geometry:SCNSphere(radius:0.04))
        pin.geometry?.firstMaterial?.diffuse.contents=UIColor.systemYellow
        pin.position.y=0.15
        group.addChildNode(pin)
        let text=SCNText(string:label,extrusionDepth:0)
        text.font = .boldSystemFont(ofSize:12)
        text.firstMaterial?.diffuse.contents=UIColor.white
        let tag=SCNNode(geometry:text)
        tag.scale=SCNVector3(0.018,0.018,0.018)
        tag.position=SCNVector3(0,0.24,0)
        tag.constraints=[SCNBillboardConstraint()]
        group.addChildNode(tag)
        referenceOverlay.addChildNode(group)
        if previewVisible {previewAnnotations.addChildNode(group.clone())}
    }
    private func dashedGuide(_ a: Point3,_ b: Point3) {
        let length=hypot(b.x-a.x,b.z-a.z)
        guard length > 0 else {return}
        var start=0.0
        while start < length {
            let end=min(start+0.30,length)
            let u=start/length, v=end/length
            let from=Point3(a.x+(b.x-a.x)*u,a.y,a.z+(b.z-a.z)*u)
            let to=Point3(a.x+(b.x-a.x)*v,a.y,a.z+(b.z-a.z)*v)
            line(from,to,color:.systemOrange)
            start += 0.55
        }
    }
    private func marker(_ p: Point3,label: String,color: UIColor) {
        let n=SCNNode(geometry:SCNSphere(radius:0.05)); n.geometry?.firstMaterial?.diffuse.contents=color
        n.position=SCNVector3(Float(p.x),Float(p.y)+0.05,Float(p.z))
        referenceOverlay.addChildNode(n); if previewVisible {previewAnnotations.addChildNode(n.clone())}
        let text=SCNText(string:label,extrusionDepth:0); text.font = .boldSystemFont(ofSize:10)
        let t=SCNNode(geometry:text); t.scale=SCNVector3(0.015,0.015,0.015)
        t.position=SCNVector3(Float(p.x),Float(p.y)+0.14,Float(p.z)); t.constraints=[SCNBillboardConstraint()]
        referenceOverlay.addChildNode(t); if previewVisible {previewAnnotations.addChildNode(t.clone())}
    }
    private func line(_ a: Point3,_ b: Point3,color: UIColor) {
        let u=SIMD3<Float>(Float(a.x),Float(a.y)+0.025,Float(a.z))
        let v=SIMD3<Float>(Float(b.x),Float(b.y)+0.025,Float(b.z))
        let d=v-u; guard simd_length(d)>0.001 else {return}
        let n=SCNNode(geometry:SCNCylinder(radius:0.012,height:CGFloat(simd_length(d))))
        n.geometry?.firstMaterial?.diffuse.contents=color
        n.simdPosition=(u+v)/2
        n.simdOrientation=simd_quatf(from:SIMD3<Float>(0,1,0),to:simd_normalize(d))
        referenceOverlay.addChildNode(n); if previewVisible {previewAnnotations.addChildNode(n.clone())}
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
        guard canSave, !busy, let session, let stage, let checkpoint, let area else { return }
        let route: StageRoute
        do { route = try preparation?.stageRoute() ?? StageRoute(area:area,points:routePoints,obstacles:obstacles) }
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
                let id=self.scanID, name=self.scanName.trimmingCharacters(in:.whitespacesAndNewlines)
                guard !name.isEmpty else {self.busy=false; self.errorMessage="스캔 이름을 입력하세요."; return}
                guard [".origin",".front",".check"].allSatisfy({suffix in map.anchors.contains {$0.name==self.referencePrefix+suffix}}) else {
                    self.busy=false; self.errorMessage="공간 지도에 기준점이 아직 포함되지 않았습니다. 다시 저장하세요."; return
                }
                self.session?.pause(); self.gate.invalidate(); self.ready=false
                self.cancelCountdown(); self.position=nil; self.heading=nil; self.recordOn=false
                do {
                    let data=try NSKeyedArchiver.archivedData(withRootObject:map,requiringSecureCoding:true)
                    self.archiveWriteInProgress=true
                    let result=try await self.store.save(id:id,name:name,frame:stage,checkpoint:checkpoint,
                        worldMap:data,meshes:parts,device:UIDevice.current.model+" / "+UIDevice.current.systemVersion,
                        appVersion:Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                        route:route,settings:self.settings)
                    guard self.token==operation else { return }
                    self.mode = .saved; self.savedID=result.id; self.manifest=result; self.status="저장 완료 · 앱 재실행 후 저장 공간을 불러와 C를 검증하세요"
                    self.event("scan_saved",detail:result.id.uuidString); self.stopLog(); self.refreshFiles()
                } catch {
                    guard self.token==operation else { return }
                    self.errorMessage="저장 실패: "+error.localizedDescription; self.status="입력은 유지됩니다. 다시 저장해주세요."
                    if let configuration=self.session?.configuration, self.active { self.session?.run(configuration) }
                }
                self.archiveWriteInProgress=false; self.busy=false; UIApplication.shared.isIdleTimerDisabled = self.mode == .scanning
            }
        }
    }
    func confirmSpace() { if canConfirmScan { scanConfirmed=true } }
    func resumePreparation() {
        guard vertexCount<=800_000 else {errorMessage="스캔 범위가 너무 큽니다. 준비를 종료하고 더 작은 영역으로 다시 스캔해주세요."; return}
        guard active, mode == .scanning, let configuration=session?.configuration else { return }
        latest=nil; preparationInterrupted=false; session?.run(configuration)
        status="주변을 천천히 비추며 추적을 다시 확인해주세요."
    }
    private func synchronizePreparation() {
        guard let draft=preparation else {return}
        corners=draft.corners; checkpoint=draft.checkpoint; area=draft.area
        removeReferenceAnchors(); addCornerAnchors()
        if let area {
            origin=area.world(FloorPoint(0,0)); front=area.world(FloorPoint(0,-1))
            stage=try? StageFrame(origin:origin!,front:front!)
            addReference(origin!,suffix:".origin"); addReference(front!,suffix:".front")
            routePoints=draft.route.map(area.floor)
            obstacles=draft.objects.compactMap {try? $0.projected(in:area)}
            obstacleDraft=pendingObjectWorld.map(area.floor)
        } else { origin=nil; front=nil; stage=nil; routePoints=[]; obstacles=[]; obstacleDraft=[] }
        if let checkpoint {addReference(checkpoint,suffix:".check")}
        routeConflicts=draft.errors; canSave=false; redrawReferences()
    }
    func prepareCorner(_ index: Int) {
        guard canPlacePoint, var draft=preparation, draft.corners.indices.contains(index) else {return}
        do {draft.corners[index]=try centerFloorPoint(); preparation=draft; synchronizePreparation()}
        catch {errorMessage=error.localizedDescription}
    }
    func undoPreparationCorner(_ index: Int) {
        guard !busy, var draft=preparation, draft.corners.indices.contains(index) else {return}
        draft.corners[index]=nil; preparation=draft; synchronizePreparation()
    }
    func prepareRoutePoint(destination: Bool = false) {
        guard canPlacePoint, var draft=preparation else {return}
        do {try draft.addRoutePoint(centerFloorPoint(),asDestination:destination); preparation=draft; synchronizePreparation()}
        catch {errorMessage=error.localizedDescription}
    }
    func undoPreparationRoute() {
        guard !busy, var draft=preparation else {return}
        draft.removeLastRoutePoint(); preparation=draft; synchronizePreparation()
    }
    func prepareCheckpoint() {
        guard canPlacePoint, var draft=preparation else {return}
        do {
            draft.checkpoint=try centerFloorPoint()
            guard draft.checkpointErrors.isEmpty else {throw LabError.invalid(draft.checkpointErrors.joined(separator:"\n"))}
            preparation=draft; synchronizePreparation()
        } catch {errorMessage=error.localizedDescription}
    }
    func beginPreparationObject(_ id: UUID? = nil) {
        guard !busy else {return}
        editingObjectID=id
        if let object=preparation?.objects.first(where:{$0.id==id}) {
            obstacleName=object.name; obstacleKind=object.kind; pendingObjectWorld=object.vertices
        } else {obstacleName="장애물"; obstacleKind = .other; pendingObjectWorld=[]}
        synchronizePreparation()
    }
    func prepareObjectVertex() {
        guard canPlacePoint, let area=preparation?.area else {return}
        do {
            let p=try centerFloorPoint()
            guard pendingObjectWorld.count<8, abs(p.y-area.floorHeight)<=0.10, area.contains(area.floor(p)) else {throw LabError.invalid("무대 안 바닥에서 기물의 둘레를 3~8점으로 지정해주세요.")}
            pendingObjectWorld.append(p); synchronizePreparation()
        } catch {errorMessage=error.localizedDescription}
    }
    func undoPreparationObjectVertex() {
        guard !busy, !pendingObjectWorld.isEmpty else {return}
        pendingObjectWorld.removeLast(); synchronizePreparation()
    }
    @discardableResult func commitPreparationObject() -> Bool {
        guard !busy, var draft=preparation, let area=draft.area else {return false}
        do {
            let item=WorldObstacle(id:editingObjectID ?? UUID(),name:obstacleName.trimmingCharacters(in:.whitespacesAndNewlines),kind:obstacleKind,vertices:pendingObjectWorld)
            let projected=try item.projected(in:area)
            guard projected.vertices.allSatisfy({area.contains($0)}) else {throw LabError.invalid("기물을 무대 안에 지정해주세요.")}
            if let i=draft.objects.firstIndex(where:{$0.id==item.id}) {draft.objects[i]=item} else {draft.objects.append(item)}
            preparation=draft; cancelPreparationObject(); return true
        } catch {errorMessage=error.localizedDescription; return false}
    }
    func cancelPreparationObject() {pendingObjectWorld=[]; editingObjectID=nil; synchronizePreparation()}
    func deletePreparationObject(_ id: UUID) {
        guard !busy else {return}
        preparation?.objects.removeAll {$0.id==id}; synchronizePreparation()
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
            guard self.prepareAudio() else {return}
            self.recordOn=true; self.event("wear_start",detail:"rear camera outward, portrait")
            self.status="착용 추적 기록 중 · 카메라 위치의 추정값이며 발 위치가 아닙니다"
            UIAccessibility.post(notification:.announcement,argument:"착용 기록 시작")
        }
    }
    var canGuide: Bool {
        guard ready, recordOn, let position, let heading, let guide else {return false}
        if guide.state == .idle {return guide.ready(position:FloorPoint(position.x,position.y),headingDegrees:heading,trackingValid:true)}
        return guide.state == .paused && routeConflicts.isEmpty
    }
    func startGuide() {
        guard canGuide, let position, let heading, var guide else {
            guideMessage="p0 근접·무대 정면·C 검증·경로 안전 상태를 확인하세요"; return
        }
        let floor=FloorPoint(position.x,position.y)
        let success = guide.state == .idle
            ? guide.start(position:floor,headingDegrees:heading,trackingValid:true)
            : guide.resume(position:floor,trackingValid:true)
        guard success else {return}
        self.guide=guide; guideState=guide.state; guideTargetIndex=guide.targetIndex
        autoResumePending=false; guideMessage="p\(guide.targetIndex) 안내 중"
        updateNowPlaying(active:true); event("guide_start",detail:"p\(guide.targetIndex)")
        announce("안내를 시작합니다.")
    }
    func pauseGuide(_ reason: String = "사용자 일시정지") {
        autoResumePending=false
        guard var guide, guide.state == .guiding else {return}
        guide.pause(); self.guide=guide; guideState = .paused; guideMessage=reason
        speech.stopSpeaking(at:.immediate); updateNowPlaying(active:false); event("guide_paused",detail:reason)
    }
    private func announce(_ text: String) {
        guideMessage=text
        speech.stopSpeaking(at:.immediate)
        let utterance=AVSpeechUtterance(string:text); utterance.voice=AVSpeechSynthesisVoice(language:"ko-KR"); utterance.rate=0.48
        speech.speak(utterance)
    }
    private func prepareAudio() -> Bool {
        do {
            let audio=AVAudioSession.sharedInstance()
            try audio.setCategory(.playback,mode:.spokenAudio,options:[.mixWithOthers])
            try audio.setActive(true)
            updateNowPlaying(active:false); return true
        } catch {errorMessage="오디오 준비 실패: "+error.localizedDescription; return false}
    }
    private func updateNowPlaying(active: Bool) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo=[
            MPMediaItemPropertyTitle:"PoC4 무대 안내",
            MPMediaItemPropertyArtist:stageLabel,
            MPNowPlayingInfoPropertyPlaybackRate:active ? 1.0 : 0.0
        ]
    }
    private func clearNowPlaying() {
        guard preparation == nil else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo=nil
        try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation)
    }
    private func installRemoteCommands() {
        let commands=MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled=true; commands.pauseCommand.isEnabled=true
        commands.togglePlayPauseCommand.isEnabled=true
        remoteTargets.append(commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.event("remote_command",detail:"play"); self?.startGuide() }; return .success
        })
        remoteTargets.append(commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.event("remote_command",detail:"pause"); self?.pauseGuide("에어팟/원격 명령 일시정지") }; return .success
        })
        remoteTargets.append(commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else {return}
                self.event("remote_command",detail:"toggle")
                if self.guideState == .guiding {self.pauseGuide("에어팟/원격 명령 일시정지")}
                else {self.startGuide()}
            }; return .success
        })
    }
    private func audioInterrupted() {
        pauseGuide("오디오 중단 · C와 착용 위치 재검증 후 명시적 재개")
        gate.invalidate(); invalidateWear("오디오 중단 · C 재검증 필요")
        event("audio_interrupted")
    }
    private func cancelCountdown() {wearTask?.cancel(); wearTask=nil; wearCountdown=nil}
    func stopWear() {pauseGuide("착용 종료"); clearNowPlaying(); cancelCountdown(); recordOn=false; event("wear_stop"); status="착용 구간 종료 · 관측 로그는 계속 기록"}
    func addNote() {
        let text=note.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        event("manual_note",detail:text); note=""
    }
    private func invalidateWear(_ message: String) {
        autoResumePending=false
        pauseGuide(message); cancelCountdown()
        if recordOn { event("wear_invalidated",detail:message) }
        recordOn=false; ready=false; position=nil; heading=nil; status=message
    }
    func interrupt(_ message: String, token incoming: UUID) {
        guard incoming==token else { return }
        if preparation != nil, mode == .scanning, message != "측정 종료" {
            session?.pause(); preparationInterrupted=true; canSave=false
            if !archiveWriteInProgress {saveAttempt=UUID(); busy=false}
            latest=nil; status="추적이 중단됐습니다. 같은 공간에서 추적을 다시 시작해주세요."
            return
        }
        pauseGuide(message)
        if message != "측정 종료", let guide, guide.state == .paused {
            suspendedGuide=guide; suspendedScanID=scanID
        } else {suspendedGuide=nil; suspendedScanID=nil}
        event("session_interrupted",detail:message)
        session?.pause(); session?.delegate=nil; token=UUID(); busy=false; gate.invalidate()
        canSave=false; canVerify=false; mode = .idle; restoreStarted=nil; clearNowPlaying()
        invalidateWear(message); stopLog(); UIApplication.shared.isIdleTimerDisabled=false
    }
    func setActive(_ value: Bool) {
        active=value
        if preparation != nil {
            if !value {
                session?.pause(); latest=nil; canSave=false; preparationInterrupted=true
                if !archiveWriteInProgress {saveAttempt=UUID(); busy=false}
            }
            return
        }
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
                "arrivalRadiusMeters":String(settings.arrivalRadius),"arrivalDwellSeconds":String(settings.arrivalDwell),
                "startRadiusMeters":String(settings.startRadius),"frontToleranceDegrees":String(settings.frontToleranceDegrees),
                "coordinates":"X audience-right from front-left; Y backstage; Z up; heading clockwise from stage-front",
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
            coordinateSpace:(name.hasPrefix("reference_") || name.hasPrefix("corner_") || name=="route_point" || name=="checkpoint") ? "ar-world" : "stage",
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
