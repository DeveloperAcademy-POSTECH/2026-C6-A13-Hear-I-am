import SwiftUI

@MainActor
final class PreferencesStore: ObservableObject {
    @Published var values: AppPreferences { didSet { save() } }
    private let defaults: UserDefaults
    private let key = "directionHaptics.preferences.v1"
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        defaults = arguments.contains("--ui-testing") ? UserDefaults(suiteName: "org.heariam.DirectionHaptics.UITests")! : .standard
        if arguments.contains("--ui-testing") && arguments.contains("--ui-reset") { defaults.removeObject(forKey: key) }
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(AppPreferences.self, from: data) {
            values = decoded.validated
        } else { values = AppPreferences() }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(values.validated) { defaults.set(data, forKey: key) }
    }
    func reset() { values = AppPreferences() }
    var colorScheme: ColorScheme? {
        switch values.appearance { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

struct KeepAwakeModifier: ViewModifier {
    let enabled: Bool
    @State private var original = false
    func body(content: Content) -> some View {
        content.onAppear {
            original = UIApplication.shared.isIdleTimerDisabled
            if enabled { UIApplication.shared.isIdleTimerDisabled = true }
        }.onDisappear { UIApplication.shared.isIdleTimerDisabled = original }
    }
}
