import SwiftUI
import ARKit
import PoC4Core

struct CameraView: UIViewRepresentable {
    let model: ScanLabModel
    func makeUIView(context: Context) -> ARSCNView {
        let view=ARSCNView(frame:.zero)
        view.preferredFramesPerSecond=30
        model.attach(view)
        return view
    }
    func updateUIView(_ uiView: ARSCNView,context:Context) {}
}
