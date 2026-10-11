import SwiftUI
import AppIntents

@main
struct OrientationHapticsLabApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ResetOrientationIntent: AppIntent {
    static let title: LocalizedStringResource = "방향 기준 리셋"
    static let description = IntentDescription("현재 방향을 0도 기준점으로 다시 설정합니다.")
    static let openAppWhenRun: Bool = true // 실행 시 앱 화면을 열어 센서 측정 활성화

    @MainActor
    func perform() async throws -> some IntentResult {
        // 단축어 실행 시 ContentView로 알림 전송
        NotificationCenter.default.post(name: Notification.Name("ResetOrientationIntentTriggered"), object: nil)
        return .result()
    }
}

struct OrientationShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResetOrientationIntent(),
            phrases: [
                "\(.applicationName)에서 방향 기준 리셋해 줘",
                "\(.applicationName) 방향 영도로 맞춰 줘"
            ],
            shortTitle: "방향 리셋",
            systemImageName: "scope"
        )
    }
}
