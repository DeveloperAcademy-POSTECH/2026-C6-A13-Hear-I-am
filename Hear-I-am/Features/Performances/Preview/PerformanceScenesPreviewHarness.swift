#if DEBUG
import SwiftUI
import HearIAmCore

/// Opt-in preview data lives outside Documents; never seeds or migrates a user's library.
struct PerformanceScenesPreviewHarness: View {
    @StateObject private var library = StageLibrary(root: FileManager.default.temporaryDirectory.appendingPathComponent("performance-113-" + UUID().uuidString))
    @State private var performanceID: UUID?
    @State private var venueID: UUID?
    @State private var savedID: UUID?
    @State private var ready = false
    @State private var failure: String?
    private var mode: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--performance-113-preview"), args.indices.contains(index + 1) else { return "list" }
        return args[index + 1]
    }
    var body: some View {
        Group {
            if let failure { Text(failure) }
            else if ready { screen }
            else { ProgressView().task { await prepare() } }
        }.v3Screen()
    }
    @ViewBuilder private var screen: some View {
        switch mode {
        case "scan-before": NavigationStack { ScanPreparationFlow(library: library) { _ in } }
        case "scan-after":
            if let savedID { StageClassificationView(library: library, scanIDs: [savedID], wasJustSaved: true) { _ in } }
        case "settings": SettingsPushPreview { HomeSettingsView() }
        case "settings-wear": SettingsPushPreview { V3UsageHelpView() }
        case "settings-voice": SettingsPushPreview { V3VoiceHelpView() }
        case "settings-permission": SettingsPushPreview { V3PermissionView() }
        case "settings-tutorial": SettingsPushPreview { SoundTestView() }
        case "settings-lesson": SettingsPushPreview { SignalLessonView(step: .direction) }
        case "guide-panel", "guide-panel-folded":
            ScanLandscapePreview { GuidePanelPreview(folded: mode == "guide-panel-folded") }
        case let mode where mode.hasPrefix("intro-"):
            // 「intro-<step>-<page>」: one how-to card over grey, turned to landscape.
            let parts = mode.split(separator: "-").compactMap { Int($0) }
            ScanLandscapePreview { PreparationIntro(step: parts.first ?? 1, page: parts.last ?? 0) { _ in } }
        case "scan-screen": PreparationView(library: library)
        case "performer-home": HomeView(library: library, wake: VoiceWakeListener(), start: {})
        case "scan-home": HelperScanHomeView(library: library, startNow: .constant(false)) { _ in }
        // As when the performer asks for a scan by voice: the scan tab opens straight onto the information page.
        case "scan-home-voice": HelperScanHomeView(library: library, startNow: .constant(true)) { _ in }
        case "scan-pick-performance": NavigationStack { PerformanceChoiceSheet(library: library, selection: performanceID) { _ in } }
        case "scan-pick-venue":
            if let performanceID { NavigationStack { VenueChoiceSheet(library: library, performanceID: performanceID, selection: venueID) { _ in } } }
        case "create": SheetOverPreview { listPage } sheet: { PerformanceEditorSheet(library: library) { _ in } }
        case "space-add":
            SheetOverPreview { detailPage } sheet: { PerformanceSpaceSearchSheet { _ in } }
        case "venue-filter":
            SheetOverPreview { listPage } sheet: {
                PerformanceVenueFilterSheet(names: ["대구공연예술연습공간", "효자아트홀", "연습실 A", "연습실 B", "소극장 A"],
                                            selection: ["효자아트홀", "대구공연예술연습공간"]) { _ in }
            }
        case "editor":
            if let performanceID { ReferenceSceneEditorView(library: library, performanceID: performanceID) }
        case "space":
            if let performanceID { NavigationStack { PerformanceSpaceView(library: library, performanceID: performanceID, venueID: venueID, onStartGuidance: { _ in }) } }
        case "space-empty":
            if let performanceID { NavigationStack { PerformanceSpaceView(library: library, performanceID: performanceID, venueID: venueID, onStartGuidance: { _ in }) } }
        case "detail": detailPage
        default: listPage
        }
    }
    @ViewBuilder private var detailPage: some View {
        if let performanceID { NavigationStack { PerformanceDetailView(library: library, performanceID: performanceID, onStartGuidance: { _ in }) } }
    }
    private var listPage: some View {
        TabView(selection: .constant(1)) {
            Text("스캔").tabItem { HelperTab.label("스캔", systemImage: "viewfinder") }.tag(0)
            PerformanceLibraryView(library: library, selectedPerformanceID: .constant(nil), onStartGuidance: { _ in }).tabItem { HelperTab.label("공연 관리", systemImage: "folder") }.tag(1)
            Text("기록").tabItem { HelperTab.label("기록", systemImage: "clock") }.tag(2)
        }
    }
    private func prepare() async {
        do {
            await library.refresh()
            if mode == "empty" { ready = true; return }
            let folder = try await library.createPerformance(name: "Lion King", notes: "쇼케이스를 위한 10분 공연")
            performanceID = folder.id
            let venue = try await library.createVenue(name: "효자 아트홀", in: folder.id)
            venueID = venue.id
            for name in ["예술의 전당", "세종문화회관", "롯데콘서트홀"] { _ = try await library.createVenue(name: name, in: folder.id) }
            for (index, name) in ["초원을 뛰어노는 장면", "긴장감 고조 장면", "마지막 인사"].enumerated() {
                var plan = PerformancePlan(); plan.name = name; plan.isReferenceOnly = true
                for point in [FloorPoint(0.6,1), .init(3,1), .init(5.4,5), .init(8,5), .init(11,1.5)] { try plan.append(point) }
                plan.objects = [try StageObstacle(name: "세트 \(index + 1)", kind: .box, vertices: [.init(8.5,6), .init(10.7,6), .init(10.7,7.5), .init(8.5,7.5)])]
                plan.completeReference(); try await library.savePerformancePlan(plan, for: folder.id)
            }
            let area = try StageArea(corners: [.init(0,0,0), .init(6,0,0), .init(6,0,-4), .init(0,0,-4)])
            let route = try StageRoute(area: area, points: [.init(0.5,0.4), .init(2,1), .init(3,2), .init(5,2)], obstacles: [])
            let mesh = MeshSnapshot(id: UUID(), transform: [1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1], vertices: area.corners, indices: [0,1,2,0,2,3])
            for name in ["초원을 뛰어노는 장면", "긴장감 고조 장면", "커튼콜"] {
                let scan = try await library.scans.save(id: UUID(), name: name, frame: StageFrame(origin: area.world(.init(0,0)), front: area.world(.init(0,-1))), checkpoint: area.world(.init(5,3)), worldMap: Data([1]), meshes: [mesh], device: "Simulator fixture", appVersion: "QA", route: route, secondCheckpoint: area.world(.init(1,3)))
                await library.refresh()
                try await library.assignScans([scan.id], to: folder.id, venueID: mode == "space-empty" ? nil : venue.id)
                savedID = scan.id
            }
            for name in ["소말리아 해적선", "내 귀에 앉은 조랑말"] { _ = try await library.createPerformance(name: name) }
            guard library.referencePlans(for: folder.id).count == 3,
                  library.scans(in: folder.id).count == 3,
                  library.records.allSatisfy({ $0.route?.points == route.points }) else { throw LabError.invalid("씬과 실제 스캔의 독립 저장 검증 실패") }
            print("PERFORMANCE_113_QA_OK: three reference scenes, space assignments, independent scanned points")
            ready = true
        } catch { failure = error.localizedDescription; print("PERFORMANCE_113_QA_FAILED: \(error)") }
    }
}

#endif

#if DEBUG
/// A sheet as it really appears: presented over its page, so its edge against the page can be checked.
private struct SheetOverPreview<Base: View, Sheet: View>: View {
    @ViewBuilder let base: Base
    @ViewBuilder let sheet: Sheet
    @State private var shown = false
    var body: some View {
        base.sheet(isPresented: $shown) { sheet }
            .task { try? await Task.sleep(for: .seconds(0.6)); shown = true }
    }
}
#endif

#if DEBUG
/// Draws a landscape scan overlay inside the portrait simulator, turned a quarter, at the 874×402 design size.
private struct ScanLandscapePreview<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ZStack { Color(white: 0.55); content }
            .frame(width: 874, height: 402).clipShape(RoundedRectangle(cornerRadius: 34))
            .rotationEffect(.degrees(90)).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black).ignoresSafeArea()
    }
}
#endif

#if DEBUG
/// The scan screen's right panel and bottom tools on the boundary step, as placed in PreparationView.
private struct GuidePanelPreview: View {
    let folded: Bool
    @StateObject private var model = PreparationViewModel()
    var body: some View {
        ZStack {
            PreparationToolGroup(model: model).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).padding(.bottom, 14)
            PreparationGuideCard(model: model, maxHeight: 252)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, -PreparationGuideCard.bleed).padding(.top, 70).padding(.bottom, 80)
            Rectangle().fill(.red).frame(width: 1).frame(maxHeight: .infinity)
        }.onAppear { model.step = .boundary; model.guideCollapsed = folded }
    }
}
#endif

#if DEBUG
/// Settings as it is reached from the role page: pushed onto a stack, with the back button.
private struct SettingsPushPreview<Page: View>: View {
    @ViewBuilder let page: Page
    @State private var pushed = false
    var body: some View {
        NavigationStack { Color.black.navigationDestination(isPresented: $pushed) { page } }
            .task { try? await Task.sleep(for: .seconds(0.5)); pushed = true }
    }
}
#endif
