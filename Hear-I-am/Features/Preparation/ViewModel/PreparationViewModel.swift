import SwiftUI
import Combine
import HearIAmCore

/// Landscape stage preparation: scan → boundary → objects → route → checkpoint → review.
/// Input lives in `draft` in AR world coordinates; every change is mirrored into the AR session.
/// Step-specific actions live in the PreparationViewModel+<Step> files.
@MainActor
final class PreparationViewModel: ObservableObject {
    let session=ARSessionController(purpose:.preparation)

    let spaceRequest: SpacePreparationRequest?
    @Published var awaitingBase=false
    @Published var checkpointNote=""
    var appeared=false
    var isBaseRegistration: Bool {spaceRequest?.context.purpose == .base}
    var usesBase: Bool {spaceRequest?.base != nil}
    var preparationErrors: [String] {isBaseRegistration ? draft.boundaryErrors + draft.checkpointErrors : draft.errors}
    var steps: [PreparationStep] {isBaseRegistration ? [.scan,.boundary,.checkpoint] : PreparationStep.allCases}

    // Input
    @Published var draft=PreparationDraft()
    @Published var scanConfirmed=false
    @Published var pendingObjectWorld: [Point3] = []
    @Published var obstacleName="장애물"
    /// Changing the kind renames an object that still carries a default name, so the name always tells
    /// the kind (field test 10/17: an object named "장애물" was saved as stairs and never warned).
    @Published var obstacleKind: ObstacleKind = .box {
        didSet {
            if ObstacleKind.allCases.map(\.defaultName).contains(obstacleName) { obstacleName=obstacleKind.defaultName }
            if !applyingSuggestion { kindChosen=true }
        }
    }
    /// Height read from the scan mesh inside the drafted outline; nil until 3 points or when too little mesh.
    @Published var entryEdges: Set<Int> = []
    @Published var exitEdges: Set<Int> = []
    @Published var objectHeight: ObjectHeight?
    /// Once the operator picks a kind, the height no longer changes it.
    var kindChosen=false
    var applyingSuggestion=false
    @Published var objectModel: ObjectAppearance.Model = .generic
    @Published var objectHeading=0.0
    @Published var showingPhotos=false
    @Published var scanName="무대 스캔"
    @Published var selectedPlan: PerformancePlan?
    @Published var choosingPlan=false
    var editingObjectID: UUID?
    var pendingObjectID=UUID()

    // Screen state
    @Published var step: PreparationStep = .scan
    @Published var highest: PreparationStep = .scan
    @Published var intro: Int? = 0
    @Published var selectedCorner: Int?
    @Published var objectEditing=false
    @Published var confirmingRouteHeight=false
    var pendingRouteHeight: (point: Point3, destination: Bool, draft: PreparationDraft, token: UUID)?
    var routeHeightMessage=""
    @Published var review=false
    @Published var editingDangerZones=false
    @Published var guideCollapsed=false
    @Published var confirmingScan=false
    @Published var confirmingExit=false
    private var seen: Set<PreparationStep> = [.scan]
    private var sessionChanges: AnyCancellable?

    init(initialPlan: PerformancePlan? = nil, spaceRequest: SpacePreparationRequest? = nil) {
        self.spaceRequest=spaceRequest
        self.awaitingBase=spaceRequest?.base != nil
        session.spaceContext=spaceRequest?.context
        if let spaceRequest {scanName=spaceRequest.title}
        if awaitingBase {intro=nil}
        self.selectedPlan=initialPlan
        if let initialPlan { self.scanName=initialPlan.name }
        sessionChanges=session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        session.onReset={ [weak self] in
            guard let self else { return }
            draft=PreparationDraft(); scanConfirmed=false; pendingObjectWorld=[]; editingObjectID=nil
        }
    }

    // Session state the screen reads
    var supported: Bool {session.supported && (!(isBaseRegistration || usesBase) || session.supportsMesh)}
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
        if isBaseRegistration {
            switch step {
            case .scan: return PreparationGuide(title:"기본 공간을 스캔하세요",description:"이동할 소품을 치우고 고정된 벽과 바닥을 충분히 담아주세요. 공연별 범위와 기물은 나중에 추가합니다.")
            case .boundary: return PreparationGuide(title:"방의 기준 범위를 지정하세요",description:"재사용할 바닥의 네 모서리를 지정해주세요. 공연마다 이 범위 안에 새 무대를 잡을 수 있습니다.")
            case .checkpoint: return PreparationGuide(title:"다시 찾을 확인점을 지정하세요",description:"이동하지 않는 바닥 표식을 지정해주세요. 저장할 때 위치 설명도 남깁니다.")
            default: break
            }
        }
        return PreparationGuide(step:step,draft:draft,nextCorner:nextCorner,objectEditing:objectEditing,pendingVertexCount:pendingObjectWorld.count)
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
        guard !appeared else {return};appeared=true
        session.showMesh=true
        if supported {
            if let base=spaceRequest?.base {session.restore(base)} else {session.newScan()}
        }
    }
    func disappear() { session.endSession() }
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background { confirmingRouteHeight=false; pendingRouteHeight=nil;session.setActive(false)} else if phase == .active {session.setActive(true)}
    }
    func resumeTracking() {
        if awaitingBase, let base=spaceRequest?.base {session.preparationInterrupted=false;session.restore(base)}
        else {session.resumePreparation()}
    }
    func verifyBaseAndContinue() {
        session.verifyCheckpoint()
        guard session.ready else {return}
        do {
            try session.beginBasePerformance()
            draft=PreparationDraft();scanConfirmed=true;highest = .boundary;awaitingBase=false
            synchronize();changeStep(.boundary)
        } catch {session.errorMessage=error.localizedDescription}
    }
    /// Leaving with no scanned surface needs no confirmation.
    var exitNeedsConfirmation: Bool { !awaitingBase && (!session.photoSources.isEmpty || session.photoCapturing || session.meshCount != 0 || draft.corners.contains(where:{$0 != nil})) }

    // Steps
    func isComplete(_ s: PreparationStep) -> Bool {
        switch s {
        case .scan: return scanConfirmed
        case .boundary: return draft.area != nil
        case .objects: return (highest > .objects || draft.planApplied) && draft.objectErrors.isEmpty
        case .route: return draft.routeFinished && draft.routeErrors.isEmpty
        case .checkpoint: return draft.checkpoint != nil && draft.checkpointErrors.isEmpty
        }
    }
    func canSelect(_ s: PreparationStep) -> Bool { !(busy || awaitingBase || s == .scan || s > highest || objectEditing) && steps.contains(s) }
    func advance() {
        if isBaseRegistration && step == .boundary {highest = .checkpoint;changeStep(.checkpoint);return}
        if step == .boundary, let selectedPlan {
            applyPlan(selectedPlan)
            return
        }
        highest=max(highest,step.next); changeStep(step.next)
    }
    func applyPlan(_ plan: PerformancePlan) {
        do {
            var next=draft
            try next.applyPlan(plan)
            for source in session.photoSources {
                session.linkPhoto(source.photo.id,objectID:nil,routeIndex:nil)
            }
            for id in Array(session.scopedLayers.keys) {session.removeObjectLayer(id)}
            draft=next; selectedPlan=plan; choosingPlan=false
            if scanName == "무대 스캔" || scanName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { scanName=plan.name }
            synchronize()
            highest = .checkpoint
            changeStep(.checkpoint)
        } catch {
            session.errorMessage=error.localizedDescription
        }
    }
    func changeStep(_ value: PreparationStep) {
        guard value > .scan, value <= highest, !busy else {return}
        let changed=step != value
        confirmingRouteHeight=false; pendingRouteHeight=nil
        step=value; review=false; selectedCorner=nil; guideCollapsed=false
        if !seen.contains(value) {seen.insert(value); intro=0} else {intro=nil}
        // Objects are outlined on top of the scanned surface (10/18), so the mesh stays on through that step.
        if changed {session.showMesh = value <= .objects}
    }
    /// The boundary step shows two intro pages; every other step shows one.
    func nextIntroPage() {
        if step == .boundary && intro == 0 {intro=1} else {intro=nil}
    }

    /// Mirrors the current input into anchors and the AR overlay.
    func synchronize() { session.applyPreparation(draft,pendingObject:pendingObjectWorld) }
    func place(_ update: (inout PreparationDraft, Point3) throws -> Void) {
        guard canPlacePoint else {return}
        do {
            var next=draft;try update(&next,session.centerFloorPoint())
            if let roomArea=spaceRequest?.context.roomArea, let area=next.area {
                guard area.corners.allSatisfy({roomArea.contains(roomArea.floor($0)) && abs($0.y-roomArea.floorHeight)<=0.10}) else {
                    throw LabError.invalid("이번 공연의 범위는 기본 공간 안 같은 바닥에 지정해주세요.")
                }
            }
            draft=next;synchronize()
        }
        catch {session.errorMessage=error.localizedDescription}
    }
}
