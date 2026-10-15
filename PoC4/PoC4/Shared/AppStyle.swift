import SwiftUI
import UIKit
import PoC4Core

extension Color {
    static let hearGreen = Color(red: 0.16, green: 0.43, blue: 0.34)
    static let hearInk = Color(white: 0.10)
}

struct ActionButton: View {
    let title: String
    var primary = true
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .semibold)).frame(minHeight: 44).padding(.horizontal, 18)
                .foregroundStyle(primary ? .white : Color.hearInk)
                .background(primary ? Color.hearInk : .white.opacity(0.92), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.gray.opacity(primary ? 0 : 0.3)))
        }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
    }
}

final class HearAppDelegate: NSObject, UIApplicationDelegate {
    static var orientations: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask { Self.orientations }
}

enum ScreenOrientation {
    @MainActor static func set(_ mask: UIInterfaceOrientationMask) {
        HearAppDelegate.orientations = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}) {
            scene.windows.forEach { window in
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.rootViewController?.presentedViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

/// Present the landscape controller with its final orientation, so UIKit coordinates
/// rotation with presentation/dismissal rather than rotating an already visible SwiftUI screen.
extension View {
    func landscapeCover<Content: View>(isPresented: Binding<Bool>, onDismiss: @escaping () -> Void = {},
                                       @ViewBuilder content: @escaping (@escaping () -> Void) -> Content) -> some View {
        background(LandscapePresenter(isPresented:isPresented,onDismiss:onDismiss,content:content).frame(width:0,height:0))
    }
}

private struct LandscapePresenter<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let content: (@escaping () -> Void) -> Content
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> PresentationAnchor {
        let anchor=PresentationAnchor()
        anchor.onReady={ [weak coordinator=context.coordinator] in coordinator?.reconcile() }
        context.coordinator.anchor=anchor
        return anchor
    }
    func updateUIViewController(_ controller: PresentationAnchor,context: Context) {
        context.coordinator.parent=self
        context.coordinator.wantsPresentation=isPresented
        Task { @MainActor [weak coordinator=context.coordinator] in coordinator?.reconcile() }
    }
    @MainActor final class Coordinator {
        var parent: LandscapePresenter
        var wantsPresentation=false
        weak var anchor: PresentationAnchor?
        private var host: UIViewController?
        private var transitioning=false
        init(_ parent: LandscapePresenter) {self.parent=parent}
        func reconcile() {
            guard !transitioning, let anchor else {return}
            if wantsPresentation, host == nil, anchor.viewIfLoaded?.window != nil, anchor.presentedViewController == nil {
                let controller=LandscapeHostingController(rootView:parent.content { [weak self] in self?.parent.isPresented=false })
                controller.modalPresentationStyle = .fullScreen
                controller.modalTransitionStyle = .crossDissolve
                // Allow both the outgoing portrait and incoming landscape controller during the transition.
                HearAppDelegate.orientations = .allButUpsideDown
                host=controller;transitioning=true
                anchor.present(controller,animated:!UIAccessibility.isReduceMotionEnabled) { [weak self] in
                    guard let self else {return}
                    self.transitioning=false
                    ScreenOrientation.set(.landscape)
                    self.reconcile()
                }
            } else if !wantsPresentation, let host {
                transitioning=true
                HearAppDelegate.orientations = .portrait
                anchor.setNeedsUpdateOfSupportedInterfaceOrientations()
                host.dismiss(animated:!UIAccessibility.isReduceMotionEnabled) { [weak self] in
                    guard let self else {return}
                    self.host=nil;self.transitioning=false
                    ScreenOrientation.set(.portrait)
                    self.parent.onDismiss()
                    self.reconcile()
                }
            }
        }
    }
}

private final class PresentationAnchor: UIViewController {
    var onReady: (() -> Void)?
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {.portrait}
    override func viewDidAppear(_ animated: Bool) {super.viewDidAppear(animated);onReady?()}
}

private final class LandscapeHostingController<Content: View>: UIHostingController<Content> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {.landscape}
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        UIDevice.current.orientation == .landscapeRight ? .landscapeLeft : .landscapeRight
    }
}

struct UnavailableFeature: View {
    let title: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("현재 준비 중인 기능입니다."))
    }
}

/// The provisional Hear I am mark: eight directional rays around an open center.
struct BrandMark: View {
    var body: some View {
        Canvas { context, size in
            let radius=min(size.width,size.height)
            let center=CGPoint(x:size.width/2,y:size.height/2)
            func point(_ angle:Double,_ r:Double) -> CGPoint {
                CGPoint(x:center.x+cos(angle)*radius*r,y:center.y+sin(angle)*radius*r)
            }
            for i in 0..<8 {
                let angle=Double(i)*Double.pi/4
                var ray=Path()
                ray.move(to:point(angle,0.17))
                if i%2 == 0 {ray.addLine(to:point(angle,0.39))}
                else {
                    ray.addLine(to:point(angle,0.22)); ray.move(to:point(angle,0.27)); ray.addLine(to:point(angle,0.39))
                }
                context.stroke(ray,with:.color(.white),lineWidth:max(1,radius*0.027))
            }
        }.background(.black,in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
    }
}


extension View {
    func librarySelection(selecting: Bool, selected: Bool, onSelect: @escaping () -> Void, onToggle: @escaping () -> Void) -> some View {
        self.allowsHitTesting(!selecting)
            .overlay {
                if selecting {
                    Button(action:onToggle) {Color.clear.contentShape(Rectangle())}
                        .buttonStyle(.plain).accessibilityLabel(selected ? "선택 해제" : "선택")
                }
            }
            .overlay(alignment:.topLeading) {
                if selecting {
                    Image(systemName:selected ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(selected ? Color.hearGreen : .secondary)
                        .background(.white,in:Circle()).padding(8).allowsHitTesting(false)
                }
            }
            .overlay(RoundedRectangle(cornerRadius:20).stroke(selected ? Color.hearGreen : .clear,lineWidth:2).allowsHitTesting(false))
            .contentShape(RoundedRectangle(cornerRadius:20))
            .highPriorityGesture(LongPressGesture(minimumDuration:0.45).onEnded {_ in onSelect()})
            .accessibilityAction(named:"삭제할 항목으로 선택",onSelect)
    }
}

struct LibrarySelectionBar: View {
    let count: Int
    let busy: Bool
    let cancel: () -> Void
    let delete: () -> Void
    var body: some View {
        HStack(spacing:16) {
            Button("취소",action:cancel).frame(minHeight:44)
            Spacer()
            if busy {ProgressView()} else {Text("\(count)개 선택").font(.subheadline.weight(.semibold))}
            Spacer()
            Button(role:.destructive,action:delete) {Label("삭제",systemImage:"trash").frame(minHeight:44)}
                .disabled(count == 0)
        }.padding(.horizontal,24).padding(.vertical,6).background(.regularMaterial).disabled(busy)
    }
}
