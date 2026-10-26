import SwiftUI
import HearIAmCore

@MainActor final class PlaceLibrary: ObservableObject {
    @Published private(set) var index=PlaceFolderIndex()
    @Published private(set) var photos: [UUID: UIImage] = [:]
    @Published private(set) var ready=false
    @Published private(set) var loading=false
    @Published private(set) var busy=false
    @Published var error: String?
    @Published var scanPresented=false
    @Published var sheet: PlaceSheetRequest?
    func present(_ content: PlaceSheetRequest.Content) {sheet=PlaceSheetRequest(content:content)}
    let store: PlaceFolderStore
    private var receipt: PlaceScanReceipt?
    private var scanDestination: PlaceDestination?

    init(root: URL? = nil) {
        let directory=root ?? FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("PlaceFolders",isDirectory:true)
        store=PlaceFolderStore(root:directory)
    }
    func refresh() async {
        guard !loading, !busy else {return}
        loading=true;defer {loading=false}
        do {index=try await store.load();ready=true;await loadPhotos()}
        catch {ready=false;self.error="장소 정보를 읽지 못했어요. 기존 스캔은 유지됩니다. \(error.localizedDescription)"}
    }
    private func loadPhotos() async {
        var loaded: [UUID: UIImage] = [:]
        for place in index.places {
            if let existing=photos[place.photoID] {loaded[place.photoID]=existing}
            else if let data=try? await store.photo(place.photoID),let image=UIImage(data:data) {loaded[place.photoID]=image}
        }
        photos=loaded
    }
    @discardableResult func update(_ action: () async throws -> PlaceFolderIndex) async -> Bool {
        guard !busy, !loading, ready else {return false}
        busy=true;defer {busy=false}
        do {index=try await action();await loadPhotos();return true}
        catch {self.error=error.localizedDescription;return false}
    }
    func records(_ records: [ScanManifest], at destination: PlaceDestination?, includeSubfolders: Bool = false) -> [ScanManifest] {
        records.filter {record in
            let saved=index.destination(for:record.id)
            if includeSubfolders,let destination {return saved?.placeID == destination.placeID}
            return saved==destination
        }.sorted {$0.date>$1.date}
    }
    func count(in place: PlaceEntry, scans: [ScanManifest]) -> Int {
        records(scans,at:.init(placeID:place.id),includeSubfolders:true).count
    }
    func visit(_ id: UUID) async {
        _ = await update {try await store.visit(id)}
    }
    /// The existing preparation view runs unchanged. Only its newly saved result is classified afterwards.
    func beginScan(at destination: PlaceDestination?, library: StageLibrary) async {
        guard !busy, !loading, ready, !scanPresented else {return}
        busy=true;defer {busy=false}
        do {
            if let destination, !index.contains(destination) {throw LabError.invalid("저장할 폴더를 다시 선택해주세요.")}
            receipt=PlaceScanReceipt(scans:try await library.scans.list())
            scanDestination=destination
            scanPresented=true
        } catch {self.error=error.localizedDescription}
    }
    func finishScan(library: StageLibrary) async {
        let receipt=self.receipt, destination=scanDestination
        self.receipt=nil;scanDestination=nil
        do {
            let saved=try await library.scans.list()
            if let destination,let id=try receipt?.newScan(in:saved) {
                let success=await update {try await store.assign([id],to:destination)}
                if !success {error="공연은 저장됐지만 폴더에 연결하지 못했어요. ‘장소 미지정’에서 옮겨주세요.\n"+(error ?? "")}
            }
        } catch {self.error="스캔 원본은 유지됩니다. 장소 미지정에서 저장 결과를 확인해주세요.\n\(error.localizedDescription)"}
        await library.refresh()
    }
}

struct PlaceSheetRequest: Identifiable {
    let id=UUID()
    let content: Content
    enum Content {
        case edit(PlaceEntry?)
        case move([ScanManifest])
        case rename(ScanManifest)
    }
}
