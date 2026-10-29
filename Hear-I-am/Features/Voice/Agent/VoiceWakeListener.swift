import Foundation
import UIKit
import Combine
import HearIAmCore

/// The voice agent on every tab (#90). While asleep it only waits for 「히얼아이엠」; speech without the call
/// belongs to someone else and is ignored. Once called it greets, takes one request and hands it to
/// guidance, or falls asleep again after a quiet while.
@MainActor final class VoiceWakeListener: ObservableObject {
    @Published private(set) var listening=false
    @Published private(set) var awake=false
    @Published private(set) var speaking=false
    /// Why the call cannot be heard (no permission, dictation off); nil while listening works.
    @Published private(set) var failure: String?
    var onRequest: ((String) -> Void)?
    var visualization: VoiceInputVisualization {recognition.inputVisualization}

    static let greeting="네, 어떤 무대를 준비할까요?"
    private let recognition=VoiceRecognitionService()
    private let speech=GuidanceSpeech()
    private let chime=VoiceListeningChime()
    private var startTask: Task<Void,Never>?
    private var sleepTask: Task<Void,Never>?
    private var resumeTask: Task<Void,Never>?
    private var active=false
    /// The answer whose end opens the next screen; a tap or sleep in between cancels it.
    private var answerID: UUID?

    init() {
        // Speak through the recognizer's engine so its echo cancellation hears the user over the greeting.
        speech.bufferedOutput={ [weak self] utterance, completion in
            self?.recognition.speakNarration(utterance,completion:completion) ?? false
        }
        speech.stopBufferedOutput={ [weak self] in self?.recognition.stopNarration() }
        speech.onSpeaking={ [weak self] value in self?.speaking=value }
        recognition.onTranscript={ [weak self] text in self?.heardPartial(text) }
        recognition.onFinal={ [weak self] text in self?.heardFinal(text) }
        // A permission or dictation failure shows a fallback button; the next visit to Home tries again.
        recognition.onError={ [weak self] message in self?.active=false;self?.failure=message;self?.sleep() }
        // A call, another app's sound or a headset change: listen again shortly, if the app is still in front.
        recognition.onExternalStop={ [weak self] _ in
            guard let self else {return}
            self.active=false;self.sleep()
            self.resumeTask=Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds:1_500_000_000)
                guard !Task.isCancelled, UIApplication.shared.applicationState == .active else {return}
                self?.start()
            }
        }
        recognition.$isListening.receive(on:RunLoop.main).assign(to:&$listening)
    }

    func start() {
        guard !active else {return}
        active=true;failure=nil
        startTask=Task { [weak self] in
            guard let self, self.active else {return}
            await self.recognition.start(contextualStrings:VoiceWakeWord.hints,vocabulary:VoiceVocabulary.phrases(),listensForWakeWord:true)
            // Asleep, Home listens in English for 「Hear I am」 only (#92).
            if self.active, !self.awake {self.recognition.listenInEnglish(true)}
        }
    }

    func stop() {
        resumeTask?.cancel();resumeTask=nil
        sleep()
        guard active else {return}
        active=false
        startTask?.cancel();startTask=nil
        recognition.stop()
    }

    private func heardPartial(_ text:String) {
        guard active else {return}
        // Someone is still talking to the agent; it must not fall asleep in the middle of the request.
        if awake, !recognition.listensInEnglish {stayAwake(8);return}
        guard !awake, VoiceWakeWord.matches(text) else {return}
        // Switching to Korean ends this English turn, so the greeting cannot wait for its final text.
        wake();greet()
    }

    private func heardFinal(_ text:String) {
        guard active else {return}
        // The call may sit in a lower recognition candidate (#92).
        let call=([text]+recognition.lastAlternatives).lazy.compactMap(VoiceWakeWord.request(in:)).first
        if let request=call {
            if !awake {wake()}
            if request.isEmpty {if !speaking {greet()}} else {hand(request)}
            return
        }
        guard awake, !recognition.listensInEnglish else {return}
        hand(text)
    }

    private func wake() {
        awake=true
        speech.stop()
        recognition.listenInEnglish(false)
        chime.play()
        stayAwake(8)
    }

    private func greet() {
        stayAwake(60)
        speech.play([Self.greeting]) { [weak self] _ in self?.stayAwake(8) }
    }

    private func hand(_ request:String) {
        stop()
        onRequest?(request)
    }

    /// Answers a request on the spot instead of opening guidance. The conversation stays open for a
    /// follow-up, as after the greeting, then goes back to waiting for the call. `then` runs once the
    /// answer has been said, unless the agent was closed first.
    func answer(_ lines:[String],then next:(() -> Void)? = nil) {
        awake=true
        // Handing the request over left the recognizer in English; a follow-up comes in Korean.
        recognition.listenInEnglish(false)
        start()
        stayAwake(60)
        let id=UUID();answerID=id
        speech.play(lines) { [weak self] _ in
            guard let self else {return}
            self.stayAwake(8)
            guard self.answerID == id else {return}
            self.answerID=nil;next?()
        }
    }

    /// A tap closes the agent and goes back to waiting for 「Hear I am」.
    func dismiss() {
        guard awake else {return}
        sleep()
    }

    private func stayAwake(_ seconds:Double) {
        sleepTask?.cancel()
        sleepTask=Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
            guard !Task.isCancelled else {return}
            self?.sleep()
        }
    }

    private func sleep() {
        sleepTask?.cancel();sleepTask=nil;answerID=nil
        if speaking {speech.stop()}
        awake=false
        if active {recognition.listenInEnglish(true)}
    }
}
