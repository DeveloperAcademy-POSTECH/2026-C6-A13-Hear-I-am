import SwiftUI
import ARKit
import Combine

struct GuidanceWorkspace: View {
    @State private var scan = false
    @State private var demo = false
    private var supported: Bool {
        ARWorldTrackingConfiguration.isSupported &&
        ARWorldTrackingConfiguration.supportsFrameSemantics(PeopleTrackingController.semantics)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("P 한 명이 D까지").font(.largeTitle.bold())
                    Text("운영자는 iPhone으로 P를 계속 촬영합니다. P는 AirPods를 착용하고 전진 보행으로 테스트합니다.")
                    Label("바닥 스캔 → 경계 지정 → P 선택 → D 지정 → 초기 방향 → 이동", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Text("무대와 P를 같은 카메라 세션에서 측정합니다. 스캔 후 앱을 닫거나 다른 탭으로 이동하면 다시 스캔해야 합니다.")
                    Text("초기 방향은 지도에서 맞추고, 이후 AirPods 머리 방향을 반영합니다. 소리는 목적지 쪽에서 들리며, 머리 방향이 몸이나 이동 방향을 의미하지는 않습니다.")
                    Button("무대 스캔하고 P 추적하기") { scan = true }
                        .buttonStyle(.borderedProminent).disabled(!supported)
                    if !supported { Text("실측은 LiDAR 깊이·사람 분할 지원 기기가 필요합니다.").foregroundStyle(.orange) }
                    Button("센서 없이 조작 예제 열기") { demo = true }.buttonStyle(.bordered)
                    Text("AirPods 공간음향 안내 · 가까워지면 커지고 멀어지면 작아집니다. 스캔 후 소리 준비 → P가 보는 방향 지정 → 안내 시작 순서로 진행하세요.")
                        .font(.callout).foregroundStyle(.orange)
                    Text("장애물 없는 짧은 구간에서 보조자와 함께 테스트하세요. 표시 위치는 몸통의 바닥 투영 추정값이며, 도착 반경 0.3m는 정확도 보증이 아닙니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("1인 이동 PoC")
            .fullScreenCover(isPresented: $scan) {
                StageScannerView(name: "PoC 무대", venue: "", pocMode: true, onFinish: { _ in })
            }
            .sheet(isPresented: $demo) { GuidanceDemoView() }
        }
    }
}

struct GuidancePanel: View {
    @Binding var guide: GuidanceState
    let polygon: [MapPoint]
    var liveAudio = false
    @StateObject private var audio = StageBeaconAudio()
    @Environment(\.scenePhase) private var scenePhase
    private let audioTimer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    @State private var headingMode = false
    @State private var headingNotice: String?
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var distanceLabel: String {
        guard let target = guide.target, let position = guide.position else { return "거리 —" }
        return String(format: "거리 %.2fm", (target - position).length)
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack {
                    Text("P → D").font(.headline)
                    Spacer()
                    Text(liveAudio ? (audio.prepared ? "AirPods 공간음향" : "소리 준비 필요") : "무음 조작 예제").font(.caption).foregroundStyle(.orange)
                }
                GuidancePlan(guide: guide, polygon: polygon) { point in
                    if headingMode {
                        guard guide.setHeading(toward: point, time: now) else {
                            headingNotice = guide.message
                            return
                        }
                        headingNotice = nil
                        if liveAudio, let heading = guide.heading {
                            // A map direction can be previewed before headphone motion is ready.
                            // Never reuse an older calibration for a newly selected direction.
                            audio.silence(clearCalibration: true)
                            if !audio.calibrate(heading: heading) {
                                headingNotice = "방향 화살표 지정 완료 · 소리 준비와 머리 방향 수신을 확인한 뒤 같은 방향을 다시 찍으세요."
                            }
                        }
                    } else {
                        headingNotice = nil
                        guide.setTarget(point)
                        if !guide.active { audio.silence(clearCalibration: true) }
                    }
                }.frame(height: 210)
                if liveAudio {
                    HStack {
                        Button(audio.prepared ? "소리 다시 준비" : "소리 준비") {
                            guide.pause("소리 준비 후 P가 보는 방향을 다시 지정하세요.")
                            audio.prepare()
                        }.buttonStyle(.bordered)
                        Text(audio.status).font(.caption)
                    }
                    DisclosureGroup("오디오 진단") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("출력: \(audio.outputStatus)")
                            Text("엔진: \(audio.engineStatus)")
                            Text("머리 방향: \(audio.motionStatus)")
                            ForEach(Array(audio.diagnostics.enumerated()), id: \.offset) { _, line in Text(line) }
                            ShareLink("진단 기록 공유", item: ([audio.outputStatus, audio.engineStatus, audio.motionStatus] + audio.diagnostics).joined(separator: "\n"))
                        }.font(.caption2).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Picker("지도 터치 동작", selection: $headingMode) {
                    Text("D 지정").tag(false)
                    Text("P가 보는 방향 지정").tag(true)
                }.pickerStyle(.segmented)
                Text(headingMode ? "운영자가 P를 정렬한 방향의 점을 지도에서 찍으세요." : "무대 안쪽을 터치해 D를 지정하세요.")
                    .font(.caption)
                if headingMode, let headingNotice {
                    Text(headingNotice).font(.caption).foregroundStyle(.orange)
                }
                if guide.selectedID != nil {
                    HStack {
                        Text("P 지정 유지").foregroundStyle(.mint)
                        Button("P 선택 해제") {
                            audio.silence(clearCalibration: true)
                            guide.clearSelection()
                        }
                    }
                }
                Text(guide.trackingMessage).font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(guide.people) { person in
                        Button(guide.selectedID == person.id ? "P 선택됨 (#\(person.id))" : "#\(person.id)을 P로 선택") {
                            audio.silence(clearCalibration: true)
                            guide.select(person.id, time: now)
                        }.disabled(guide.selectedID != nil)
                    }
                }
                Text(guide.message).font(.subheadline.bold()).foregroundStyle(guide.active ? .mint : .orange)
                HStack {
                    Text(distanceLabel)
                    Text(String(format: "방향 %+.0f°", guide.cue.turnRadians * 180 / .pi))
                    Text(String(format: "음량 계수 %.0f%%", (liveAudio ? audio.outputGain : guide.cue.gain) * 100))
                }.font(.caption.monospacedDigit())
                HStack {
                    Button("안내 시작") {
                        if liveAudio {
                            guard let heading = audio.heading else { return }
                            guide.receiveHeadHeading(heading, time: audio.headTimestamp)
                        }
                        guide.start(time: now)
                        if liveAudio { audio.update(guide) }
                    }
                        .buttonStyle(.borderedProminent).disabled(guide.active || (liveAudio && audio.heading == nil))
                    Button("정지", role: .destructive) { audio.silence(clearCalibration: true); guide.pause() }.buttonStyle(.bordered)
                }
                Text(liveAudio ? "화살표: 수동 지정 → 보정 후 AirPods 머리 방향 · 도착: 0.3m\nP는 재선택 없이 유지 · 위치 측정 대기 중에는 무음" : "화살표: 초기 지정 / 이동 추정 방향 · 도착: 0.3m\n무음 예제에서 거리별 음량 계수를 확인하세요.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.frame(maxHeight: 490)
        .onReceive(audioTimer) { _ in
            guard liveAudio, scenePhase == .active else { return }
            if guide.heading != nil, let heading = audio.heading {
                guide.receiveHeadHeading(heading, time: audio.headTimestamp)
            } else if guide.active && !audio.waitingForFreshHead {
                guide.pause("AirPods 연결·방향 측정을 확인하고 다시 정렬해주세요.")
            }
            guide.expire(time: now)
            audio.update(guide)
        }
        .onChange(of: guide.cue) { _, cue in
            guard liveAudio else { return }
            if cue.state == .paused && guide.heading == nil { audio.silence(clearCalibration: true) }
            audio.update(guide)
        }
        .onChange(of: scenePhase) { _, phase in
            if liveAudio && phase != .active {
                guide.pause("앱 비활성 · 소리 준비와 방향 지정을 다시 해주세요.")
                if phase == .background { audio.shutdown() }
                else { audio.suspend() }
            }
        }
        .onDisappear { audio.shutdown() }
    }
}

private struct GuidancePlan: View {
    let guide: GuidanceState
    let polygon: [MapPoint]
    let tap: (MapPoint) -> Void
    var body: some View {
        GeometryReader { geometry in
            let transform = PlanTransform(points: polygon, size: geometry.size)
            Canvas { context, _ in
                var floor = Path()
                if let first = polygon.first {
                    floor.move(to: transform.screen(first))
                    polygon.dropFirst().forEach { floor.addLine(to: transform.screen($0)) }
                    floor.closeSubpath()
                }
                context.fill(floor, with: .color(.mint.opacity(0.15)))
                context.stroke(floor, with: .color(.mint), lineWidth: 2)
                if let p = guide.position, let d = guide.target {
                    var route = Path(); route.move(to: transform.screen(p)); route.addLine(to: transform.screen(d))
                    context.stroke(route, with: .color(guide.active ? .mint : .gray), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
                for person in guide.people {
                    let at = transform.screen(person.point)
                    context.fill(Path(ellipseIn: CGRect(x: at.x - 7, y: at.y - 7, width: 14, height: 14)),
                                 with: .color(person.id == guide.selectedID ? .white : .gray))
                    context.draw(Text(person.id == guide.selectedID ? "P" : "#\(person.id)").font(.caption.bold()).foregroundColor(.white),
                                 at: CGPoint(x: at.x, y: at.y + 18))
                }
                if let p = guide.position, let h = guide.heading {
                    let tip = transform.screen(p + h * 0.65)
                    var arrow = Path(); arrow.move(to: transform.screen(p)); arrow.addLine(to: tip)
                    let side = MapPoint(-h.y, h.x)
                    arrow.move(to: transform.screen(p + h * 0.45 + side * 0.12)); arrow.addLine(to: tip)
                    arrow.addLine(to: transform.screen(p + h * 0.45 - side * 0.12))
                    context.stroke(arrow, with: .color(.yellow), lineWidth: 3)
                }
                if let d = guide.target {
                    context.draw(Text("◎ D").font(.headline).foregroundColor(.orange), at: transform.screen(d))
                }
                context.draw(Text("아래: 무대 앞 / 객석").font(.caption2).foregroundColor(.secondary),
                             at: CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 10))
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap(transform.stage($0.location)) })
        }.background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct GuidanceDemoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var guide = GuidanceState(polygon: [MapPoint(-3, 0), MapPoint(3, 0), MapPoint(3, 6), MapPoint(-3, 6)])
    @State private var p = MapPoint(0, 1)
    @State private var visible = true
    @State private var depthAvailable = true
    private let timer = Timer.publish(every: 0.12, on: .main, in: .common).autoconnect()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text("조작 예제 · 실제 센서 측정 아님").foregroundStyle(.orange)
                    GuidancePanel(guide: $guide, polygon: guide.polygon)
                    Text("P를 20cm씩 이동해 안내 값을 확인하세요.").font(.caption)
                    HStack {
                        Button("←") { move(-0.2, 0) }
                        Button("↑") { move(0, 0.2) }
                        Button("↓") { move(0, -0.2) }
                        Button("→") { move(0.2, 0) }
                    }.buttonStyle(.bordered)
                    Toggle("P 영상 보임", isOn: $visible)
                    Toggle("P 위치 측정 가능", isOn: $depthAvailable)
                }.padding()
            }
            .navigationTitle("PoC 조작 예제")
            .toolbar { Button("닫기") { dismiss() } }
            .onReceive(timer) { _ in
                guard scenePhase == .active else { guide.invalidate("앱 비활성 · 안내 정지"); return }
                guide.receive(visible && depthAvailable ? [GuidePerson(id: 1, point: p)] : [], time: ProcessInfo.processInfo.systemUptime, visualContact: visible, detail: visible && !depthAvailable ? "P 일부 보임 · 깊이 측정 대기" : nil)
            }
            .onDisappear { guide.pause() }
        }
    }
    private func move(_ x: Double, _ y: Double) { p = p + MapPoint(x, y) }
}
