import SwiftUI
import HearIAmCore

@MainActor
final class SavedStagePreviewModel: ObservableObject {
    @Published var loaded: LoadedScan?
    @Published var error: String?
    @Published var wireframe=false
    @Published var display: ReplayDisplay = .scan
    @Published var cameraMode: ReplayCamera = .overview
    @Published var cameraRevision=0
    @Published var selection: ReplaySelection?
    @Published var showPhotoPins=true
    @Published var photoExpanded=false
    @Published var photoCardCollapsed=false
    let record: ScanManifest
    let store: ScanStore
    init(record: ScanManifest, store: ScanStore) {self.record=record;self.store=store}
    func load() async {
        guard loaded==nil else {return}
        error=nil
        do {loaded=try await store.load(record.id);cameraRevision+=1}
        catch {self.error=error.localizedDescription}
    }
    func setCamera(_ mode: ReplayCamera) {cameraMode=mode;cameraRevision+=1}
    func select(_ value: ReplaySelection) {
        selection=value;photoCardCollapsed=false
        if case .photo=value {showPhotoPins=true}
        // Selecting a marker updates its details without moving the user's camera.
    }
    var selectedPhoto: ScanPhoto? {
        guard let photos=loaded?.manifest.photos else {return nil}
        switch selection {
        case .photo(let id): return photos.first {$0.id==id}
        case .object(let id): return photos.first {$0.objectID==id}
        case .point(let i): return photos.first {$0.routePointIndex==i}
        case nil: return nil
        }
    }
    var selectedObject: StageObstacle? {
        guard case .object(let id)=selection else {return nil}
        return loaded?.manifest.route?.obstacles.first {$0.id==id}
    }
    var selectionTitle: String {
        switch selection {
        case .point(let i): return "\(i+1)번 지점 · "+(i==0 ? "출발" : i==(loaded?.manifest.route?.points.count ?? 0)-1 ? "도착" : "이동")
        case .object: return selectedObject?.name ?? "기물"
        case .photo: return "사진 촬영 위치"
        case nil: return "지점이나 기물을 선택하세요"
        }
    }
}
