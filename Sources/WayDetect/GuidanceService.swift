import AVFoundation
import Combine
import CoreHaptics
import UIKit
import WayDetectCore

@MainActor
final class GuidanceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let feedback = HapticFeedback()
    private var activeUtterance: ObjectIdentifier?
    private var ownsAudioSession = false
    var onStart: ((String) -> Void)?
    var onFinish: ((String) -> Void)?
    var onFailure: ((String) -> Void)?
    override init() { super.init(); synthesizer.delegate = self }
    func speak(_ cue: GuidanceCue, voice: Bool, haptics: Bool) {
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        feedback.stop()
        if haptics { feedback.play(cue.haptic) }
        guard voice else {
            releaseAudioSession()
            return
        }
        let text = cue.speech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            releaseAudioSession()
            return
        }
        if UIAccessibility.isVoiceOverRunning {
            // Avoid speaking over VoiceOver with a second speech engine.
            releaseAudioSession()
            // Replace outdated navigation speech instead of queuing it. Do not
            // suppress identical text: a stop cue or an explicit replay must speak.
            let announcement = NSAttributedString(string: text, attributes: [
                .accessibilitySpeechQueueAnnouncement: false,
                .accessibilitySpeechLanguage: "ko-KR"
            ])
            UIAccessibility.post(notification: .announcement, argument: announcement)
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            ownsAudioSession = true
        } catch {
            feedback.stop()
            if haptics { feedback.play(.warning) }
            releaseAudioSession()
            onFailure?("음성 오류. 오디오를 확인하세요.")
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        activeUtterance = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }
    func stop() {
        activeUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        feedback.stop()
        releaseAudioSession()
    }
    private func releaseAudioSession() {
        guard ownsAudioSession else { return }
        ownsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance == identifier else { return }
            self.onStart?(text)
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        let identifier = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeUtterance == identifier else { return }
            self.activeUtterance = nil
            self.onFinish?(text)
            self.releaseAudioSession()
        }
    }
}

/// Event patterns supplement speech; they do not encode left versus right.
/// Always replace the previous pattern so an old cue cannot follow a stop cue.
@MainActor
private final class HapticFeedback {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?

    func play(_ cue: HapticCue) {
        stop()
        guard cue != .none else { return }
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            fallback(cue); return
        }
        do {
            let engine = try prepareEngine()
            try engine.start()
            let pattern = try CHHapticPattern(events: events(for: cue), parameters: [])
            let nextPlayer = try engine.makePlayer(with: pattern)
            player = nextPlayer
            try nextPlayer.start(atTime: CHHapticTimeImmediate)
        } catch {
            stop(); engine = nil
            fallback(cue)
        }
    }

    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    private func prepareEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let next = try CHHapticEngine()
        next.playsHapticsOnly = true
        next.isAutoShutdownEnabled = true
        next.resetHandler = { [weak self, weak next] in
            Task { @MainActor in
                guard let self, let next, self.engine === next else { return }
                // Rebuild on the next instruction; never replay an outdated cue after a reset.
                self.engine = nil; self.player = nil
            }
        }
        engine = next
        return next
    }

    private func events(for cue: HapticCue) -> [CHHapticEvent] {
        func tap(_ time: Double, intensity: Float, sharpness: Float) -> CHHapticEvent {
            CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ], relativeTime: time)
        }
        switch cue {
        case .none: return []
        case .start: return [tap(0, intensity: 0.7, sharpness: 0.5)]
        case .turn: return [tap(0, intensity: 0.9, sharpness: 0.75), tap(0.18, intensity: 0.9, sharpness: 0.75)]
        case .stop:
            return [CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.85),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ], relativeTime: 0, duration: 0.45)]
        case .success: return [tap(0, intensity: 0.4, sharpness: 0.2), tap(0.32, intensity: 0.55, sharpness: 0.2)]
        case .warning: return [0.0, 0.2, 0.4].map { tap($0, intensity: 1, sharpness: 0.9) }
        }
    }

    private func fallback(_ cue: HapticCue) {
        // UIKit provides a best-effort standard cue if custom haptics are unavailable.
        switch cue {
        case .none: break
        case .start: UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .turn: UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .stop: UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }
}
