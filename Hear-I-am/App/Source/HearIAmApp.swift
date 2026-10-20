import SwiftUI

@main struct HearIAmApp: App {
    @UIApplicationDelegateAdaptor(HearAppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--stage-replay-preview") {
                StageReplayPreviewHarness()
            } else {HearRootView()}
            #else
            HearRootView()
            #endif
        }
    }
}
