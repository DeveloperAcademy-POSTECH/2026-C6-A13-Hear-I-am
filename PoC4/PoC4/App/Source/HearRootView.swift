import SwiftUI
import PoC4Core

struct HearRootView: View {
    @StateObject private var library=StageLibrary()
    var body: some View {
        TabView {
            HomeView(library:library).tabItem {Label("홈",systemImage:"house.fill")}
            PlanLibraryView(library:library).tabItem {Label("공연 사전 저장",systemImage:"map")}
            GuidanceRecordsView(library:library)
                .tabItem {Label("기록",systemImage:"clock")}
        }.tint(.hearInk).preferredColorScheme(.light)
            .task {await library.refresh()}
            .alert("확인이 필요해요",isPresented:Binding(get:{library.error != nil},set:{if !$0 {library.error=nil}})) {
                Button("확인",role:.cancel) {library.error=nil}
            } message: {Text(library.error ?? "")}
    }
}
