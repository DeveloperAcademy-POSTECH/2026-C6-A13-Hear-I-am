import SwiftUI
import HearIAmCore

/// Temporary fourth tab for real-device signal checks. Remove with the SoundTest folder after testing.
struct SoundTestView: View {
    @StateObject private var model=SoundTestViewModel()
    @AppStorage(HearAudioSession.speakerKey) private var forcesSpeaker=false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("실기기 확인용 임시 화면이에요. 테스트가 끝나면 지워요.").font(.subheadline).foregroundStyle(.secondary)
                        Text("마지막 기록: "+model.lastEvent).font(.caption.monospaced()).lineLimit(2)
                        Text(model.logStatus).font(.caption).foregroundStyle(.secondary)
                        // Same setting as 홈 설정 › 소리 출력; the next sound plays through the new output.
                        Toggle("폰 스피커로 듣기 (끄면 에어팟)",isOn:$forcesSpeaker).font(.subheadline)
                            .onChange(of:forcesSpeaker) {_,value in model.record("audio_output",value ? "speaker" : "auto")}
                    }
                    SoundTestCard(section:.signals) { signals }
                    SoundTestCard(section:.haptics) { haptics }
                    SoundTestCard(section:.buzz) { buzz }
                    SoundTestCard(section:.direction) { direction }
                }.padding(.horizontal,20).padding(.vertical,16)
            }.navigationTitle("소리 테스트")
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
    }

    private var signals: some View {
        VStack(alignment:.leading,spacing:16) {
            Text("현재 안내: 상승음은 왼쪽, 하강음은 오른쪽. 삐빅은 방향 정렬, 띵은 지점 도착이에요.")
                .font(.subheadline)
            SoundTestRow(label:"새 방향음 · 큰 회전 / 작은 회전") {
                ForEach([-135,-25,25,135],id:\.self) { degrees in
                    ActionButton(title:Self.label(degrees),primary:false,enabled:model.trial == nil) { model.previewSweep(degrees) }
                }
                ActionButton(title:"정렬 삐빅",primary:false,enabled:model.trial == nil) { model.previewAlignment() }
            }
            SoundTestRow(label:"남은 거리 · 좌우 기물 미리듣기") {
                ForEach([1.5,3.2,0.7],id:\.self) { meters in
                    ActionButton(title:String(format:"%.1f m",meters),primary:false) {
                        if let line=DistanceAnnouncement(meters:meters)?.line { model.speak(line) }
                    }
                }
                ForEach(["오른쪽 책장","왼쪽 책상","단상 접근"],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"경고 소리 종류 (고른 뒤 아래 거리를 눌러요)") {
                ForEach(WarningTone.allCases,id:\.self) { tone in
                    ActionButton(title:Self.toneLabel(tone),primary:model.warningTone == tone) { model.setWarningTone(tone) }
                }
            }
            SoundTestRow(label:"장애물 경고 (반복, 다시 누르면 꺼짐)") {
                ForEach(WarningLevel.allCases,id:\.self) { level in
                    ActionButton(title:["1m","0.6m","0.35m"][level.rawValue-1],primary:model.warning == level) {
                        model.setWarning(model.warning == level ? nil : level)
                    }
                }
            }
            SoundTestRow(label:"도착") { ActionButton(title:"띵",primary:false) { model.playArrival() } }
            SoundTestRow(label:"기존 방향 비프 비교 (현재 안내에는 미사용)") {
                ForEach(DirectionPattern.landmarks,id:\.self) { degrees in
                    ActionButton(title:Self.label(degrees),primary:false) { model.beep(degrees) }
                }
            }
            SoundTestRow(label:"방향 교정 음성") {
                ForEach([SignalCopy.turnLeft,SignalCopy.turnRight,SignalCopy.turnBack],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"단상 · 계단 음성") {
                ForEach(["단상 접근",SignalCopy.stepUp(stairs:true),SignalCopy.stepDown],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"빠져나오기 음성") {
                ForEach([true,false],id:\.self) { right in
                    let line=SignalCopy.escape(toRight:right)
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"겹침") {
                ActionButton(title:"경고 0.6m + \"왼쪽으로\"",primary:false) { model.playOverlap() }
            }
        }
    }

    private var haptics: some View {
        VStack(alignment:.leading,spacing:16) {
            SoundTestRow(label:"기존 방식 비교 (이 테스트에만 적용)") {
                ForEach(DirectionSignalMode.allCases,id:\.self) { mode in
                    ActionButton(title:Self.modeLabel(mode),primary:model.directionMode == mode) { model.setDirectionMode(mode) }
                }
            }
            SoundTestRow(label:"45° 눈금 (0° = 목표 방향, 진동은 좌우 같음)") {
                ForEach(DirectionPattern.landmarks,id:\.self) { degrees in
                    ActionButton(title:Self.label(degrees),primary:false) { model.vibrate(degrees) }
                }
            }
            SoundTestRow(label:"진동 중 위치 추적") {
                ActionButton(title:model.probing ? "위치 추적 끄기" : "위치 추적 켜기",primary:model.probing) { model.toggleProbe() }
            }
            Text("추적: \(model.trackingText) · 1초 흔들림: \(model.jitterText)").font(.subheadline.monospacedDigit())
        }
    }

    private var buzz: some View {
        VStack(alignment:.leading,spacing:16) {
            ForEach([false,true],id:\.self) { harmonic in
                SoundTestRow(label:harmonic ? "높은 소리 섞음" : "낮은 소리만") {
                    ForEach([40.0,50,60,70,80],id:\.self) { hertz in
                        ActionButton(title:"\(Int(hertz))Hz",primary:false) { model.playBuzz(hertz,harmonic:harmonic) }
                    }
                }
            }
        }
    }

    private var direction: some View {
        VStack(alignment:.leading,spacing:16) {
            VStack(alignment:.leading,spacing:4) {
                Text("에어팟: \(model.headStatus)")
                Text("몸 \(Self.angle(model.bodyAngle)) · 고개 \(Self.angle(model.headAngle))").monospacedDigit()
                if let trial=model.trial { Text("진행 중 · \(trial.mode.rawValue) · 목표 \(trial.target)°").bold() }
            }.font(.subheadline)
            Text("작은 한 음이 계속 이어져요. 왼쪽 보정은 80→60Hz, 오른쪽 보정은 40→60Hz로 목표에 가까워질수록 변해요. 정렬되면 띠링이 한 번 나고 작은 60Hz 소리는 유지돼요.")
                .font(.subheadline)
            SoundTestRow(label:"새 실험 · 작은 지속음 40~80Hz") {
                ActionButton(title:"몸으로 찾기 · 지속음",enabled:model.trial == nil) { model.startTrial(.pitchBody) }
                ActionButton(title:"고개로 찾기 · 지속음",enabled:model.trial == nil) { model.startTrial(.pitchHead) }
                ActionButton(title:"슬라이더로 듣기",primary:false,enabled:model.trial == nil) { model.startTrial(.pitchSlider) }
                ActionButton(title:"기준음 60Hz",primary:false,enabled:model.trial == nil) { model.startTrial(.pitchReference) }
                ActionButton(title:"그만",primary:false,enabled:model.trial != nil) { model.finishTrial(found:false) }
            }
            Text("\(model.pitchStatus) · \(model.pitchHertz.map { String(format: "%.1f Hz",$0) } ?? "무음")")
                .font(.subheadline.monospacedDigit()).accessibilityLabel("지속음 상태, \(model.pitchStatus)")
            Picker("음높이 변화",selection:$model.pitchResolution) {
                Text("부드럽게").tag(ContinuousDirectionGate.Resolution.smooth)
                Text("10Hz 간격").tag(ContinuousDirectionGate.Resolution.tenHertz)
            }.pickerStyle(.segmented)
            VStack(alignment:.leading,spacing:6) {
                Text("지속음 크기 \(Int((model.pitchVolume*100).rounded()))%")
                Slider(value:$model.pitchVolume,in:0.02...0.3,step:0.01).accessibilityLabel("지속음 크기")
            }.font(.caption)
            if model.trial?.mode == .pitchSlider {
                VStack(alignment:.leading,spacing:8) {
                    Text("목표 상대각 \(Self.angle(model.manualBearing)) · 0°가 정렬")
                    Slider(value:$model.manualBearing,in:-180...180,step:1)
                        .accessibilityLabel("목표 상대각").accessibilityValue(Self.angle(model.manualBearing))
                    HStack {
                        ForEach([-180,-90,0,90,180],id:\.self) { value in
                            Button("\(value)°") { model.manualBearing=Double(value) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            SoundTestRow(label:"이전 방식 비교") {
                ActionButton(title:"이전 휘익 360°",enabled:model.trial == nil) { model.startTrial(.sweep) }
                ActionButton(title:"이전 몸 진동",enabled:model.trial == nil) { model.startTrial(.body) }
                ActionButton(title:"이전 고개 부르르",enabled:model.trial == nil) { model.startTrial(.head) }
                ActionButton(title:"그만",primary:false,enabled:model.trial != nil) { model.finishTrial(found:false) }
            }
            if !model.results.isEmpty {
                VStack(alignment:.leading,spacing:6) {
                    Text("결과").font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(model.results) { Text($0.summary).font(.caption.monospacedDigit()) }
                }
            }
        }
    }

    static func label(_ degrees: Int) -> String {
        degrees == 0 ? "앞" : degrees == 180 ? "뒤" : (degrees < 0 ? "왼쪽 " : "오른쪽 ")+"\(abs(degrees))°"
    }
    static func modeLabel(_ mode: DirectionSignalMode) -> String {
        switch mode {
        case .haptic: return "진동만"
        case .beep: return "비프만"
        case .both: return "진동 + 비프"
        }
    }
    static func toneLabel(_ tone: WarningTone) -> String {
        switch tone {
        case .sharp: return "날카로운 삑 (처음)"
        case .soft: return "부드러운 삑"
        case .low: return "낮은 삑"
        case .pluck: return "톡 (마림바)"
        case .thump: return "낮은 둥 (진동 느낌)"
        }
    }
    static func angle(_ value: Double?) -> String { value.map { String(format:"%+.0f°",$0) } ?? "—" }
}
