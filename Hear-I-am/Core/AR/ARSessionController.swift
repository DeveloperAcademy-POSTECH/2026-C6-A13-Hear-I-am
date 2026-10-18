import ARKit
import AVFoundation
import Combine
import HearIAmCore

/// Owns one ARKit world-tracking session for stage preparation or portrait guidance.
/// Each new session gets a fresh token; callbacks carrying an older token are ignored.
/// State is split across extension files by concern, so stored properties are module-internal.
@MainActor
final class ARSessionController: ObservableObject {
    enum Purpose { case preparation, guidance }
    enum Mode: String { case idle, scanning, restoring, saved }

    @Published var mode: Mode = .idle
    @Published var status="새 스캔 또는 저장 공간을 선택하세요"
    @Published var tracking="대기"
    @Published var mapping="대기"
    @Published var meshCount=0
    @Published var vertexCount=0
    @Published var position: Point3?
    @Published var heading: Double?
    @Published var ready=false
    @Published var canVerify=false
    @Published var canSave=false
    @Published var busy=false
    @Published var savedID: UUID?
    @Published var preparationInterrupted=false
    @Published var errorMessage: String?
    @Published var showMesh=true { didSet { renderer.meshLayer.isHidden = !showMesh } }

    let purpose: Purpose
    let checkpointTolerance=0.15 // Experiment threshold, NOT an accuracy guarantee.
    let supportsMesh=ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    let supported=ARWorldTrackingConfiguration.isSupported
    let store: ScanStore
    let renderer=ARSceneRenderer()
    let logger: TrialLogger
    weak var view: ARSCNView?
    var settings=GuideSettings()

    // Session
    var session: ARSession?
    var bridge: SessionBridge?
    var token=UUID()
    var scanID=UUID()
    var active=true
    var gate=TrackingGate()
    var latest: CameraSample?
    var lastUI = -Double.infinity
    var lastPoseLog = -Double.infinity
    var restoreStarted: Double?
    var guidancePoseTime: Double?
    private var watchdog: Timer?
    private let cameraQueue=DispatchQueue(label:"HearIAm.AR",qos:.userInitiated)

    // Saving
    var saveAttempt=UUID()
    var archiveWriteInProgress=false
    var manifest: ScanManifest?
    var meshes: [UUID:MeshSnapshot]=[:]

    // Stage geometry in AR world (corners, checkpoint) and stage floor metres (route, obstacles).
    var cornerAnchors: [Int: ARAnchor] = [:]
    var corners: [Point3?] = Array(repeating:nil,count:4)
    var origin: Point3?
    var front: Point3?
    var checkpoint: Point3?
    var stage: StageFrame?
    var area: StageArea?
    var routePoints: [FloorPoint] = []
    var obstacles: [StageObstacle] = []
    var pendingObject: [FloorPoint] = []
    /// The preparation draft last applied; saving builds the route from it.
    var preparedDraft: PreparationDraft?
    /// Called whenever a new session replaces the previous one, so owners can clear their own input.
    var onReset: (() -> Void)?
    private var visibleGuidanceTarget: Int?
    private var guidanceCompleted=false

    var now: Double { ProcessInfo.processInfo.systemUptime }
    var referencePrefix: String { "PoC4.reference."+scanID.uuidString }
    var canConfirmScan: Bool { mode == .scanning && !busy && (!supportsMesh || !meshes.isEmpty) && latest?.mapped == true && latest?.normal == true && now-(latest?.time ?? 0) < 0.5 }
    var canPlacePoint: Bool { mode == .scanning && !busy && !preparationInterrupted && latest?.normal == true && now-(latest?.time ?? 0) < 0.5 }

    init(purpose: Purpose) {
        self.purpose=purpose
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        store=ScanStore(root:docs.appendingPathComponent("Scans",isDirectory:true))
        logger=TrialLogger(directory:docs.appendingPathComponent("Trials",isDirectory:true))
        if purpose == .preparation {
            settings.boundaryMargin=PreparationDraft.boundaryMargin
            settings.obstacleClearance=PreparationDraft.obstacleClearance
            NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object:nil, queue:.main) { [weak self] notification in
                guard let raw=notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      AVAudioSession.InterruptionType(rawValue:raw) == .began else { return }
                Task { @MainActor in self?.audioInterrupted() }
            }
        }
        watchdog=Timer.scheduledTimer(withTimeInterval:0.2,repeats:true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }
    deinit { watchdog?.invalidate() }

    func attach(_ arView: ARSCNView) {
        view=arView; arView.scene=SCNScene()
        renderer.attach(to:arView.scene)
        if let session { arView.session=session }
    }
    func setGuidanceTarget(_ index: Int, completed: Bool = false) {
        guard visibleGuidanceTarget != index || guidanceCompleted != completed else { return }
        visibleGuidanceTarget=index;guidanceCompleted=completed;redrawReferences()
    }
    func redrawReferences() {
        renderer.draw(.init(
            style:purpose == .preparation ? .preparation(routeFinished:preparedDraft?.routeFinished == true)
                                          : .guidance(target:visibleGuidanceTarget,completed:guidanceCompleted),
            checkpoint:checkpoint,corners:corners,area:area,routePoints:routePoints,obstacles:obstacles,pendingObject:pendingObject))
    }

    func startSession(map: ARWorldMap?) {
        let config=ARWorldTrackingConfiguration()
        config.worldAlignment = .gravity; config.planeDetection=[.horizontal]
        // Mesh creation only in pre-scan when LiDAR is available. During restoration use the saved snapshot.
        if mode == .scanning && supportsMesh { config.sceneReconstruction = .mesh }
        config.initialWorldMap=map
        let newSession=ARSession()
        bridge=SessionBridge(controller:self,token:token)
        newSession.delegate=bridge; newSession.delegateQueue=cameraQueue
        session=newSession; view?.session=newSession
        newSession.run(config,options:[.resetTracking,.removeExistingAnchors])
        UIApplication.shared.isIdleTimerDisabled=true
    }
    func reset() {
        stopLog()
        session?.delegate=nil; session?.pause()
        token=UUID(); gate=TrackingGate(); latest=nil
        if purpose == .preparation { preparedDraft=PreparationDraft(); savedID=nil; onReset?() }
        position=nil; heading=nil; guidancePoseTime=nil; ready=false; canVerify=false; canSave=false
        meshes=[:]; renderer.clearMeshes()
        renderer.clearAnnotations()
        cornerAnchors.removeAll()
        renderer.meshLayer.isHidden = !showMesh; renderer.referenceLayer.isHidden=false
        manifest=nil; origin=nil; front=nil; checkpoint=nil; stage=nil; area=nil
        corners=Array(repeating:nil,count:4); routePoints=[]; obstacles=[]; pendingObject=[]
        restoreStarted=nil; updateCounts(); lastUI = -.infinity; lastPoseLog = -.infinity
    }
}
