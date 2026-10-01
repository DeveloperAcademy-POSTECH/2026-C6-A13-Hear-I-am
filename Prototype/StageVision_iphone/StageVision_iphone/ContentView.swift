import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            GuidanceWorkspace()
                .tabItem { Label("1인 이동 PoC", systemImage: "location.north.line") }
            PeopleTrackingView()
                .tabItem { Label("사람 감지", systemImage: "person.3.sequence.fill") }
            StageMapWorkspace()
                .tabItem { Label("무대 지도", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            LegacyStageView()
                .tabItem { Label("기존 직사각형", systemImage: "rectangle") }
        }
        .tint(.mint)
        .preferredColorScheme(.dark)
    }
}
