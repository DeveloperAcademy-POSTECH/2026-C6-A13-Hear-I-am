import SwiftUI
import UIKit

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

/// The landscape scan used to slide up as a modal while the window was still turning, so the two motions fought.
/// Now the screen fades to black, the scan is put up underneath that black without any animation, the window turns
/// unseen, and the scan fades in. Closing runs the same steps backwards. `HearRootView` draws the veil over everything.
@MainActor final class ScanTransition: ObservableObject {
    static let shared=ScanTransition()
    @Published private(set) var veiled=false
    /// One fade, in or out.
    static let fade: Double = 0.3
    /// How long the window takes to finish turning after an orientation request.
    static let rotation: Double = 0.45
    func veil(_ on: Bool) {withAnimation(.easeInOut(duration:Self.fade)) {veiled=on}}
}

/// Full-screen black that swallows touches while it shows.
struct ScanVeil: View {
    let on: Bool
    var body: some View {
        Color.black.opacity(on ? 1 : 0).ignoresSafeArea().allowsHitTesting(on).accessibilityHidden(true)
    }
}

extension View {
    /// `fullScreenCover` for the scan screen, presented through `ScanTransition` instead of the slide-up.
    func scanCover<Cover: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Cover) -> some View {
        modifier(ScanCoverModifier(isPresented:isPresented,onDismiss:onDismiss,cover:content))
    }
    func scanCover<Item: Identifiable, Cover: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Cover) -> some View {
        modifier(ScanCoverModifier(isPresented:Binding(get:{item.wrappedValue != nil},set:{if !$0 {item.wrappedValue=nil}}),onDismiss:onDismiss) {
            if let value=item.wrappedValue {content(value)}
        })
    }
}

private struct ScanCoverModifier<Cover: View>: ViewModifier {
    @Binding var isPresented: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var cover: () -> Cover
    @State private var presented=false
    func body(content: Content) -> some View {
        content
            .onChange(of:isPresented) {_,shown in
                if shown && !presented {present()}
                else if !shown && presented {withTransaction(Self.instant) {presented=false}}
            }
            .fullScreenCover(isPresented:$presented,onDismiss:{
                isPresented=false
                onDismiss?()
                ScanTransition.shared.veil(false)
            }) {cover()}
    }
    private func present() {
        ScanTransition.shared.veil(true)
        Task { @MainActor in
            try? await Task.sleep(for:.seconds(ScanTransition.fade))
            withTransaction(Self.instant) {presented=true}
        }
    }
    static var instant: Transaction {var transaction=Transaction();transaction.disablesAnimations=true;return transaction}
}
