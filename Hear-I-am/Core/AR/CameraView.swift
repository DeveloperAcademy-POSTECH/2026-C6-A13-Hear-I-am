import SwiftUI
import ARKit
import Combine
import HearIAmCore

struct CameraView: UIViewRepresentable {
    let model: ARSessionController
    func makeUIView(context: Context) -> ARSCNView {
        let view=ARSCNView(frame:.zero)
        view.preferredFramesPerSecond=30
        model.attach(view)
        if model.purpose == .preparation {
            // The system 「Move iPhone to start」 animation (Figma 452:12789) while the scan finds its first surfaces.
            let coaching=ARCoachingOverlayView()
            coaching.goal = .anyPlane
            coaching.activatesAutomatically=false
            coaching.delegate=context.coordinator
            coaching.translatesAutoresizingMaskIntoConstraints=false
            view.addSubview(coaching)
            NSLayoutConstraint.activate([
                coaching.leadingAnchor.constraint(equalTo:view.leadingAnchor),coaching.trailingAnchor.constraint(equalTo:view.trailingAnchor),
                coaching.topAnchor.constraint(equalTo:view.topAnchor),coaching.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
            context.coordinator.coaching=coaching
            context.coordinator.view=view
            context.coordinator.observe()
        }
        return view
    }
    // SwiftUI sees the same controller object each time and skips updates, so the coaching follows the
    // controller's published state through Combine instead (see `Coordinator.observe`).
    func updateUIView(_ uiView: ARSCNView,context:Context) {}
    func makeCoordinator() -> Coordinator {Coordinator(model:model)}

    @MainActor final class Coordinator: NSObject, ARCoachingOverlayViewDelegate {
        let model: ARSessionController
        var coaching: ARCoachingOverlayView?
        weak var view: ARSCNView?
        private var subscriptions: Set<AnyCancellable> = []
        init(model: ARSessionController) {self.model=model}

        func observe() {
            model.$coachingForced.removeDuplicates().dropFirst().receive(on:DispatchQueue.main).sink { [weak self] forced in
                self?.apply(forced:forced)
            }.store(in:&subscriptions)
            // Each scan runs a fresh ARSession on the view; the overlay is re-pointed at it and, if the opening
            // coaching is being held, shown again on the new session.
            model.$sessionGeneration.dropFirst().receive(on:DispatchQueue.main).sink { [weak self] _ in
                guard let self else {return}
                bindSession()
                if model.coachingForced {apply(forced:true)}
            }.store(in:&subscriptions)
            // Only the scan step uses the system coaching; later steps show the app's own tracking card.
            model.$coachingAllowed.removeDuplicates().dropFirst().receive(on:DispatchQueue.main).sink { [weak self] allowed in
                guard let self, let coaching, !model.coachingForced else {return}
                coaching.activatesAutomatically=allowed
                if !allowed {coaching.setActive(false,animated:true)}
            }.store(in:&subscriptions)
        }
        private func apply(forced: Bool) {
            guard let coaching else {return}
            bindSession()
            if forced {
                coaching.activatesAutomatically=false
                coaching.setActive(true,animated:true)
            } else {
                coaching.setActive(false,animated:true)
                coaching.activatesAutomatically=model.coachingAllowed
            }
        }
        private func bindSession() {
            guard let coaching, let view, coaching.session !== view.session else {return}
            coaching.session=view.session
        }
        func coachingOverlayViewWillActivate(_ view: ARCoachingOverlayView) {model.coachingActive=true}
        func coachingOverlayViewDidDeactivate(_ view: ARCoachingOverlayView) {model.coachingActive=false}
    }
}
