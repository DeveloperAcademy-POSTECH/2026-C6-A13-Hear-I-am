import SwiftUI

@main
struct DirectionHapticsApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var haptics = HapticService()
    @StateObject private var preferences = PreferencesStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(haptics)
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(Theme.accent)
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--hardware-diagnostics") {
                        await HardwareDiagnostics.run(haptics: haptics)
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { haptics.stop(interrupted: true) }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var haptics: HapticService
    var body: some View {
        TabView {
            NavigationStack { LibraryView() }.tabItem { Label("탐색", systemImage: "square.grid.2x2.fill") }
            NavigationStack { RandomPracticeView() }.tabItem { Label("랜덤 체험", systemImage: "hand.draw.fill") }
            NavigationStack { UserSetsView() }.tabItem { Label("편집", systemImage: "slider.horizontal.3") }
        }
        .alert("확인해 주세요", isPresented: Binding(get: { store.error != nil || haptics.error != nil }, set: { if !$0 { store.error = nil; haptics.error = nil } })) {
            Button("확인") { store.error = nil; haptics.error = nil }
        } message: { Text(store.error ?? haptics.error ?? "") }
        .overlay(alignment: .top) {
            if let message = store.message {
                Text(message).font(.subheadline.bold()).padding().background(.regularMaterial, in: Capsule())
                    .padding(.top, 4)
                    .task(id: message) {
                        try? await Task.sleep(for: .seconds(2.5))
                        if store.message == message { store.message = nil }
                    }
                    .allowsHitTesting(false)
            }
        }
    }
}
