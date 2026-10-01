import SwiftUI
import simd

struct PeopleTrackingView: View {
    @StateObject private var controller = PeopleTrackingController()
    @Environment(\.scenePhase) private var scenePhase
    @State private var display = 0
    @State private var selectedID: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Picker("측정 모드", selection: $controller.mode) {
                        ForEach(PeopleTrackingController.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    if controller.mode == .demo {
                        Label("가상 인물 예제 · 실제 센서 측정값이 아닙니다", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    summary
                    visualization
                    controls
                    peopleList
                    VStack(alignment: .leading, spacing: 7) {
                        Label("측정 기준", systemImage: "scope").font(.subheadline.bold())
                        Text("거리: 카메라에서 몸통 표면까지의 직선 거리. 좌우·앞: 현재 휴대폰 방향을 기준으로 한 수평 위치. 높이차: 카메라 대비 몸통 위치입니다.")
                        Text("사람 영역의 고신뢰 LiDAR 깊이만 사용합니다. 절대 측정 오차는 아직 실기기에서 검증하지 않았습니다.")
                        Text("후면 카메라에 몸통이 보이는 사람만 감지합니다. 모형의 키와 걷기 동작은 설명용이며 실제 체형·관절 측정이 아닙니다. 가림·교차 시 번호가 바뀔 수 있습니다. 소수점 표시는 정확도 보장을 뜻하지 않습니다.")
                    }.font(.caption).foregroundStyle(.secondary).padding(16).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }.padding(20).frame(maxWidth: 900).frame(maxWidth: .infinity)
            }
            .background(Color(red: 0.025, green: 0.04, blue: 0.065))
            .navigationTitle("사람 감지").navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { controller.appear() }
        .onDisappear { controller.stop() }
        .onChange(of: controller.mode) { _, _ in selectedID = nil; controller.changeMode() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.stop() } }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("PEOPLE RADAR").font(.caption.weight(.bold)).tracking(3).foregroundStyle(.mint)
            Text("사람의 움직임을, 공간 위에.").font(.title2.bold())
            Text(controller.supported ? "LiDAR + 카메라 · 여러 사람의 위치와 거리" : "이 기기는 LiDAR 실측 미지원 · 시뮬레이션 사용 가능")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var summary: some View {
        HStack(spacing: 0) {
            metric("감지 인원", "\(controller.visiblePeople.count)", "명")
            Spacer()
            let nearest = controller.visiblePeople.compactMap { controller.relative($0).map { simd_length($0) } }.min()
            metric("가장 가까운 사람", nearest.map { String(format: "%.2f", $0) } ?? "—", "m")
            Spacer()
            metric("감지 반경", String(format: "%.1f", controller.range), "m")
        }.padding(16).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
    }
    private func metric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var visualization: some View {
        VStack(spacing: 0) {
            HStack {
                Label(controller.running ? "감지 중" : "대기", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.bold()).foregroundStyle(controller.running ? .mint : .secondary)
                Spacer()
                Picker("표시 방식", selection: $display) {
                    Text("3D 모형").tag(0); Text("평면도").tag(1)
                }.pickerStyle(.segmented).frame(maxWidth: 190)
            }.padding(14)
            ZStack(alignment: .bottomLeading) {
                if display == 0 {
                    PeopleSceneView(people: controller.visiblePeople, camera: controller.camera,
                                    range: controller.range, selectedID: selectedID)
                } else { radar }
                if controller.visiblePeople.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.rectangle.badge.plus").font(.largeTitle)
                        Text(controller.running ? "반경 안의 사람을 찾고 있습니다" : "시작하면 사람의 위치가 나타납니다").font(.subheadline)
                        Text("후면 카메라를 사람의 몸통이 보이도록 향해주세요").font(.caption)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Text(display == 0 ? "1 m 격자 · 체형과 동작은 예시" : "상단 = 전방 · 원점 = 내 iPhone")
                    .font(.caption2).foregroundStyle(.secondary).padding(12)
            }.frame(height: 330).clipped()
        }.background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
    }
    private var radar: some View {
        GeometryReader { geometry in
            let scale = min((geometry.size.width - 50) / (2 * controller.range), (geometry.size.height - 55) / controller.range)
            let origin = CGPoint(x: geometry.size.width / 2, y: geometry.size.height - 38)
            Canvas { context, size in
                for meter in 1...5 where Double(meter) <= controller.range {
                    let radius = Double(meter) * scale
                    var ring = Path()
                    ring.addArc(center: origin, radius: radius, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                    context.stroke(ring, with: .color(.mint.opacity(0.2)), lineWidth: 1)
                    context.draw(Text("\(meter)m").font(.system(size: 10)).foregroundColor(.gray), at: CGPoint(x: origin.x + radius - 10, y: origin.y - 10))
                }
                var axis = Path(); axis.move(to: CGPoint(x: origin.x, y: 15)); axis.addLine(to: origin)
                context.stroke(axis, with: .color(.white.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))
            }
            Image(systemName: "iphone.radiowaves.left.and.right").foregroundStyle(.white).position(origin)
            ForEach(controller.visiblePeople) { person in
                if let p = controller.relative(person) {
                    Button { selectedID = person.id } label: {
                        VStack(spacing: 3) {
                            Image(systemName: person.moving ? "figure.walk" : "figure.stand").font(.title2)
                            Text(String(format: "P%02d · %.2fm", person.id, simd_length(p))).font(.caption2.monospacedDigit())
                        }.foregroundStyle(peopleColor(person.id)).padding(7)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(selectedID == person.id ? peopleColor(person.id) : .clear))
                    }.buttonStyle(.plain).position(x: origin.x + Double(p.x) * scale, y: origin.y - Double(p.z) * scale)
                }
            }
        }
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("감지 반경").font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.1f m", controller.range)).monospacedDigit().foregroundStyle(.mint)
            }
            Slider(value: $controller.range, in: 1...5, step: 0.5).accessibilityLabel("감지 반경, 미터")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sensor.fill").foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(controller.status).font(.caption)
                    if controller.rejected > 0 {
                        Text("깊이 또는 자세 불확실 \(controller.rejected)명 · 측정에서 제외").font(.caption2).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button { controller.running ? controller.stop() : controller.start() } label: {
                    Label(controller.running ? "일시 정지" : "감지 시작", systemImage: controller.running ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).tint(.mint).foregroundStyle(.black)
                if controller.running {
                    Button { selectedID = nil; controller.start() } label: { Image(systemName: "arrow.counterclockwise").padding(.vertical, 7) }
                        .buttonStyle(.bordered).accessibilityLabel("감지 다시 시작")
                }
                if controller.permissionDenied {
                    Button("설정 열기") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
            }
        }
    }
    private var peopleList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("감지된 사람").font(.headline); Spacer(); Text("위치 단위 m · 추정값").font(.caption2).foregroundStyle(.secondary) }
            ForEach(controller.visiblePeople) { person in
                if let p = controller.relative(person) {
                    Button { selectedID = person.id } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: person.moving ? "figure.walk" : "figure.stand").font(.title2).foregroundStyle(peopleColor(person.id))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(String(format: "PERSON %02d", person.id)).font(.subheadline.bold())
                                    Text(person.motionReady ? (person.moving ? "이동 중 · 약 \(String(format: "%.1f", person.speed)) m/s" : "정지 / 느린 움직임") : "움직임 확인 중")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(String(format: "%.2f m", simd_length(p))).font(.title3.bold()).monospacedDigit()
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack { coordinates(p) }
                                VStack(alignment: .leading) { coordinates(p) }
                            }.font(.caption).monospacedDigit().foregroundStyle(.secondary)
                        }.padding(15).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selectedID == person.id ? peopleColor(person.id) : .white.opacity(0.06)))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    @ViewBuilder private func coordinates(_ p: SIMD3<Float>) -> some View {
        Text(String(format: "%@ %.2f", p.x < 0 ? "왼쪽" : "오른쪽", abs(p.x)))
        Text(String(format: "앞 %.2f", p.z))
        Text(String(format: "높이차 %+.2f", p.y))
    }
}

#Preview { PeopleTrackingView().preferredColorScheme(.dark) }
