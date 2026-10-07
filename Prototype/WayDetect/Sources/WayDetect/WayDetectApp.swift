import SwiftUI
import WayDetectCore

@main
struct WayDetectApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var session = SessionController()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).environmentObject(session).tint(.indigo)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var session: SessionController
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @State private var selectedRoute: UUID?
    @State private var wasBackgrounded = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                RoutesView { route in selectedRoute = route.id; tab = 1 }
            }.tabItem { Label("경로", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }.tag(0)
            NavigationStack {
                MeasurementView(selectedRoute: $selectedRoute)
            }.tabItem { Label("측정", systemImage: "location.north.line") }.tag(1)
            NavigationStack { RecordsView() }
                .tabItem { Label("기록", systemImage: "chart.xyaxis.line") }.tag(2)
            NavigationStack { SettingsView() }
                .tabItem { Label("설정", systemImage: "slider.horizontal.3") }.tag(3)
        }
        .alert("저장 상태 확인", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("확인") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .sheet(isPresented: Binding(get: { store.interruptedRecord != nil }, set: { _ in })) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "pause.circle.fill").font(.system(size: 48)).foregroundStyle(.orange)
                    Text("남아 있는 측정 기록").font(.title2.bold())
                    Text("앱이 종료되기 전 임시 기록입니다. 저장 여부를 선택해 주세요. 이전 방향 기준으로 측정을 재개하지는 않습니다.")
                    Button("기록 저장") { store.archiveInterrupted() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Button("저장 안 함", role: .destructive) {
                        if let record = store.interruptedRecord { store.discardPendingSession(id: record.id) }
                    }.buttonStyle(.bordered).controlSize(.large)
                    Spacer()
                }.padding(24).navigationTitle("측정 복구").navigationBarTitleDisplayMode(.inline)
            }.interactiveDismissDisabled()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: wasBackgrounded = true; session.enteredBackground()
            case .inactive: if session.isActive { session.pause("앱 사용이 중단됐습니다. 위치와 정면을 확인한 뒤 재개해 주세요.") }
            case .active:
                session.becameActive(resumeSensors: wasBackgrounded); wasBackgrounded = false
            @unknown default: break
            }
        }
        .onChange(of: session.needsResultDecision) { _, needed in if needed { tab = 1 } }
        .onAppear {
            // Explicit UI-test fixtures. Never used during normal launches or saved as real measurements.
            if ProcessInfo.processInfo.arguments.contains("--preview-results") { tab = 2 }
        }
    }
}
