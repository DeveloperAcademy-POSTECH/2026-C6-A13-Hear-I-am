import SwiftUI

/// One voice guidance screen opened by the call or by Siri. Each launch is a new item, so the screen
/// always receives the request it was opened with (#90).
struct VoiceGuidanceLaunch: Identifiable {
    let id=UUID()
    var request: String?
    var stageID: UUID?
    var mode: VoiceUsageMode?
}

/// The call is heard on every tab, but not while a screen covers the tabs: that screen owns the
/// microphone and speaker, and guidance cannot open on top of it.
@MainActor final class VoiceWakeGate: ObservableObject {
    static let shared=VoiceWakeGate()
    @Published private(set) var holders: Set<UUID>=[]
    var open: Bool {holders.isEmpty}
    func hold(_ id:UUID) {holders.insert(id)}
    func release(_ id:UUID) {holders.remove(id)}
}

private struct VoiceWakeSuspension: ViewModifier {
    @State private var id=UUID()
    func body(content: Content) -> some View {
        content.onAppear {VoiceWakeGate.shared.hold(id)}.onDisappear {VoiceWakeGate.shared.release(id)}
    }
}

extension View {
    /// Stops listening for the call while this screen is shown.
    func suspendsVoiceWake() -> some View {modifier(VoiceWakeSuspension())}
}
