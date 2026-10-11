import SwiftUI

@main
struct PoC3App: App {
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--demo") {
                    NavigationStack { BodyDemoView() }
                } else { PoC3Home() }
                #else
                PoC3Home()
                #endif
            }.preferredColorScheme(.dark)
        }
    }
}

struct PoC3Home: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("STAGE / BODY / DIRECTION", systemImage: "figure.dance").font(.caption.bold()).foregroundStyle(.mint)
                    Text("PoC3").font(.system(size: 56, weight: .bold, design: .rounded))
                    Text("몸의 방향에서\n목적지까지.").font(.largeTitle.bold())
                    Text("운영자는 무대와 P의 위치를 보고, 배에 착용한 폰은 몸의 방향을 읽어 소리로 안내합니다.")
                        .foregroundStyle(.secondary)
                    NavigationLink { OperatorWorkspace() } label: {
                        roleCard("운영자", detail: "무대 스캔 · P 추적 · S와 D 지정", icon: "viewfinder")
                    }
                    NavigationLink { WearerView() } label: {
                        roleCard("착용자 P", detail: "배에 세로 착용 · 몸 방향 · 폰 스피커", icon: "iphone.gen3.radiowaves.left.and.right")
                    }
                    NavigationLink("센서 없는 이동 예제") { BodyDemoView() }
                        .buttonStyle(.bordered)
                    Text("두 기기에 PoC3 설치 · Wi-Fi와 Bluetooth 켜기\n운영자: LiDAR 지원 iPhone/iPad · P: iPhone\n앱을 전면에 유지하고 화면을 바깥쪽으로 착용합니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24)
            }.navigationTitle("PoC3").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func roleCard(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon).font(.title).frame(width: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.bold())
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
        }.foregroundStyle(.white).padding(20)
            .background(.mint.opacity(0.13), in: RoundedRectangle(cornerRadius: 20))
    }
}
