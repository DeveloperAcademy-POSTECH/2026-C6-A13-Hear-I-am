import SwiftUI
import Combine
import HearIAmCore

/// Landscape stage preparation: scan → boundary → objects → route → checkpoint → review.
/// Input lives in `draft` in AR world coordinates; every change is mirrored into the AR session.
/// Step-specific actions live in the PreparationViewModel+<Step> files.
@MainActor
final class PreparationViewModel: ObservableObject {
    let session=ARSessionController(purpose:.preparation)

    // Input
    @Published var draft=PreparationDraft()
    @Published var scanConfirmed=false
    @Published var pendingObjectWorld: [Point3] = []
    @Published var obstacleName="기물"
    /// Changing the kind renames an object that still carries a default name, so the name always tells
    /// the kind (field test 10/17: an object named "장애물" was saved as stairs and never warned).
    @Published var obstacleKind: ObstacleKind = .box {
        didSet {
            if ObstacleKind.allCases.map(\.defaultName).contains(obstacleName) { obstacleName=obstacleKind.defaultName }
            if !applyingSuggestion { kindChosen=true }
        }
    }
    /// Height read from the scan mesh inside the drafted outline; nil until 3 points or when too little mesh.
    @Published var facingEdge: Int? = nil
    @Published var objectHeight: ObjectHeight?
    /// Once the operator picks a kind, the height no longer changes it.
    var kindChosen=false
    var applyingSuggestion=false
    @Published var objectModel: ObjectAppearance.Model = .generic
    @Published var objectHeading=0.0
    @Published var showingPhotos=false
    @Published var scanName="무대 스캔"
    @Published var selectedPlan: PerformancePlan?
    @Published private var showObjectReference=true
    @Published private var showRouteReference=true
    var canShowPlanReference: Bool { selectedPlan != nil && (step == .objects || step == .route) }
    var showPlanReference: Bool {
        get { step == .objects ? showObjectReference : showRouteReference }
        set {
            if step == .objects { showObjectReference=newValue } else { showRouteReference=newValue }
            synchronizeReference()
        }
    }
    var visiblePlanReference: StagePlanReference? {
        guard canShowPlanReference, showPlanReference, let selectedPlan else { return nil }
        return try? draft.reference(for:selectedPlan)
    }
    private func synchronizeReference() {
        session.planReference=visiblePlanReference
        session.redrawReferences()
    }
    @Published var choosingPlan=false
    var editingObjectID: UUID?

    // Screen state
    @Published var step: PreparationStep = .scan
    @Published var highest: PreparationStep = .scan
    /// The scan step's card waits for the system coaching (「Move iPhone to start」) to finish; `?` shows it any time.
    @Published var intro: Int? = nil {
        // The scan itself starts with the card's 「시작하기」, after the coaching and the card (11/02).
        didSet { if intro == nil, oldValue != nil, step == .scan { session.beginMeshScan() } }
    }
    @Published private(set) var scanIntroShown=false
    /// The opening 「iPhone을 움직이세요」 runs until the intro card shows (at most about 13 s, see `appear`);
    /// the controls behind it take no taps meanwhile (11/02).
    var openingCoaching: Bool { supported && step == .scan && !scanIntroShown }
    @Published var selectedRoutePoint: Int?
    @Published var selectedCorner: Int?
    /// The checkpoint the next + replaces, picked in the panel; nil fills the first empty one.
    @Published var selectedCheckpoint: Int?
    @Published var objectEditing=false
    @Published var confirmingRouteHeight=false
    var pendingRouteHeight: (point: Point3, destination: Bool, draft: PreparationDraft, token: UUID)?
    var routeHeightMessage=""
    @Published var review=false
    @Published var editingDangerZones=false
    @Published var guideCollapsed=false
    @Published var confirmingScan=false
    @Published var confirmingExit=false
    /// The more panel under the ⋯ button (452:12878).
    @Published var showingMore=false
    private var seen: Set<PreparationStep> = [.scan]
    private var sessionChanges: AnyCancellable?
    private var coachingChanges: AnyCancellable?

    init(initialPlan: PerformancePlan? = nil, initialName: String = "") {
        self.selectedPlan=initialPlan
        if !initialName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { self.scanName=initialName }
        else if let initialPlan { self.scanName=initialPlan.name }
        sessionChanges=session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        coachingChanges=session.$coachingActive.dropFirst().receive(on:DispatchQueue.main).sink { [weak self] active in
            guard let self, !active else { return }
            showScanIntroOnce()
        }
        if let preview=Self.layoutPreview, let s=PreparationStep(rawValue:preview) {
            step=s; highest = .checkpoint; scanConfirmed=s != .scan; scanIntroShown=true
            confirmingScan=ProcessInfo.processInfo.arguments.contains("--scan-confirm")
            showingMore=ProcessInfo.processInfo.arguments.contains("--scan-more")
            choosingPlan=ProcessInfo.processInfo.arguments.contains("--scan-plans")
        }
        session.onReset={ [weak self] in
            guard let self else { return }
            draft=PreparationDraft(); scanConfirmed=false; pendingObjectWorld=[]; editingObjectID=nil
        }
    }

    // Session state the screen reads
    var supported: Bool { session.supported || Self.layoutPreview != nil }
    #if DEBUG
    /// `--scan-layout <step>`: the scan screen's layout without LiDAR, for comparing with the design in the simulator.
    static let layoutPreview: Int? = {
        let args=ProcessInfo.processInfo.arguments
        guard let index=args.firstIndex(of:"--scan-layout"), args.indices.contains(index+1) else { return nil }
        return Int(args[index+1])
    }()
    #else
    static let layoutPreview: Int? = nil
    #endif
    var supportsMesh: Bool { session.supportsMesh }
    var busy: Bool { session.busy || session.photoCapturing }
    var interrupted: Bool { session.preparationInterrupted }
    var canPlacePoint: Bool { session.canPlacePoint && !session.photoCapturing }
    var meshCount: Int { session.meshCount }
    var mapping: String { session.mapping }
    var savedID: UUID? { session.savedID }
    var showMesh: Bool { get {session.showMesh} set {session.showMesh=newValue} }
    var errorMessage: String? { get {session.errorMessage} set {session.errorMessage=newValue} }

    var guide: PreparationGuide {
        PreparationGuide(step:step,draft:draft,nextCorner:nextCorner,objectEditing:objectEditing,pendingVertexCount:pendingObjectWorld.count)
    }
    var showsCrosshairHint: String? {
        if session.saveRecoveryPending, let message=saveRecoveryMessage { return message }
        if interrupted { return "추적 중단" }
        if let hit=aimHit { return hit.message }
        if let issue=aimEdgeIssue { return issue }
        if step == .scan { return supportsMesh ? "민트색 그물 = 스캔한 표면" : nil }
        return step == .route ? "바닥 또는 등록한 의자·계단 윗면을 선택하세요" : "십자선을 실제 바닥에 맞춰주세요"
    }
    /// Why the point under the crosshair cannot join the route, shown before it is placed (#38).
    var aimHit: ClearanceHit? {
        guard step == .route, !draft.routeFinished, let aim=session.aimPoint else { return nil }
        return draft.clearanceHit(adding:aim)
    }
    /// The point under the crosshair is too close to the stage edge or a danger zone (10/19).
    var aimEdgeIssue: String? {
        guard step == .route, !draft.routeFinished, let aim=session.aimPoint else { return nil }
        return draft.edgeIssue(adding:aim)
    }
    var aimBlocked: Bool { aimHit != nil || aimEdgeIssue != nil }

    // Lifecycle
    func appear() {
        session.showMesh=true
        guard session.supported else { return }
        session.meshHeld=true
        session.newScan()
        // 「Move iPhone to start」 opens every scan: held past the black transition for 3s at least, then until
        // tracking is normal (8s at most). Its deactivation brings the intro card.
        session.coachingForced=true
        Task { @MainActor [weak self] in
            let started=Date()
            try? await Task.sleep(for:.seconds(ScanTransition.rotation+ScanTransition.fade+3))
            // Hold on until the session has started and tracks normally, 10s at the most.
            while let self, session.tracking != "normal", Date().timeIntervalSince(started) < 10 {
                try? await Task.sleep(for:.seconds(0.25))
            }
            guard let self else { return }
            session.coachingForced=false
            try? await Task.sleep(for:.seconds(1.2))
            showScanIntroOnce()
        }
    }
    private func showScanIntroOnce() {
        guard step == .scan, !scanIntroShown, supported else { return }
        scanIntroShown=true; intro=0
    }
    /// The bottom-right + places the step's next point. The Camera Control button no longer does (#152).
    func plusPressed() {
        guard supported, intro == nil, !review, !choosingPlan, !editingDangerZones, !confirmingScan else { return }
        switch step {
        case .scan: break
        case .boundary: if let next=nextCorner { captureCorner(next) }
        case .objects: if objectEditing { addObjectVertex() } else if draft.area != nil { beginObject() }
        case .route: addRoutePoint()
        case .checkpoint:
            if let index=nextCheckpoint { placeCheckpoint(index); selectedCheckpoint=nil }
        }
    }
    /// The checkpoint the next + places: the one picked in the panel, else the first empty one.
    var nextCheckpoint: Int? {
        if let selectedCheckpoint, selectedCheckpoint == 0 || draft.checkpoint != nil { return selectedCheckpoint }
        return draft.checkpoint == nil ? 0 : (draft.secondCheckpoint == nil ? 1 : nil)
    }
    /// Whether the bottom-right + would place a point now (971:28541).
    var canPressPlus: Bool {
        guard canPlacePoint, !busy else { return false }
        switch step {
        case .scan: return false
        case .boundary: return nextCorner != nil
        case .objects: return draft.area != nil && (!objectEditing || pendingObjectWorld.count < 8)
        case .route: return draft.area != nil && !draft.routeFinished && draft.route.count < StageRoute.maxPointCount
        case .checkpoint: return draft.area != nil && nextCheckpoint != nil
        }
    }
    /// The panel's ↺: clears the current step's input.
    func resetStep() {
        guard !busy else { return }
        switch step {
        case .scan: break
        case .boundary:
            draft.corners=Array(repeating:nil,count:4); draft.dangerZones=[]; selectedCorner=nil; synchronize()
        case .objects:
            // While an object is drafted, ↺ drops the draft and leaves editing (the design has no cancel button).
            if objectEditing { cancelObject() }
            else { for object in draft.objects { deleteObject(object.id) } }
        case .route:
            cancelRouteHeight()
            while !draft.route.isEmpty { undoRoutePoint() }
            selectedRoutePoint=nil
        case .checkpoint:
            draft.checkpoint=nil; draft.secondCheckpoint=nil; selectedCheckpoint=nil; synchronize()
        }
    }
    /// Removes one checkpoint from the panel; the second moves up when the first goes.
    func removeCheckpoint(_ index: Int) {
        guard !busy else { return }
        if index == 0 { draft.checkpoint=draft.secondCheckpoint }
        draft.secondCheckpoint=nil
        synchronize()
    }
    func undoCheckpoint() {
        guard !busy else { return }
        if draft.secondCheckpoint != nil { draft.secondCheckpoint=nil } else { draft.checkpoint=nil }
        synchronize()
    }
    /// Changes the facing edge of a registered chair or stairs from the panel's dropdown (452:11604).
    func setFacingEdge(_ edge: Int?, of id: UUID) {
        guard !busy, let i=draft.objects.firstIndex(where:{$0.id==id}) else { return }
        draft.objects[i].facingEdge=edge; synchronize()
    }
    func disappear() { session.endSession() }
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background { confirmingRouteHeight=false; pendingRouteHeight=nil;session.setActive(false)} else if phase == .active {session.setActive(true)}
    }
    func resumeTracking() { session.resumePreparation() }
    /// Leaving with no scanned surface needs no confirmation.
    var exitNeedsConfirmation: Bool { !session.photoSources.isEmpty || session.photoCapturing || session.meshCount != 0 || draft.corners.contains(where:{$0 != nil}) }

    // Steps
    func isComplete(_ s: PreparationStep) -> Bool {
        switch s {
        case .scan: return scanConfirmed
        case .boundary: return draft.area != nil
        case .objects: return highest > .objects && draft.objectErrors.isEmpty
        case .route: return draft.routeFinished && draft.routeErrors.isEmpty
        case .checkpoint: return draft.checkpoint != nil && draft.checkpointErrors.isEmpty
        }
    }
    /// After the scan is confirmed every later step is open, finished or not (the step bar moves freely).
    func canSelect(_ s: PreparationStep) -> Bool { !(busy || s == .scan || !scanConfirmed || objectEditing) }
    func advance() {
        highest=max(highest,step.next); changeStep(step.next)
    }
    func selectReferencePlan(_ plan: PerformancePlan) {
        guard !busy else { return }
        do {
            _ = try draft.reference(for:plan)
            selectedPlan=plan; choosingPlan=false
            showObjectReference=true; showRouteReference=true
            if scanName == "무대 스캔" || scanName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { scanName=plan.name }
            highest=max(highest,.objects)
            changeStep(.objects)
        } catch {
            session.errorMessage=error.localizedDescription
        }
    }
    func changeStep(_ value: PreparationStep) {
        guard value > .scan, scanConfirmed, !busy else {return}
        highest=max(highest,value)
        let changed=step != value
        confirmingRouteHeight=false; pendingRouteHeight=nil
        step=value; review=false; selectedCorner=nil; guideCollapsed=false; selectedRoutePoint=nil
        if !seen.contains(value) {seen.insert(value); intro=0} else {intro=nil}
        // Objects are outlined on top of the scanned surface (10/18), so the mesh stays on through that step.
        if changed {session.showMesh = value <= .objects}
        synchronizeReference()
    }

    /// Mirrors the current input into anchors and the AR overlay.
    func synchronize() {
        session.planReference=visiblePlanReference
        let edge = (obstacleKind == .platform || obstacleKind == .stairs) ? facingEdge : nil
        session.applyPreparation(draft,pendingObject:pendingObjectWorld,pendingFacingEdge:edge)
    }
    func place(_ update: (inout PreparationDraft, Point3) throws -> Void) {
        guard canPlacePoint else {return}
        do {var next=draft; try update(&next,session.centerFloorPoint()); draft=next; synchronize()}
        catch {session.errorMessage=error.localizedDescription}
    }
}
