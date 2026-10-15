import SwiftUI

@main struct PoC4App: App {
    @UIApplicationDelegateAdaptor(HearAppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { HearRootView() } }
}
