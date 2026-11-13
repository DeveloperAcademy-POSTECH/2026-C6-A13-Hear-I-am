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
    @Published private(set) var caption=VoiceHomeCaption()
    @Published private(set) var confirmingInput=false
    /// Why the call cannot be heard (no permission, dictation off); nil while listening works.
    @Published private(set) var failure: String?
    var onRequest: ((String) -> Void)?
    var visualization: VoiceInputVisualization {recognition.inputVisualization}

    /// Read each time: a stored line kept the language of the first call after launch, so after switching the
    /// app back to Korean the Korean voice read the English question aloud (11/13 POS).
    static var greeting: String {VoiceAppRequest.homeQuestion[0]}
    private let recognition=VoiceRecognitionService()
    private let speech=GuidanceSpeech()
    private let chime=VoiceListeningChime()
    private var startTask: Task<Void,Never>?
    private var sleepTask: Task<Void,Never>?
    private var resumeTask: Task<Void,Never>?
    /// What the agent last said, and whether the request now heard began while it was saying it (11/01).
    private var spokenLines: [String]=[]
    private var heardOverSpeech=false
    private var active=false
    /// The answer whose end opens the next screen; a tap or sleep in between cancels it.
    private var answerID: UUID?
    /// The conversation was opened with the orb rather than the call, so it waits longer for the request.
    private var openedByTap=false
    /// What the performer asked and what the agent answered on Home, shown as the chat before another
    /// screen opens (「스캔하자」 → the scan answer, 11/03).
    @Published private(set) var answerRequest: String?
    @Published private(set) var answerLines: [String]=[]
    private var narrationHeld=false
    /// The performer's own words, beyond the agent's echo, have been heard since the agent last spoke.
    private var userSpoke=false
    private var loggedOverSpeech=false

    init() {
        // Speak through the recognizer's engine so its echo cancellation hears the user over the greeting.
        speech.bufferedOutput={ [weak self] utterance, completion in
            self?.recognition.speakNarration(utterance,completion:completion) ?? false
        }
        speech.stopBufferedOutput={ [weak self] in self?.recognition.stopNarration() }
        speech.onText={ [weak self] text in self?.caption.updateNarration(text) }
        speech.onSpeaking={ [weak self] value in self?.speaking=value }
        recognition.onTranscript={ [weak self] text in self?.heardPartial(text) }
        // Sound over the question holds it at once; it goes on if no words follow (11/03).
        recognition.onSpeechDetected={ [weak self] in self?.holdNarration() }
        recognition.onFinal={ [weak self] text in self?.heardFinal(text) }
        recognition.onRecoverableError={ [weak self] _ in self?.caption.clearRequest() }
        recognition.$finalizing.assign(to:&$confirmingInput)
        // A permission or dictation failure shows a fallback button; the next visit to Home tries again.
        // Opened by a tap, the conversation stays on screen with the reason instead of dropping back.
        recognition.onError={ [weak self] message in
            guard let self else {return}
            self.active=false;self.failure=message
            VoiceLog.write("home_voice_error",message,screen:self.awake ? "home.awake" : "home.asleep")
            if !self.awake {self.sleep(reason:"error")}
        }
        // A call, another app's sound or a headset change: listen again shortly, if the app is still in front.
        // The conversation, if open, waits on screen for the microphone to come back.
        recognition.onExternalStop={ [weak self] message in
            guard let self else {return}
            self.active=false
            VoiceLog.write("home_voice_stopped",message,screen:self.awake ? "home.awake" : "home.asleep")
            if !self.awake {self.sleep(reason:"external")}
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
        sleep(reason:"stop")
        guard active else {return}
        active=false
        startTask?.cancel();startTask=nil
        recognition.stop()
    }

    /// The same conversation can be opened with the orb when saying the wake phrase is inconvenient.
    /// The screen opens on the tap itself; the microphone is readied or restarted behind it, and a
    /// failure is shown there rather than sending the performer back to the waiting screen.
    func beginConversation() {
        guard !awake else {return}
        VoiceLog.write("home_woke","tap",screen:"home.asleep")
        // A listener that stopped or failed earlier is started afresh; a healthy one just switches to Korean.
        if !active || failure != nil {active=false;start()}
        wake()
        openedByTap=true
        Task { @MainActor [weak self] in
            guard let self else {return}
            await self.startTask?.value
            guard self.awake else {return}
            guard self.failure == nil else {return}
            self.recognition.listenInEnglish(false)
            self.greet()
        }
    }

    /// In English the app's own voice comes back through the microphone as words: its 「Yes, …」 was heard as
    /// 「Yes」, or as 「I talked about it」, and cut the question every time (11/13 POS). Korean recognition
    /// leaves it out or the echo checks catch it; English does not. So in English nothing heard while the app
    /// speaks stops it except the call 「Hear I am」, and what was heard over it is not taken as a request.
    private var callOnlyOverSpeech: Bool {HearLanguage.current.isEnglish}

    private func heardPartial(_ text:String) {
        guard active else {return}
        if awake, speaking, callOnlyOverSpeech, !recognition.listensInEnglish {
            heardOverSpeech=true
            if VoiceWakeWord.matches(text), !spokenLines.contains(where:VoiceWakeWord.matches) {
                VoiceLog.write("home_barge_in","call \(text)",screen:"home.awake")
                narrationHeld=false
                speech.stop()
            } else if !loggedOverSpeech {
                loggedOverSpeech=true
                VoiceLog.write("home_over_speech",text,screen:"home.awake")
            }
            stayAwake(8);return
        }
        // Someone is still talking to the agent; it must not fall asleep in the middle of the request.
        if awake, !recognition.listensInEnglish {
            let words=heardOverSpeech || speaking ? VoiceEcho.strippingLeadingEcho(text,of:spokenLines) : text
            let request=words.isEmpty || VoiceEcho.isEcho(words,of:spokenLines) ? nil : VoiceNoise.request(words)
            // Marked before the agent is stopped: stopping ends its speech at once, and a turn not yet marked
            // as the performer's was thrown away with 「저장된」 in it, leaving only 「보여줘」 (11/03).
            if request != nil {userSpoke=true}
            if speaking {
                heardOverSpeech=true
                // The performer talking over the question cuts it, as a person would stop (11/03). One word
                // the question also holds (「스캔」, 「연습」) counts once their voice has held the question.
                if let request, narrationHeld || request.contains(" ") || !spokenLines.joined().contains(request) {
                    VoiceLog.write("home_barge_in",request,screen:"home.awake")
                    narrationHeld=false
                    speech.stop()
                } else if !loggedOverSpeech {
                    loggedOverSpeech=true
                    VoiceLog.write("home_over_speech",text,screen:"home.awake")
                }
            }
            if let request, VoiceAppRequest.resolve(request) != nil || VoiceAppRequest.isRehearsal(request) {recognition.finishSoon()}
            caption.receivePartial(text,isAwake:awake,isEnglish:recognition.listensInEnglish,
                                   overlappingNarration:heardOverSpeech,spokenLines:spokenLines)
            stayAwake(8);return
        }
        guard !awake, VoiceWakeWord.matches(text) else {return}
        // Switching to Korean ends this English turn, so the greeting cannot wait for its final text.
        VoiceLog.write("home_woke","call \(text)",screen:"home.asleep")
        wake();greet()
    }

    private func heardFinal(_ text:String,typed:Bool=false) {
        guard active || typed else {return}
        // Room noise (「.」, 「아.」, 「그」) is no call and no request; fillers around real words are dropped.
        guard let text=VoiceNoise.request(text) else {caption.clearRequest();return}
        VoiceLog.write(recognition.listensInEnglish ? "home_heard_english" : "home_heard",([text]+recognition.lastAlternatives.filter {$0 != text}).joined(separator:" | "),screen:awake ? "home.awake" : "home.asleep")
        // The call may sit in a lower recognition candidate (#92).
        let call=([text]+recognition.lastAlternatives).lazy.compactMap(VoiceWakeWord.request(in:)).first
        if let request=call {
            if !awake {wake()}
            if request.isEmpty {caption.clearRequest();if !speaking {greet()}} else {hand(request)}
            return
        }
        guard awake, !recognition.listensInEnglish else {return}
        // Heard over the app's English speech without the call: the app's own voice (see callOnlyOverSpeech).
        if callOnlyOverSpeech, heardOverSpeech {
            heardOverSpeech=false
            caption.clearRequest();VoiceLog.write("home_ignored","over speech \(text)",screen:"home.awake");return
        }
        // 「닫기」 closes the conversation; dictation often writes it 「찾기」 or 「받기」 (11/03).
        if VoiceCommandParser.isClose(text) || (text.count <= 4 && VoiceCommandParser.parse(text) == nil && recognition.lastAlternatives.contains(where:VoiceCommandParser.isClose)) {
            VoiceLog.write("home_close",text,screen:"home.awake");sleep(reason:"voice close");return
        }
        // The question itself can come back through the microphone ahead of the answer.
        var request=text
        // A whole request in the question's own words (「저장된 공연으로 연습할래」) is the performer's, not echo.
        if heardOverSpeech, VoiceAppRequest.resolve(text) == nil, !VoiceAppRequest.isRehearsal(text) {
            heardOverSpeech=false
            request=VoiceEcho.strippingLeadingEcho(text,of:spokenLines)
            if request.isEmpty {caption.clearRequest();VoiceLog.write("home_ignored","echo \(text)",screen:"home.awake");return}
        }
        hand(request)
    }

    #if DEBUG
    /// A line typed for testing is taken like final speech: the call wakes, a request opens guidance.
    func simulateHeard(_ text:String) {heardFinal(text,typed:true)}
    #endif

    private func wake() {
        caption.reset();answerRequest=nil;answerLines=[]
        awake=true;openedByTap=false
        speech.stop()
        recognition.listenInEnglish(false)
        chime.play()
        stayAwake(8)
    }

    private func greet() {
        caption.clearRequest()
        stayAwake(60)
        spokenLines=[Self.greeting];heardOverSpeech=false;userSpoke=false;loggedOverSpeech=false
        speech.play([Self.greeting]) { [weak self] _ in self?.afterSpeaking() }
    }

    private func hand(_ request:String) {
        // A scan or plans request heard slightly wrong may be right in a lower candidate (「스캔 스캔 스킨」).
        var request=request
        if VoiceAppRequest.resolve(request) == nil,
           let other=recognition.lastAlternatives.map({VoiceWakeWord.request(in:$0) ?? $0}).first(where:{VoiceAppRequest.resolve($0) != nil}) {
            VoiceLog.write("home_alternative","\(request) -> \(other)",screen:"home.awake");request=other
        }
        // The microphone keeps running: an answer on Home plays through it, and restarting it here left
        // the scan answer unheard (11/03). Opening guidance stops it from the root view.
        sleep(reason:"handed")
        onRequest?(request)
    }
    private func holdNarration() {
        // In English the app's own voice sets this off as well; holding for it stuttered every question.
        guard awake, speaking, !narrationHeld, !recognition.listensInEnglish, !callOnlyOverSpeech else {return}
        narrationHeld=true
        recognition.holdNarration(true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:1_300_000_000)
            guard let self, self.narrationHeld else {return}
            self.narrationHeld=false
            if self.speaking {self.recognition.holdNarration(false)}
        }
    }

    /// Answers a request on the spot instead of opening guidance. The conversation stays open for a
    /// follow-up, as after the greeting, then goes back to waiting for the call. `then` runs once the
    /// answer has been said, unless the agent was closed first.
    func answer(_ lines:[String],request:String? = nil,then next:(() -> Void)? = nil) {
        caption.reset()
        answerRequest=request;answerLines=lines
        awake=true
        // Handing the request over left the recognizer in English; a follow-up comes in Korean.
        recognition.listenInEnglish(false)
        start()
        stayAwake(60)
        let id=UUID();answerID=id
        spokenLines=lines;heardOverSpeech=false;userSpoke=false;loggedOverSpeech=false
        speech.play(lines) { [weak self] _ in
            guard let self else {return}
            self.afterSpeaking()
            guard self.answerID == id else {return}
            self.answerID=nil;next?()
        }
    }

    /// The agent finished speaking. A turn that heard only its voice starts again, so the request is
    /// timed from the performer's own words (13 s on 11/03, whatever they said).
    private func afterSpeaking() {
        stayAwake(10)
        guard awake, !userSpoke, !recognition.listensInEnglish else {return}
        heardOverSpeech=false;caption.clearRequest()
        recognition.restartIdleTurn()
    }

    /// A tap closes the agent and goes back to waiting for 「Hear I am」.
    func dismiss() {
        guard awake else {return}
        sleep(reason:"tap")
    }

    private func stayAwake(_ seconds:Double) {
        sleepTask?.cancel()
        sleepTask=Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000))
            guard !Task.isCancelled else {return}
            self?.sleep(reason:"quiet \(Int(seconds))s")
        }
    }

    private func sleep(reason:String) {
        sleepTask?.cancel();sleepTask=nil;answerID=nil
        if speaking {speech.stop()}
        if awake {VoiceLog.write("home_slept",reason,screen:"home.awake")}
        awake=false;openedByTap=false;narrationHeld=false
        caption.reset();answerRequest=nil;answerLines=[]
        if active {recognition.listenInEnglish(true)}
    }
}
