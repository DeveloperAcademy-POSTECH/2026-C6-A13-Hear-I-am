import SwiftUI
import SceneKit
import HearIAmCore

final class ReplaySCNView: SCNView {
    var onLayout: (() -> Void)?
    private var previousSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != previousSize, bounds.width>0, bounds.height>0 {
            previousSize=bounds.size;onLayout?()
        }
    }
}

struct SavedMeshView: UIViewRepresentable {
    let scan: LoadedScan
    @ObservedObject var model: SavedStagePreviewModel
    func makeCoordinator() -> ReplaySceneController { ReplaySceneController(scan:scan,cleanSurfaces:model.cleanSurfaces) }
    func makeUIView(context: Context) -> SCNView {
        let view=ReplaySCNView()
        let controller=context.coordinator
        view.onLayout={ [weak controller] in
            guard let controller else {return}
            controller.frame(controller.lastMode)
        }
        controller.view=view; view.scene=controller.scene; view.pointOfView=controller.camera
        view.backgroundColor=UIColor(white:0.96,alpha:1)
        view.allowsCameraControl=true; view.antialiasingMode = .multisampling4X
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.worldUp=SCNVector3(0,1,0)
        view.addGestureRecognizer(UITapGestureRecognizer(target:controller,action:#selector(ReplaySceneController.tapped(_:))))
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSelect={model.select($0)}
        context.coordinator.update(display:model.display,wireframe:model.wireframe,showPhotos:model.photoPinsVisible,
                                   selection:model.selection,cameraMode:model.cameraMode,revision:model.cameraRevision)
    }
}
