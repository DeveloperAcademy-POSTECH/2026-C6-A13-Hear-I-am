import SwiftUI
import HearIAmCore

/// Only the requested thumbnail/full image is read; errors stay local to this card.
struct SavedPhotoImage: View {
    let store: ScanStore
    let scanID: UUID
    let photo: ScanPhoto
    var thumbnail=true
    @State private var image: UIImage?
    @State private var failed=false
    var body: some View {
        Group {
            if let image {Image(uiImage:image).resizable().scaledToFit()}
            else if failed {Label("사진을 불러올 수 없어요",systemImage:"photo.badge.exclamationmark").font(.caption).padding()}
            else {ProgressView().padding()}
        }.task(id:"\(photo.id)-\(thumbnail)") {
            image=nil; failed=false
            do {
                let data=try await store.photoData(scanID:scanID,photoID:photo.id,thumbnail:thumbnail)
                guard !Task.isCancelled else {return}
                image=UIImage(data:data); failed=image==nil
            } catch {if !Task.isCancelled {failed=true}}
        }
    }
}
