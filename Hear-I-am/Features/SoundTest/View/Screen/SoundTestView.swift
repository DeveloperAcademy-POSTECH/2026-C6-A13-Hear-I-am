import SwiftUI
import HearIAmCore

/// Temporary fourth tab for real-device signal checks. Remove with the SoundTest folder after testing.
struct SoundTestView: View {
    @StateObject private var model=SoundTestViewModel()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:6) {
                        Text("실기기 확인용 임시 화면이에요. 테스트가 끝나면 지워요.").font(.subheadline).foregroundStyle(.secondary)
                        Text("마지막 기록: "+model.lastEvent).font(.caption.monospaced()).lineLimit(2)
                        Text(model.logStatus).font(.caption).foregroundStyle(.secondary)
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
            SoundTestRow(label:"방향 교정 음성") {
                ForEach([SignalCopy.turnLeft,SignalCopy.turnRight,SignalCopy.turnBack],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"단상 · 계단 음성") {
                ForEach([SignalCopy.stepUp(stairs:false),SignalCopy.stepUp(stairs:true),SignalCopy.stepDown],id:\.self) { line in
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
            SoundTestRow(label:"30° 눈금 진동 (0° = 목표 방향)") {
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
                    ForEach([40.0,60,80],id:\.self) { hertz in
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
            SoundTestRow(label:"시작") {
                ActionButton(title:"몸으로 찾기",enabled:model.trial == nil) { model.startTrial(.body) }
                ActionButton(title:"고개로 찾기",enabled:model.trial == nil) { model.startTrial(.head) }
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
