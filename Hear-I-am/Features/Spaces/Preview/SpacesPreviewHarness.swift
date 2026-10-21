#if DEBUG
import SwiftUI
import HearIAmCore

/// Opt-in simulator fixtures. No writes to Documents or the user's scan library.
struct SpacesPreviewHarness: View {
    @StateObject private var library=StageLibrary(root:FileManager.default.temporaryDirectory.appendingPathComponent("spaces-qa-"+UUID().uuidString))
    @State private var ready=false
    @State private var error: String?
    @State private var tab=1
    @State private var filter=SpaceFilter()
    @State private var showFilters=false
    private var mode: String {
        let args=ProcessInfo.processInfo.arguments
        guard let i=args.firstIndex(of:"--spaces-preview"),args.indices.contains(i+1) else {return "list"}
        return args[i+1]
    }
    var body: some View {
        Group {
            if ready {
                TabView(selection:$tab) {
                    HomeView(library:library).tabItem {Label("홈",systemImage:"house.fill")}.tag(0)
                    Group {
                        if let venue=library.venues.first {
                            if mode=="venue" {NavigationStack {VenueDetailView(venue:venue,library:library)}}
                            else if mode=="room", let room=venue.rooms.first {NavigationStack {RoomDetailView(venue:venue,room:room,library:library)}}
                            else {SpacesView(library:library)}
                        }
                    }.tabItem {Label("공간",systemImage:"cube")}.tag(1)
                    PlanLibraryView(library:library).tabItem {Label("공연 사전 저장",systemImage:"map")}.tag(2)
                    GuidanceRecordsView(library:library).tabItem {Label("기록",systemImage:"clock")}.tag(3)
                    SoundTestView().tabItem {Label("소리 테스트",systemImage:"waveform")}.tag(4)
                }.sheet(isPresented:$showFilters) {SpaceFilterSheet(filter:$filter,regions:["경남","경북","광주","대구","서울"])}
            } else if let error {Text(error)}
            else {ProgressView().task {await seed()}}
        }.tint(.hearInk).preferredColorScheme(.light)
    }
    private func seed() async {
        do {
            if mode=="room" || mode=="venue" {
                let area=PerformancePlan.area
                let frame=try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1)))
                let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:area.corners,indices:[0,1,2,0,2,3])
                let base=try await library.scans.save(id:UUID(),name:"검증용 기본 공간",frame:frame,checkpoint:area.world(.init(2,2)),worldMap:Data([1]),meshes:[mesh],device:"UI fixture",appVersion:"1",space:.init(venueID:"daegu-practice",roomID:"daegu-practice-large",purpose:.base,roomArea:area,checkpointNote:"입구 옆 바닥 표식 · UI 검증용"))
                for name in ["Look at me · UI 검증용","입장 동선 · UI 검증용"] {
                    let route=try StageRoute(area:area,points:[.init(1,2),.init(3,3),.init(7,5)],obstacles:[])
                    _=try await library.scans.save(id:UUID(),name:name,frame:frame,checkpoint:area.world(.init(2,2)),worldMap:Data([1]),meshes:[mesh],device:"UI fixture",appVersion:"1",route:route,space:.init(venueID:"daegu-practice",roomID:"daegu-practice-large",baseScanID:base.id,baseMeshHash:base.meshHash,roomArea:area))
                }
            }
            await library.refresh();ready=true
            showFilters=mode=="filters"
        } catch {self.error=error.localizedDescription}
    }
}
#endif
