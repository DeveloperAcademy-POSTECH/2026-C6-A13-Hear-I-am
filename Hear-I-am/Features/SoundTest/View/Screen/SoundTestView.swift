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
                        Text("안내에서 쓰는 소리만 모았어요. 테스트가 끝나면 지워요.").font(.subheadline).foregroundStyle(.secondary)
                        Text("마지막 기록: "+model.lastEvent).font(.caption.monospaced()).lineLimit(2)
                        Text(model.logStatus).font(.caption).foregroundStyle(.secondary)
                        // Same setting as 홈 설정 › 소리 출력; the next sound plays through the new output.
                        Toggle("폰 스피커로 듣기 (끄면 에어팟)",isOn:$forcesSpeaker).font(.subheadline)
                            .onChange(of:forcesSpeaker) {_,value in model.record("audio_output",value ? "speaker" : "auto")}
                    }
                    SoundTestCard(section:.sounds) { sounds }
                    SoundTestCard(section:.speech) { speech }
                }.padding(.horizontal,20).padding(.vertical,16)
            }.navigationTitle("소리 테스트")
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
    }

    private var sounds: some View {
        VStack(alignment:.leading,spacing:16) {
            SoundTestRow(label:"장애물 경고 · \(Self.toneLabel(model.warningTone)) (반복, 다시 누르면 꺼짐)") {
                ForEach(WarningLevel.allCases,id:\.self) { level in
                    ActionButton(title:["1m","0.6m","0.35m"][level.rawValue-1],primary:model.warning == level) {
                        model.setWarning(model.warning == level ? nil : level)
                    }
                }
            }
            SoundTestRow(label:"지점 · 도착점 도착") { ActionButton(title:"띵",primary:false) { model.playArrival() } }
            SoundTestRow(label:"방향 (톡톡톡 · 왼쪽 낮게 / 오른쪽 높게)") {
                ActionButton(title:"왼쪽 톡",primary:false) { model.tick(toRight:false) }
                ActionButton(title:"오른쪽 톡",primary:false) { model.tick(toRight:true) }
                ActionButton(title:"방향 맞음",primary:false) { model.playAligned() }
            }
        }
    }

    private var speech: some View {
        VStack(alignment:.leading,spacing:16) {
            SoundTestRow(label:"다음 지점 쪽 (출발 · 띵 뒤에, 크게)") {
                ForEach([SignalCopy.right,SignalCopy.left],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speakNextSide(line) }
                }
            }
            SoundTestRow(label:"방향이 틀렸을 때") {
                ForEach([SignalCopy.right,SignalCopy.left],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"남은 거리") {
                ForEach([3.0,2,1,0.5],id:\.self) { meters in
                    let line=SignalCopy.distance(meters)
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"의자 · 계단") {
                ForEach([SignalCopy.stepUp(stairs:false),SignalCopy.stepUp(stairs:true),SignalCopy.stepOver(stairs:false),
                         SignalCopy.stepOver(stairs:true),SignalCopy.stepDown],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"빠져나오기") {
                ForEach([SignalCopy.escape(toRight:true),SignalCopy.escape(toRight:false),"다시 안내합니다"],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
        }
    }

    static func toneLabel(_ tone: WarningTone) -> String {
        switch tone {
        case .sharp: return "날카로운 삑"
        case .soft: return "부드러운 삑"
        case .low: return "낮은 삑"
        case .pluck: return "톡 (마림바)"
        case .thump: return "낮은 둥"
        }
    }
}
