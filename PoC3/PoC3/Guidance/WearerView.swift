import SwiftUI
import Combine
import AVKit

struct WearerView: View {
    @StateObject private var model = WearerModel()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text("착용자 P").font(.largeTitle.bold())
                ConnectionView(link: model.link, wearer: true)
                Text("화면이 바깥쪽 · 배 앞에 세로 고정").foregroundStyle(.secondary)
                Text(model.relativeDegrees.map { String(format: "%+.0f°", $0) } ?? "—")
                    .font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                    .accessibilityLabel(model.relativeDegrees.map { String(format: "무대 정면 기준 몸 회전 %.0f도", $0) } ?? "몸 정면 보정 전")
                Text(model.status).font(.title3.bold()).multilineTextAlignment(.center)
                Button("현재 몸 방향 듣기") { model.readDirection() }.disabled(!model.calibrated)
                WearerDeviceStatus(motion: model.motion, speaker: model.speaker, prepare: model.prepareAudio)
                Button("즉시 중지", role: .destructive) { model.userStop() }
                    .font(.title2.bold()).buttonStyle(.borderedProminent).tint(.red)
                    .frame(minHeight: 60)
                if let stage = model.stage {
                    BodyPlanView(polygon: stage.polygon, start: stage.start, position: model.currentPosition,
                                 target: stage.target, heading: model.relativeDegrees.map { BodyNavigationMath.stageHeading(relativeDegrees: $0) })
                        .frame(height: 220)
                }
                Text("정면 보정 때는 객석을 바라보고 잠시 그대로 서세요. 이후 선택한 스피커 또는 에어팟에서 들리는 회전·전진 안내에 따라 이동합니다.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.navigationTitle("착용 폰")
            .onAppear { model.begin() }
            .onDisappear { model.end() }
            .onChange(of: phase) { _, value in model.sceneChanged(active: value == .active) }
            .accessibilityAction(.magicTap) { model.userStop() }
    }
}

private struct WearerDeviceStatus: View {
    @ObservedObject var motion: BodyMotion
    @ObservedObject var speaker: SpeakerGuide
    let prepare: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            SpeechStylePicker(speaker: speaker)
            AudioOutputPicker(speaker: speaker)
            Text(motion.status).font(.caption)
            Text(speaker.status).font(.caption).foregroundStyle(speaker.ready ? .mint : .orange)
            Button("음성 출력 준비 · 소리 확인", action: prepare).buttonStyle(.bordered)
        }
    }
}

struct BodyDemoView: View {
    private let polygon = [MapPoint(-3, 0), MapPoint(3, 0), MapPoint(3, 6), MapPoint(-3, 6)]
    @State private var position = MapPoint(0, 4)
    @State private var target = MapPoint(0, 1)
    @State private var angle = 0.0
    @StateObject private var speaker = SpeakerGuide()
    @State private var active = false
    @State private var arrival = ArrivalGate()
    @State private var status = "조작 예제 · 실제 센서와 연결을 사용하지 않습니다"
    @Environment(\.scenePhase) private var phase
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    private var instruction: BodyInstruction? { BodyNavigationMath.instruction(position: position, target: target, relativeDegrees: angle) }
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("조작 예제 · 가상 위치").font(.title2.bold()).foregroundStyle(.orange)
                BodyPlanView(polygon: polygon, start: MapPoint(0, 4), position: position, target: target,
                             heading: BodyNavigationMath.stageHeading(relativeDegrees: angle)) { point in
                    if GuidanceMath.routeInside(position, point, polygon: polygon) {
                        target = point; stop("D 변경 · 안내 시작을 다시 누르세요")
                    }
                }.frame(height: 300)
                Text(status).multilineTextAlignment(.center)
                Text(String(format: "몸 회전 %+.0f° · D까지 %.1fm", angle, (target - position).length)).monospacedDigit()
                Slider(value: $angle, in: -180...180, step: 5).accessibilityLabel("가상 몸 회전 각도")
                HStack {
                    Button("왼쪽 30°") { angle = BodyNavigationMath.wrap(angle - 30) }
                    Button("오른쪽 30°") { angle = BodyNavigationMath.wrap(angle + 30) }
                }.buttonStyle(.bordered)
                Button("몸 방향으로 20cm 전진") {
                    let next = position + BodyNavigationMath.stageHeading(relativeDegrees: angle) * 0.2
                    if GuidanceMath.routeInside(position, next, polygon: polygon) { position = next }
                }.buttonStyle(.bordered)
                SpeechStylePicker(speaker: speaker)
            AudioOutputPicker(speaker: speaker)
                Button("음성 출력 준비 · 소리 확인") { speaker.prepare() }.buttonStyle(.bordered)
                Text(speaker.status).font(.caption)
                HStack {
                    Button("예제 안내 시작") { active = true; arrival = ArrivalGate() }
                        .buttonStyle(.borderedProminent).disabled(!speaker.ready || active)
                    Button("중지", role: .destructive) { stop("예제 중지") }.buttonStyle(.bordered)
                }
                Button("예제 초기화") { stop("예제 초기화"); position = MapPoint(0, 4); target = MapPoint(0, 1); angle = 0 }
            }.padding(20)
        }.navigationTitle("이동 예제")
            .onReceive(timer) { _ in
                guard active, phase == .active else { return }
                speaker.validateOutput()
                guard speaker.ready, let instruction, GuidanceMath.routeInside(position, target, polygon: polygon) else { stop("출력 또는 경로 확인 필요"); return }
                status = instruction.spoken(style: speaker.speechStyle)
                let now = ProcessInfo.processInfo.systemUptime
                if instruction.kind == .arrived {
                    speaker.stop()
                    if arrival.update(inside: true, now: now) { active = false; speaker.update(instruction, now: now) }
                } else {
                    _ = arrival.update(inside: false, now: now)
                    speaker.update(instruction, now: now)
                }
            }
            .onChange(of: phase) { _, value in if value != .active { stop("앱 비활성 · 예제 중지"); speaker.shutdown() } }
            .onChange(of: speaker.outputMode) { _, _ in stop("출력 변경 · 소리 확인 후 예제 안내를 다시 시작하세요") }
            .onDisappear { speaker.shutdown() }
    }
    private func stop(_ message: String) { active = false; speaker.stop(); status = message }
}

struct SpeechStylePicker: View {
    @ObservedObject var speaker: SpeakerGuide
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("음성 안내 방식", selection: $speaker.speechStyle) {
                ForEach(DirectionSpeechStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text("이동 안내: 현재 몸 정면이 12시 · 오른쪽 1~5시 · 뒤 6시 · 왼쪽 7~11시")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}


private struct AudioOutputPicker: View {
    @ObservedObject var speaker: SpeakerGuide
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("안내 음성 출력", selection: $speaker.outputMode) {
                ForEach(AudioOutputMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            Text("현재 출력: \(speaker.routeName)").font(.caption)
            if speaker.outputMode == .airPods {
                HStack {
                    Text("출력 기기 선택")
                    SystemAudioRoutePicker().frame(width: 48, height: 48)
                }
                Text("에어팟을 착용 폰에 연결한 뒤 출력 기기로 선택하세요. 다른 Bluetooth 오디오도 사용할 수 있습니다. 선택 후 소리 확인이 필요합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SystemAudioRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = false
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
