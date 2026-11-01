import SwiftUI

@main struct HearIAmApp: App {
    @UIApplicationDelegateAdaptor(HearAppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--guidance-record-preview") {
                GuidanceReplayPreviewHarness()
            } else if ProcessInfo.processInfo.arguments.contains("--stage-replay-preview") {
                StageReplayPreviewHarness()
            } else if ProcessInfo.processInfo.arguments.contains("--guidance-v3-practice-preview") {
                GuidanceV3PreviewHarness(practice:true)
            } else if ProcessInfo.processInfo.arguments.contains("--guidance-v3-preview") {
                GuidanceV3PreviewHarness(practice:false)
            } else {HearRootView()}
            #else
            HearRootView()
            #endif
        }
    }
}
