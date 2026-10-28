import SwiftUI
import HearIAmCore

struct HearRootView: View {
    @StateObject private var library=StageLibrary()
    @ObservedObject private var launch=VoiceLaunch.shared
    @State private var tab=0
    var body: some View {
        TabView(selection:$tab) {
            HomeView(library:library).tabItem {Label("홈",systemImage:"house.fill")}.tag(0)
            PlacesView(library:library).tabItem {Label("장소",systemImage:"folder.fill")}.tag(1)
            PlanLibraryView(library:library).tabItem {Label("공연 사전 저장",systemImage:"map")}.tag(2)
            GuidanceRecordsView(library:library)
                .tabItem {Label("기록",systemImage:"clock")}.tag(3)
        }.tint(.hearInk).preferredColorScheme(.light)
            // A Siri request opens guidance from Home, whichever tab was showing (#91).
            .onChange(of:launch.pending) { _, request in if request != nil {tab=0} }
            // Siri phrases that name a stage only know the stages it was last told about.
            .onChange(of:library.records.map(\.id)) {HearShortcuts.updateAppShortcutParameters()}
            .task {await library.refresh()}
            .alert("확인이 필요해요",isPresented:Binding(get:{library.error != nil},set:{if !$0 {library.error=nil}})) {
                Button("확인",role:.cancel) {library.error=nil}
            } message: {Text(library.error ?? "")}
    }
}
