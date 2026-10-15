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

struct UnavailableFeature: View {
    let title: String
    let symbol: String
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text("현재 준비 중인 기능입니다."))
    }
}
