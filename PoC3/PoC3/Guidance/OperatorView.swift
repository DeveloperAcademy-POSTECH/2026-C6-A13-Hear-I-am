import SwiftUI
import ARKit

struct OperatorWorkspace: View {
    @StateObject private var model = OperatorModel()
    @State private var scanning = false
    @Environment(\.scenePhase) private var phase
    private var supported: Bool {
        ARWorldTrackingConfiguration.isSupported && ARWorldTrackingConfiguration.supportsFrameSemantics(PeopleTrackingController.semantics)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("무대와 P를 한 좌표로").font(.largeTitle.bold())
                ConnectionView(link: model.link)
                Text("1. 착용 폰 연결\n2. 바닥 · 원점 · 객석 방향 · 경계 스캔\n3. P 선택 → 현재 위치를 S로 → D 지정\n4. P가 객석을 보고 정면 보정 → 안내 시작")
                    .lineSpacing(8)
                Button("무대 스캔하고 P 추적하기") { scanning = true }
                    .buttonStyle(.borderedProminent).disabled(!supported)
                if !supported { Text("운영자 실측은 LiDAR sceneDepth·사람 분할 지원 기기가 필요합니다.").foregroundStyle(.orange) }
                Text("스캔 후에도 운영자가 같은 기기로 P를 계속 촬영합니다. P 한 명만 화면에 담아주세요. 시작점 S는 카메라로 측정한 현재 P 위치입니다.")
                Text("몸 방향 기준은 객석입니다. P가 객석을 바라보고 움직이지 않는 동안 정면 보정을 요청하세요.")
                    .foregroundStyle(.mint)
                Text("현재 PoC는 무대 내부 직선 이동을 지원합니다. 스캔을 닫거나 앱이 백그라운드로 가면 다시 스캔해야 합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("운영자")
            .fullScreenCover(isPresented: $scanning) { OperatorScanView(model: model, controller: model.scanner) }
            .onAppear { model.begin() }
            .onDisappear { if !scanning { model.end() } }
            .onChange(of: phase) { _, value in if value != .active { model.suspend() } }
    }
}

struct OperatorPanel: View {
    @ObservedObject var model: OperatorModel
    @ObservedObject var scanner: StageScanController
    let polygon: [MapPoint]
    @AppStorage("PoC3.operatorMapRotated180") private var mapRotated180 = false
    @State private var targetX = "0"
    @State private var targetY = "2"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("P → D").font(.title2.bold())
                    Spacer()
                    Text(model.active ? "안내 중" : "준비 / 중지").foregroundStyle(model.active ? .mint : .orange)
                }
                Button {
                    mapRotated180.toggle()
                } label: {
                    Label(mapRotated180 ? "기본 방향으로 보기" : "미니맵 180° 회전", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityValue(mapRotated180 ? "180도 회전 · 객석이 위" : "기본 방향 · 객석이 아래")
                BodyPlanView(polygon: polygon, start: model.startPoint, position: model.position,
                             target: model.target, heading: model.bodyDegrees.map { BodyNavigationMath.stageHeading(relativeDegrees: $0) },
                             rotated180: mapRotated180) { model.setTarget($0) }
                    .frame(height: 200)
                Text("지도에서 D를 선택 · 노란 화살표는 P의 몸 방향").font(.caption)
                Text(scanner.guide.trackingMessage).font(.caption).foregroundStyle(.secondary)
                if scanner.guide.selectedID == nil {
                    Button(scanner.guide.candidateAvailable ? "이 사람을 P로 선택" : "P 감지 대기 · 몸통을 비춰주세요") {
                        model.selectPerson(scanner.guide.people.first?.id ?? 1)
                    }.buttonStyle(.borderedProminent).disabled(!scanner.guide.candidateAvailable)
                    Text("사람 영상으로 P를 지정합니다. S 확정과 이동 안내에는 유효한 깊이 위치가 필요합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("현재 P 위치를 시작점 S로") { model.captureStart() }.disabled(model.position == nil || model.active)
                        Button("P 해제") {
                            model.invalidate("P를 다시 선택하세요"); scanner.guide.clearSelection()
                        }.disabled(model.active)
                    }.buttonStyle(.bordered)
                }
                DisclosureGroup("D 좌표로 지정 (m)") {
                    HStack {
                        TextField("X", text: $targetX).textFieldStyle(.roundedBorder).accessibilityLabel("목적지 X 미터")
                        TextField("Y", text: $targetY).textFieldStyle(.roundedBorder).accessibilityLabel("목적지 Y 미터")
                        Button("D 적용") {
                            if let x = Double(targetX), let y = Double(targetY) { model.setTarget(MapPoint(x, y)) }
                        }
                    }
                }
                ConnectionView(link: model.link)
                Text(model.status).font(.subheadline.bold()).foregroundStyle(.mint)
                HStack {
                    Label(model.wearerReady ? "착용 센서·스피커 준비됨" : "착용 센서·스피커 대기", systemImage: "iphone")
                    if model.calibrated { Text("정면 보정 완료").foregroundStyle(.mint) }
                }.font(.caption)
                Button("P 객석 정렬 완료 · 정면 보정 요청") { model.calibrate() }
                    .buttonStyle(.bordered).disabled(!model.canCalibrate)
                HStack {
                    Button("안내 시작") { model.start() }.buttonStyle(.borderedProminent)
                        .disabled(!model.calibrated || model.active)
                    Button("즉시 중지", role: .destructive) { model.pause() }.buttonStyle(.bordered)
                }
            }
        }
    }
}
