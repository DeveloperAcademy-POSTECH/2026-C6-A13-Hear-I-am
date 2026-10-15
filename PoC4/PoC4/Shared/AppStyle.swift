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
