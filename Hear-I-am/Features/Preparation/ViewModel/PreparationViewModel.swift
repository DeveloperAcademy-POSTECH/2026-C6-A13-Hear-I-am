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
    @Published var obstacleName="장애물"
    @Published var obstacleKind: ObstacleKind = .box
    @Published var scanName="무대 스캔"
    @Published var selectedPlan: PerformancePlan?
    @Published var choosingPlan=false
    var editingObjectID: UUID?

    // Screen state
    @Published var step: PreparationStep = .scan
    @Published var highest: PreparationStep = .scan
    @Published var intro: Int? = 0
    @Published var selectedCorner: Int?
    @Published var objectEditing=false
    @Published var review=false
    @Published var guideCollapsed=false
    @Published var confirmingScan=false
    @Published var confirmingExit=false
    private var seen: Set<PreparationStep> = [.scan]
    private var sessionChanges: AnyCancellable?

    init(initialPlan: PerformancePlan? = nil) {
        self.selectedPlan=initialPlan
        if let initialPlan { self.scanName=initialPlan.name }
        sessionChanges=session.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        session.onReset={ [weak self] in
            guard let self else { return }
            draft=PreparationDraft(); scanConfirmed=false; pendingObjectWorld=[]; editingObjectID=nil
        }
    }

    // Session state the screen reads
    var supported: Bool { session.supported }
    var supportsMesh: Bool { session.supportsMesh }
    var busy: Bool { session.busy }
    var interrupted: Bool { session.preparationInterrupted }
    var canPlacePoint: Bool { session.canPlacePoint }
    var meshCount: Int { session.meshCount }
    var mapping: String { session.mapping }
    var savedID: UUID? { session.savedID }
    var showMesh: Bool { get {session.showMesh} set {session.showMesh=newValue} }
    var errorMessage: String? { get {session.errorMessage} set {session.errorMessage=newValue} }

    var guide: PreparationGuide {
        PreparationGuide(step:step,draft:draft,nextCorner:nextCorner,objectEditing:objectEditing,pendingVertexCount:pendingObjectWorld.count)
    }
    var showsCrosshairHint: String? {
        if interrupted { return "추적 중단" }
        if step == .scan { return supportsMesh ? "민트색 그물 = 스캔한 표면" : nil }
        return "십자선을 실제 바닥에 맞춰주세요"
    }

    // Lifecycle
    func appear() {
        session.showMesh=true
        if session.supported {session.newScan()}
    }
    func disappear() { session.endSession() }
    func scenePhaseChanged(_ phase: ScenePhase) {
        if phase == .background {session.setActive(false)} else if phase == .active {session.setActive(true)}
    }
    func resumeTracking() { session.resumePreparation() }
    /// Leaving with no scanned surface needs no confirmation.
    var exitNeedsConfirmation: Bool { session.meshCount != 0 || draft.corners.contains(where:{$0 != nil}) }

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
    func canSelect(_ s: PreparationStep) -> Bool { !(busy || s == .scan || s > highest || objectEditing) }
    func advance() {
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
        step=value; review=false; selectedCorner=nil; guideCollapsed=false
        if !seen.contains(value) {seen.insert(value); intro=0} else {intro=nil}
        if changed {session.showMesh = value == .scan || value == .boundary}
    }
    /// The boundary step shows two intro pages; every other step shows one.
    func nextIntroPage() {
        if step == .boundary && intro == 0 {intro=1} else {intro=nil}
    }

    /// Mirrors the current input into anchors and the AR overlay.
    func synchronize() { session.applyPreparation(draft,pendingObject:pendingObjectWorld) }
    func place(_ update: (inout PreparationDraft, Point3) throws -> Void) {
        guard canPlacePoint else {return}
        do {var next=draft; try update(&next,session.centerFloorPoint()); draft=next; synchronize()}
        catch {session.errorMessage=error.localizedDescription}
    }
}
