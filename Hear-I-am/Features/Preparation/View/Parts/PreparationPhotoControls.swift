import SwiftUI
import HearIAmCore

/// Bottom-left: how many photos were kept (a 23pt glass chip), and the 48pt shutter (Figma 452:12610).
struct PreparationPhotoControls: View {
    @ObservedObject var model: PreparationViewModel
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            if !model.session.photoStatus.isEmpty {
                Text(model.session.photoStatus).font(.system(size:13)).foregroundStyle(.white)
                    .padding(.horizontal,10).padding(.vertical,5).liquidGlass(Capsule(),tint:ScanChrome.panelTint)
            }
            Button {model.showingPhotos=true} label: {
                Text("\(model.session.photoSources.count)/\(ScanPhoto.maximumCount)").font(.system(size:14)).foregroundStyle(.white)
                    .padding(.horizontal,10).frame(height:23).liquidGlass(Capsule(),tint:ScanChrome.panelTint)
            }.buttonStyle(.plain)
                .disabled(model.session.photoSources.isEmpty || model.busy)
                .accessibilityLabel(L("촬영한 사진 %@장 확인", model.session.photoSources.count))
            ScanCircleButton(systemImage:"camera",label:model.session.photoCapturing ? L("사진 저장 중") : L("사진 남기기"),size:48,enabled:model.session.canCapturePhoto) {
                model.session.capturePhoto(objectID:model.objectEditing ? model.editingObjectID : nil,
                                           routeIndex:model.step == .route && !model.draft.route.isEmpty ? model.draft.route.count-1 : nil)
            }
        }
    }
}
