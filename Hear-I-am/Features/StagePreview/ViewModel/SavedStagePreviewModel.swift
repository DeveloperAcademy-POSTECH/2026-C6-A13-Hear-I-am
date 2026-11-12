import SwiftUI
import HearIAmCore

@MainActor
final class SavedStagePreviewModel: ObservableObject {
    @Published var loaded: LoadedScan?
    private(set) var cleanSurfaces: [ReplaySurfaceMesh]=[]
    @Published var error: String?
    /// Set only for the folder viewer; legacy inspection and photo comparison keep their rendering.
    var immersive = false
    @Published var photoAnchor: CGPoint?
    @Published var activePointIndex = 0
    @Published var selectionRevision = 0
    @Published var wireframe=false
    @Published var display: ReplayDisplay = .scan
    @Published var cameraMode: ReplayCamera = .overview
    @Published var cameraRevision=0
    @Published var selection: ReplaySelection? { didSet { refreshHoldEditor() } }
    @Published var holdSecondsText="0"
    @Published var pointFacing: StageFacing?
    @Published var savingHold=false
    @Published var holdNotice: String?
    @Published var holdSaveError: String?
    var selectedPointIndex: Int? {
        guard case .point(let index)=selection else { return nil }
        return index
    }
    var canEditPointHold: Bool {
        guard let i=selectedPointIndex, let route=loaded?.manifest.route else { return false }
        return i > 0 && i < route.points.count-1
    }
    var enteredHoldSeconds: Int? {
        guard let seconds=Int(holdSecondsText.trimmingCharacters(in:.whitespacesAndNewlines)),
              (0...StageRoute.maximumHoldSeconds).contains(seconds) else { return nil }
        return seconds
    }
    private func refreshHoldEditor() {
        pointFacing=selectedPointIndex.flatMap {loaded?.manifest.route?.facing(at:$0)}
        holdSecondsText=String(selectedPointIndex.flatMap {loaded?.manifest.route?.holdSeconds(at:$0)} ?? 0)
        holdNotice=nil; holdSaveError=nil
    }
    func savePointSettings() async {
        guard !savingHold, let index=selectedPointIndex, let seconds=enteredHoldSeconds, let scan=loaded else { return }
        let facing=pointFacing
        savingHold=true; holdNotice=nil; holdSaveError=nil
        defer { savingHold=false }
        do {
            let manifest=try await store.setPointPerformance(record.id,index:index,facing:facing,seconds:canEditPointHold ? seconds : 0)
            loaded=LoadedScan(manifest:manifest,worldMap:scan.worldMap,meshes:scan.meshes)
            if selectedPointIndex == index { holdNotice=L("%@ 설정을 저장했습니다.", manifest.route?.pointLabel(at:index) ?? L("선택 지점")) }
        } catch { holdSaveError=L("저장하지 못했어요: %@", error.localizedDescription) }
    }
    @Published var showPhotoPins=true
    @Published var showCleanPhotoPins=false
    @Published var photoExpanded=false
    @Published var photoCardCollapsed=false
    let record: ScanManifest
    let store: ScanStore
    init(record: ScanManifest, store: ScanStore) {self.record=record;self.store=store}
    func load() async {
        guard loaded==nil else {return}
        error=nil
        do {
            let scan=try await store.load(record.id)
            // Transform/classify potentially large meshes away from the UI thread, once per load.
            cleanSurfaces=await Task.detached(priority:.userInitiated) {
                guard let route=scan.manifest.route else {return [ReplaySurfaceMesh]()}
                return scan.meshes.map {ReplaySurfaceMesh(mesh:$0,route:route)}
            }.value
            loaded=scan;refreshHoldEditor();cameraRevision+=1
        }
        catch {self.error=error.localizedDescription}
    }
    /// Comparison owns its camera/display state, so closing it never moves the main overview.
    init(scan: LoadedScan, store: ScanStore, cleanSurfaces: [ReplaySurfaceMesh], display: ReplayDisplay) {
        self.record=scan.manifest;self.store=store;self.loaded=scan;self.cleanSurfaces=cleanSurfaces;self.display=display
    }
    func setCamera(_ mode: ReplayCamera) {cameraMode=mode;cameraRevision+=1}
    var photoPinsVisible: Bool {
        get {display == .clean ? showCleanPhotoPins : showPhotoPins}
        set {if display == .clean {showCleanPhotoPins=newValue} else {showPhotoPins=newValue}}
    }
    func select(_ value: ReplaySelection) {
        guard !savingHold else { return }
        selection=value;selectionRevision+=1;photoCardCollapsed=display == .clean
        if case .point(let index)=value { activePointIndex=index }
        if case .photo=value {photoPinsVisible=true;photoCardCollapsed=false}
        // Selecting a marker updates its details without moving the user's camera.
    }
    /// End photo selection as well as the card, so the 3D camera direction disappears without reframing the stage.
    func closePhotoPreview() {
        guard !savingHold,case .photo = selection else {return}
        photoExpanded=false
        if let points=loaded?.manifest.route?.points,points.indices.contains(activePointIndex) {
            select(.point(activePointIndex))
        } else {
            // Scans without a route have no point to restore.
            selection=nil
            selectionRevision+=1
            photoCardCollapsed=true
        }
    }
    var selectedPhoto: ScanPhoto? {
        guard let photos=loaded?.manifest.photos else {return nil}
        switch selection {
        case .photo(let id): return photos.first {$0.id==id}
        case .object(let id): return photos.first {$0.objectID==id}
        case .point(let i): return loaded?.manifest.viewpointPhoto(at:i)
        case nil: return nil
        }
    }
    var selectedObject: StageObstacle? {
        guard case .object(let id)=selection else {return nil}
        return loaded?.manifest.route?.obstacles.first {$0.id==id}
    }
    var selectionTitle: String {
        switch selection {
        case .point(let i): return loaded?.manifest.route?.pointLabel(at:i) ?? L("%@번 지점", i+1)
        case .object: return selectedObject?.name ?? L("기물")
        case .photo: return L("사진 촬영 위치")
        case nil: return L("지점이나 기물을 선택하세요")
        }
    }
}

extension ScanManifest {
    /// The photo seen from a route point: the one taken there, or else the nearest photo within 2.5 m of it on the
    /// floor, so every point that has a photo nearby shows one.
    func viewpointPhoto(at index: Int) -> ScanPhoto? {
        if let tagged=photos.first(where:{$0.routePointIndex==index}) {return tagged}
        guard let route,route.points.indices.contains(index) else {return nil}
        let point=route.area.world(route.points[index])
        func distance(_ photo: ScanPhoto) -> Double {
            let p=photo.position;return ((p.x-point.x)*(p.x-point.x)+(p.z-point.z)*(p.z-point.z)).squareRoot()
        }
        guard let nearest=photos.min(by:{distance($0)<distance($1)}),distance(nearest)<=2.5 else {return nil}
        return nearest
    }
}
