import SwiftUI
import HearIAmCore

struct PreparationPhotoControls: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        HStack(spacing:12) {
            Button {
                model.session.capturePhoto(objectID:model.objectEditing ? model.editingObjectID : nil,
                                           routeIndex:model.step == .route && !model.draft.route.isEmpty ? model.draft.route.count-1 : nil)
            } label:{
                Label(model.session.photoCapturing ? "저장 중…" : "사진 남기기",systemImage:"camera.fill")
            }.disabled(!model.session.canCapturePhoto)
            Button {model.showingPhotos=true} label:{
                Label("\(model.session.photoSources.count)/\(ScanPhoto.maximumCount)",systemImage:"photo.on.rectangle")
            }.accessibilityLabel("촬영한 사진 \(model.session.photoSources.count)장 확인")
                .disabled(model.session.photoSources.isEmpty || model.busy)
            if !model.session.photoStatus.isEmpty {Text(model.session.photoStatus).font(.caption)}
        }.font(.subheadline).padding(10).background(.regularMaterial,in:Capsule())
    }
}
