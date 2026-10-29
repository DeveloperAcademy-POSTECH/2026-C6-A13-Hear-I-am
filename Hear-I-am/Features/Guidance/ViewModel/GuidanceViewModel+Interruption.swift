import AVFoundation
import HearIAmCore

/// 안내 중단 · 나가기: lost tracking, audio interruptions, backgrounding and exit confirmation.
extension GuidanceViewModel {
    /// Keeps the current target and asks the wearer to verify the checkpoint again.
    func interrupt(_ reason: String, announce: Bool = true) {
        if phase == .completed { return }
        invalidateTasks()
        if phase == .finishing { message="종료 음성이 중단됐어요. 다시 들은 뒤 종료해주세요.";return }
        if phase == .selection { return }
        guide?.pause();phase = .interrupted;departureReady=false;departureGate.reset();message=reason
        tracking.endSession()
        if announce && active { read([voiceShouldListen ? VoiceStepCopy.interrupted : "위치 또는 소리를 확인할 수 없어 안내를 멈췄습니다. 잠시 멈춰주세요. 휴대폰을 손에 들고 확인점을 다시 확인해주세요."]) }
    }
    func setActive(_ value: Bool) {
        guard active != value else { return };active=value
        if voiceExperiment {
            if !value {
                voiceListeningEnabled=false
                stopVoiceExperiment()
            } else {
                // Back in the app, listening resumes by itself; there is no retry button on screen.
                voiceInputError=nil;voiceListeningEnabled=true;voiceReadyChimePending=true
                syncVoiceListening()
            }
        }
        if !value {
            interrupt("앱이 중단됐어요. 확인점과 착용 상태를 다시 확인해주세요.",announce:false)
            tracking.setActive(false)
        } else {
            tracking.setActive(true)
            if phase == .interrupted { read(["안내를 멈췄습니다. 휴대폰을 손에 들고 확인점을 다시 확인해주세요."]) }
            else if phase == .selection { replay() }
        }
    }
    func requestExit() {
        guard phase != .finishing else { return }
        if phase == .guiding || phase == .starting { guide?.pause();phase = started ? .paused : .departure }
        invalidateTasks();showExit=true
        syncVoiceListening()
        read(["안내를 끝낼까요? 계속 사용하려면 계속 사용하기를 눌러주세요."])
    }
    func cancelExit() { showExit=false;replay();syncVoiceListening() }

    func observeAudioSession() {
        observations.append(NotificationCenter.default.addObserver(forName:AVAudioSession.interruptionNotification,object:nil,queue:.main) { [weak self] n in
            guard let raw=n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue:raw) == .began else { return }
            Task { @MainActor in
                self?.voice.audioWasInterrupted();self?.signals.stop()
                self?.interrupt("음성 재생이 중단됐어요. 확인점과 착용 상태를 다시 확인해주세요.",announce:false)
            }
        })
        observations.append(NotificationCenter.default.addObserver(forName:AVAudioSession.routeChangeNotification,object:nil,queue:.main) { [weak self] n in
            guard let raw=n.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue:raw) == .oldDeviceUnavailable else { return }
            Task { @MainActor in self?.interrupt("소리 출력이 변경됐어요. 확인점과 착용 상태를 다시 확인해주세요.") }
        })
    }
}
