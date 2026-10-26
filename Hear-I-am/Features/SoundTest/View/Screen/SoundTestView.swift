import SwiftUI
import HearIAmCore

/// Signal tutorial tab (#74): lets visually impaired users hear and practice the active guidance signals.
struct SoundTestView: View {
    @StateObject private var model=SoundTestViewModel()
    @AppStorage(HearAudioSession.speakerKey) private var forcesSpeaker=false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("무대 안내 중에 들리는 신호음과 음성 안내를 미리 들어보고 익힐 수 있어요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        // Same setting as 홈 설정 › 소리 출력; the next sound plays through the new output.
                        Toggle("폰 스피커로 듣기 (끄면 에어팟)",isOn:$forcesSpeaker).font(.subheadline)
                            .onChange(of:forcesSpeaker) {_,value in model.record("audio_output",value ? "speaker" : "auto")}
                    }
                    SoundTestCard(section:.sounds) { sounds }
                    SoundTestCard(section:.speech) { speech }
                }.padding(.horizontal,20).padding(.vertical,16)
            }.navigationTitle("신호 튜토리얼")
        }
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
    }

    private var sounds: some View {
        VStack(alignment:.leading,spacing:16) {
            SoundTestRow(label:"방향 찾기 (톡톡톡 · 왼쪽 낮게 / 오른쪽 높게, 가까워질수록 빨라짐)") {
                ActionButton(title:"왼쪽 톡",primary:false) { model.tick(toRight:false) }
                ActionButton(title:"오른쪽 톡",primary:false) { model.tick(toRight:true) }
            }
            SoundTestRow(label:"방향 맞음 (목표 정면 ±15° 안에 들어오면 울림)") {
                ActionButton(title:"방향 맞음 (깊은 우드)",primary:false) { model.playAligned() }
            }
            SoundTestRow(label:"출발 준비 완료 · 마지막 지점 도착 신호음") {
                ActionButton(title:"띵",primary:false) { model.playArrival() }
            }
        }
    }

    private var speech: some View {
        VStack(alignment:.leading,spacing:16) {
            SoundTestRow(label:"출발 안내 (안내 시작 직후)") {
                ActionButton(title:SignalCopy.start,primary:false) { model.speak(SignalCopy.start) }
            }
            SoundTestRow(label:"중간 목표 지점 도착 (P1, 의자1, 계단1... 지점 이름을 말해요)") {
                ForEach([SignalCopy.point(1),SignalCopy.point(2),SignalCopy.stepPoint(stairs:false,number:1),SignalCopy.stepPoint(stairs:true,number:1)],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"마지막 지점 도착 (띵 소리 0.7초 뒤 완료 안내)") {
                ActionButton(title:"띵 + \(GuidanceCopy.completed)",primary:false) { model.playCompletionPreview() }
                ActionButton(title:GuidanceCopy.completed,primary:false) { model.speak(GuidanceCopy.completed) }
            }
            SoundTestRow(label:"다음 지점 방향 (출발 · 지점 도착 직후 크게 안내)") {
                ForEach([SignalCopy.right,SignalCopy.left],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speakNextSide(line) }
                }
            }
            SoundTestRow(label:"방향이 틀렸을 때 (톡톡톡 시작 전 1회 안내)") {
                ForEach([SignalCopy.right,SignalCopy.left],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"의자 · 계단 사전 암시 (방향 맞음 후 거리 안내 전 1회 안내)") {
                ForEach([SignalCopy.stepHint(stairs:false),SignalCopy.stepHint(stairs:true)],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"남은 거리") {
                ForEach([3.0,2,1,0.5],id:\.self) { meters in
                    let line=SignalCopy.distance(meters)
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
            SoundTestRow(label:"의자 · 계단 도착 후 바라볼 방향 (초록색 변 방향으로 몸 돌리기)") {
                ForEach([SignalCopy.look(toRight:true),SignalCopy.look(toRight:false)],id:\.self) { line in
                    ActionButton(title:line,primary:false) { model.speak(line) }
                }
            }
        }
    }
}
