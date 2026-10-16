import SwiftUI
import PoC4Core

/// Loads one saved scan bundle for the 3D preview.
@MainActor
final class SavedStagePreviewModel: ObservableObject {
    @Published var loaded: LoadedScan?
    @Published var error: String?
    @Published var wireframe=false
    @Published var fit=0
    let record: ScanManifest
    private let store: ScanStore

    init(record: ScanManifest, store: ScanStore) { self.record=record; self.store=store }

    func load() async {
        error=nil
        do {loaded=try await store.load(record.id)} catch {self.error=error.localizedDescription}
    }
    /// Re-frames the camera on the whole mesh.
    func fitAll() { fit += 1 }
}
