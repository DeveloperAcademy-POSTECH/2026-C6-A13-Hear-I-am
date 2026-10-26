import SwiftUI
import AVFoundation
import HearIAmCore

/// Preview playback is exclusive and never changes the shipping guidance rules or timbres.
@MainActor final class SoundTestViewModel: ObservableObject {
    @Published private(set) var activeID: String?
    @Published private(set) var activeTitle=""
    @Published private(set) var error: String?
    let signals=SignalPlayer()
    let voice=GuidanceSpeech()
    let log=SoundTestLog()
    private var playbackTask: Task<Void,Never>?
    private var generation=UUID()
    private var speechStarted=false
    private var observers: [NSObjectProtocol]=[]

    init() {
        signals.onEvent={ [weak self] event, detail in
            self?.log.record(event,detail)
            if event == "signal_error" { self?.fail("소리를 재생하지 못했어요. 연결 기기와 음량을 확인한 뒤 다시 눌러주세요.") }
        }
        voice.onSpeaking={ [weak self] speaking in
            guard let self else { return }
            self.signals.setSpeechActive(speaking)
            if speaking { self.speechStarted=true }
            else if self.speechStarted { self.speechStarted=false;self.finish() }
        }
        voice.onError={ [weak self] in self?.fail($0) }
        observers.append(NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] _ in
            Task { @MainActor in self?.stop();HearAudioSession.interrupted() }
        })
        observers.append(NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] note in
            let reason=(note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            guard reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
            Task { @MainActor in self?.stop() }
        })
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func appear() { _=log.open();log.record("tutorial_open",HearAudioSession.route) }
    func disappear() {
        stop();signals.shutdown();voice.deactivate()
        log.record("tutorial_close","");log.close()
    }
    func stop() {
        generation=UUID();playbackTask?.cancel();playbackTask=nil
        activeID=nil;activeTitle="";speechStarted=false
        signals.stop();voice.stop()
    }
    func clearError() { error=nil }
    func outputPreferenceChanged() {
        stop();error=nil
        signals.shutdown();HearAudioSession.deactivate()
        do { try HearAudioSession.activate() }
        catch { fail("소리 출력을 바꾸지 못했어요. 연결 기기를 확인한 뒤 다시 시도해주세요.") }
    }
    func explain(_ step: SoundTestSection) {
        play(.init("explanation-\(step.id)","설명 듣기",step.explanation,playback:.speech(step.explanation+" "+step.together)))
    }
    func play(_ example: SignalTutorialExample) {
        if activeID == example.id { stop();return }
        stop();error=nil
        guard AVAudioSession.sharedInstance().outputVolume > 0 else {
            fail("소리가 꺼져 있어요. iPhone의 음량을 올린 뒤 다시 들어보세요.");return
        }
        activeID=example.id;activeTitle=example.title
        let token=generation
        log.record("tutorial_preview",example.id)
        switch example.playback {
        case .directionTick(let right): playTone(.directionTick(toRight:right),token:token)
        case .aligned: playTone(.aligned(tone:SignalPlayer.savedAlignedTone),token:token)
        case .arrival: playTone(.arrival,token:token)
        case .speech(let line):
            if !voice.play([line]) { finish() }
        case .nextSide(let line):
            if !voice.direction(line,volume:SignalVolume.nextSide) { finish() }
        case .completion:
            signals.play(.arrival)
            guard generation == token else { return }
            playbackTask=Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds:UInt64(GuidanceViewModel.dingBeforeSpeech*1e9)) }
                catch { return }
                guard let self, self.generation == token else { return }
                if !self.voice.play([GuidanceCopy.completed]) { self.finish() }
            }
        }
    }
    private func playTone(_ sound: SignalSound, token: UUID) {
        signals.play(sound)
        guard generation == token else { return }
        let duration=Double(ToneRenderer.render(sound).count)/ToneRenderer.sampleRate
        playbackTask=Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds:UInt64(duration*1e9)) }
            catch { return }
            guard let self, self.generation == token else { return }
            self.finish()
        }
    }
    private func finish() { activeID=nil;activeTitle="";playbackTask=nil }
    private func fail(_ message: String) { stop();error=message }
}
