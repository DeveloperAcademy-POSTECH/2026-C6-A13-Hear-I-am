import SwiftUI
import HearIAmCore

@main struct HearIAmApp: App {
    @UIApplicationDelegateAdaptor(HearAppDelegate.self) var appDelegate
    init() {
        HearFont.registerBundled();DiagnosticLogMaintenance.start()
        #if DEBUG
        // Switches the language a few seconds after launch, to check that open screens redraw in place (#183).
        if ProcessInfo.processInfo.arguments.contains("--flip-language") {
            DispatchQueue.main.asyncAfter(deadline:.now()+12) {
                HearLanguage.choose(HearLanguage.current.isEnglish ? .korean : .english)
            }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--performance-113-preview") {
                PerformanceScenesPreviewHarness()
            } else if ProcessInfo.processInfo.arguments.contains("--guidance-record-preview") {
                GuidanceReplayPreviewHarness()
            } else if ProcessInfo.processInfo.arguments.contains("--stage-replay-preview") {
                StageReplayPreviewHarness()
            } else if let index=ProcessInfo.processInfo.arguments.firstIndex(of:"--voice-walk-preview") {
                VoiceWalkPreviewHarness(screen:ProcessInfo.processInfo.arguments.dropFirst(index+1).first ?? "walk")
            } else if ProcessInfo.processInfo.arguments.contains("--guidance-v3-practice-preview") {
                GuidanceV3PreviewHarness(practice:true)
            } else if ProcessInfo.processInfo.arguments.contains("--guidance-v3-preview") {
                GuidanceV3PreviewHarness(practice:false)
            } else if ProcessInfo.processInfo.arguments.contains("--permissions-preview") {
                // 「권한 상태」 alone, to look at the dictation section (#189) without walking through Settings.
                NavigationStack {V3PermissionView()}
            } else {HearRootView()}
            #else
            HearRootView()
            #endif
            }
            // Every page and sheet: a tap anywhere outside a text field puts the keyboard away.
            .background(KeyboardDismissInstaller())
        }
    }
}

/// Puts one tap recognizer on the window that ends editing when a tap lands outside any text field. It does not
/// cancel the tap, so the button or row under the finger still gets it, and sheets are covered because they are
/// presented in the same window.
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {InstallerView()}
    func updateUIView(_ view: InstallerView, context: Context) {}

    final class InstallerView: UIView, UIGestureRecognizerDelegate {
        private static let name="hear.keyboardDismiss"
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, !(window.gestureRecognizers ?? []).contains(where: {$0.name == Self.name}) else {return}
            let tap=UITapGestureRecognizer(target:self,action:#selector(dismissKeyboard))
            tap.name=Self.name
            tap.cancelsTouchesInView=false
            tap.delegate=self
            window.addGestureRecognizer(tap)
        }
        @objc private func dismissKeyboard() {window?.endEditing(true)}
        /// A tap on a text field (or inside one) moves the caret instead of closing the keyboard.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view=touch.view
            while let current=view {
                if current is UITextField || current is UITextView {return false}
                view=current.superview
            }
            return true
        }
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {true}
    }
}
