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
        case "scan-before": ScanPreparationFlow(library: library) { _ in }
        case "scan-after":
            if let savedID { StageClassificationView(library: library, scanIDs: [savedID], wasJustSaved: true) { _ in } }
        case "create": PerformanceEditorSheet(library: library) { _ in }
        case "editor":
            if let performanceID { ReferenceSceneEditorView(library: library, performanceID: performanceID) }
        case "space-empty":
            if let performanceID { NavigationStack { PerformanceSpaceView(library: library, performanceID: performanceID, venueID: venueID, onStartGuidance: { _ in }) } }
        case "detail":
            if let performanceID { NavigationStack { PerformanceDetailView(library: library, performanceID: performanceID, onStartGuidance: { _ in }) } }
        default:
            TabView(selection: .constant(1)) {
                Text("스캔").tabItem { Label("스캔", systemImage: "viewfinder") }.tag(0)
                PerformanceLibraryView(library: library, selectedPerformanceID: .constant(nil), onStartGuidance: { _ in }).tabItem { Label("공연 관리", systemImage: "folder") }.tag(1)
                Text("기록").tabItem { Label("기록", systemImage: "clock") }.tag(2)
            }
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
