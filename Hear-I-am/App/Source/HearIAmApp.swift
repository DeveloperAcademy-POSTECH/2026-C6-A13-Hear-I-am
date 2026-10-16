import SwiftUI

@main struct HearIAmApp: App {
    @UIApplicationDelegateAdaptor(HearAppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { HearRootView() } }
}
