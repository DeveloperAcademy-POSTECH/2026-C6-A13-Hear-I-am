import Foundation
import Combine
import HearIAmCore

/// Opt-in #69 experiment. Commands use the same guards as the existing touch controls.
extension GuidanceViewModel {
    func voicePointName(_ index:Int) -> String {guide?.route.pointLabel(at:index) ?? "지점"}
    /// What the current screen can do, offered to the Apple Intelligence model (#87).
    var voiceScreen: VoiceScreen {
        switch phase {
        case .selection: return voiceChoosingMode ? .modeChoice : .stageList(stageCount:visibleVoiceStages.count)
        case .starting,.guiding,.paused:
            return .guidance(pointCount:voiceMode == .practice && started ? max(0,(guide?.route.points.count ?? 0)-1) : 0)
        case .failed,.interrupted: return .recovery
        default: return .preparation
        }
    }

    var voiceCanOfferInput: Bool {
        guard voiceExperiment, active, !showExit, !savingRecord, escape == nil, audioIssue == nil else {return false}
        if voiceMode == .performance && voicePerformanceInputClosed {return false}
        return [.selection,.restoring,.checkpoint,.wear,.departure,.starting,.guiding,.paused,.failed,.interrupted].contains(phase)
    }
    var voiceShouldListen: Bool { voiceCanOfferInput && voiceListeningEnabled }
    /// True after 「히얼아이엠」 until the conversation has been quiet for a while (#90).
    var voiceAwake: Bool {
        if voiceConversationOpen && Self.voiceFlowPhases.contains(phase) {return true}
        return voiceConversationDeadline.map {ProcessInfo.processInfo.systemUptime < $0} ?? false
    }
    /// Steps taken one after another, where an open conversation carries over to the next screen.
    /// Walking guidance is not one: there the call is needed each time, since the performer's and
    /// other people's voices mix with the app's own sound.
    static let voiceFlowPhases: Set<GuidancePhase>=[.selection,.restoring,.checkpoint,.wear,.departure,.paused,.interrupted,.failed]
    /// Entering walking guidance goes back to waiting for the call in English; the steps take Korean.
    func syncVoiceConversationLanguage() {
        guard voiceExperiment, !voiceTurnActive else {return}
        voiceRecognition.listenInEnglish(!voiceAwake)
    }
    /// The listening animation shows only while the app is actually taking requests.
    var voiceShowsListening: Bool { voiceShouldListen && voiceRecognition.isListening && (voiceAwake || voiceTurnActive) }
    func keepVoiceConversation(_ seconds:Double = 8) {
        voiceConversationOpen=true
        voiceConversationDeadline=ProcessInfo.processInfo.systemUptime+seconds
        voiceRecognition.listenInEnglish(false)
        scheduleVoiceSleep(after:seconds)
    }
    /// A tap while listening ends the conversation at once, as with Siri: speech and any guess are dropped.
    func dismissVoiceConversation() {
        guard voiceExperiment else {return}
        voiceConversationTimer?.cancel();voiceConversationDeadline=nil;voiceConversationOpen=false
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        generation=UUID();voice.stop();instructionDone=true
        pendingVoiceIntent=nil;voicePendingRequest=nil
        voiceRecognition.listenInEnglish(true)
        objectWillChange.send()
        logSignal("voice_dismissed","tap")
    }
    /// When the conversation goes quiet, listen in English for the call again; never mid-sentence.
    private func scheduleVoiceSleep(after seconds:Double) {
        voiceConversationTimer?.cancel()
        voiceConversationTimer=Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:UInt64(seconds*1_000_000_000)+50_000_000)
            guard !Task.isCancelled, let self else {return}
            self.objectWillChange.send()
            guard !self.voiceAwake else {return}
            if self.voiceTurnActive {self.scheduleVoiceSleep(after:2);return}
            self.voiceRecognition.listenInEnglish(true)
        }
    }

    func configureVoiceExperiment() {
        guard voiceExperiment else {return}
        voiceRecognition.onSpeechDetected={ [weak self] in self?.voiceSpeechDetected() }
        voiceRecognition.onTranscript={ [weak self] text in self?.voicePartial(text) }
        voiceRecognition.onFinal={ [weak self] text in self?.handleVoiceCommand(text) }
        voiceRecognition.onRecoverableError={ [weak self] message in self?.voiceInputRecovering(message) }
        voiceRecognition.onRecoveryReady={ [weak self] in
            // Stop any system-synthesizer fallback spoken while the engine was being restarted.
            guard let self else {return}
            self.generation=UUID();self.voice.stop();self.instructionDone=true
            self.voiceReadyChimePending=true
        }
        voiceRecognition.onError={ [weak self] error in self?.voiceInputFailed(error) }
        voiceRecognition.onExternalStop={ [weak self] message in self?.voiceInputInterrupted(message) }
        voiceRecognition.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&voiceSubscriptions)
        voiceRecognition.$isListening.dropFirst().sink { [weak self] listening in
            guard let self, listening, self.voiceReadyChimePending, self.voiceShouldListen else {return}
            self.voiceReadyChimePending=false
            self.listeningChime.play()
            if self.voiceInitialPromptPending {
                self.voiceInitialPromptPending=false
                let operation=self.generation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds:250_000_000)
                    guard let self, self.generation == operation, self.voiceShouldListen,
                          self.phase == .selection, !self.voiceChoosingMode, !self.voiceTurnActive else {return}
                    if let id=self.voiceInitialStageID, let item=self.voiceStages.first(where:{$0.id == id}) {
                        self.voiceInitialStageID=nil
                        self.select(item)
                        if let mode=self.voiceInitialMode, self.selected?.id == id {self.selectVoiceMode(mode)}
                        self.voiceInitialMode=nil
                    }
                    else if let request=self.voiceInitialRequest {self.voiceInitialRequest=nil;self.handleVoiceCommand(request)}
                    else {self.selectionDescription(empty:self.voiceStages.isEmpty)}
                }
            }
        }.store(in:&voiceSubscriptions)
    }
    func prepareVoiceExperiment(records:[ScanManifest],places:PlaceFolderIndex = PlaceFolderIndex()) {
        guard voiceExperiment else {return}
        voiceStages=records
        voiceStagePaths=Dictionary(uniqueKeysWithValues:records.map {($0.id,places.path(for:$0.id))})
        voiceInitialPromptPending=true
        voiceReadyChimePending=true
        keepVoiceConversation(30)
        syncVoiceListening()
    }
    func selectVoiceMode(_ mode:VoiceUsageMode, advanceAutomatically: Bool = true) {
        guard voiceExperiment, phase == .selection, voiceChoosingMode, selected != nil else {return}
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        voicePerformanceInputClosed=false
        voiceMode=mode
        voiceSelectionControlsVisible = !advanceAutomatically
        if advanceAutomatically {continueVoiceSelection()}
        else {
            generation=UUID();voice.stop();instructionDone=true
        }
    }
    /// Touch selection stays on the current screen until Next; recognized choices still advance.
    var canContinueVoiceSelection: Bool {
        phase == .selection && selected != nil && (!voiceChoosingMode || voiceMode != nil)
    }
    func prepareForVoiceTouch() {
        guard voiceExperiment else {return}
        generation=UUID();voice.stop();instructionDone=true
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
    }
    func continueVoiceSelection() {
        guard voiceExperiment, active, canContinueVoiceSelection else {return}
        prepareForVoiceTouch()
        if voiceChoosingMode, let mode=voiceMode {
            // Selection does not depend on a working microphone or finishing a spoken prompt.
            // Subsequent position, checkpoint and output-audio checks are still enforced.
            audioIssue=nil
            restore(voiceIntroduction:"\(mode.title)을 선택했습니다.")
        } else {
            voiceChoosingMode=true
            readVoiceModeQuestion()
        }
    }
    func readVoiceModeQuestion() {
        guard let selected else {return}
        read(VoiceStepCopy.stageChosen(selected.name))
    }
    var visibleVoiceStages: [ScanManifest] {
        guard let ids=voiceSearchIDs else {return voiceStages}
        return ids.compactMap {id in voiceStages.first {$0.id == id}}
    }
    var canCancelVoiceSelection: Bool {
        voiceExperiment && !started && (selected != nil || voiceChoosingMode || voiceSearchQuery != nil || phase != .selection)
            && ![.starting,.finishing,.completed].contains(phase)
    }
    func cancelVoiceSelection() {
        guard voiceExperiment, !started else {return}
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        invalidateTasks()
        if phase != .selection {
            tracking.endSession();tracking.errorMessage=nil
            voiceMode=nil;voicePerformanceInputClosed=false;voiceChoosingMode=selected != nil;phase = .selection
            read(["사용 방식 선택으로 돌아왔어요.","연습용 또는 실전용이라고 말씀해주세요. 취소하면 무대를 다시 선택합니다."])
        } else if voiceChoosingMode {
            voiceChoosingMode=false;voiceMode=nil;selected=nil;guide=nil;run=nil;pendingRecord=nil
            announceVoiceStageResults()
        } else if selected != nil {
            selected=nil;guide=nil;run=nil;pendingRecord=nil
            announceVoiceStageResults()
        } else if voiceSearchQuery != nil {
            voiceSearchQuery=nil;voiceSearchIDs=nil
            selectionDescription(empty:voiceStages.isEmpty)
        } else {selectionDescription(empty:voiceStages.isEmpty)}
    }
    func announceVoiceStageResults() {
        let items=visibleVoiceStages
        if items.isEmpty {
            read(["\(voiceSearchQuery ?? "요청한 이름")에 해당하는 저장 무대가 없어요. 다른 장소나 공연 이름을 말씀해주세요. 취소하면 전체 목록으로 돌아갑니다."])
            return
        }
        let title=voiceSearchQuery.map {"\($0) 관련 무대는 \(items.count)개예요."} ?? "어느 무대를 사용할까요?"
        // Separate utterances keep a long result list interruptible at every item.
        let names=items.enumerated().map {"\($0.offset+1)번, \($0.element.name). \((voiceStagePaths[$0.element.id] ?? []).joined(separator:", "))."}
        read([title]+names+["무대 이름이나 번호를 말씀해주세요. 선택하면 사용 방식으로 넘어갑니다."])
    }
    func syncVoiceListening() {
        guard voiceExperiment else {return}
        guard voiceShouldListen else {
            voiceInputTask?.cancel();voiceInputTask=nil
            voiceRecognitionRequested=false
            if voiceRecognition.isAvailable {voice.stop()}
            voiceRecognition.stop();voiceTurnActive=false
            return
        }
        guard !voiceRecognitionRequested else {return}
        voiceRecognitionRequested=true
        // Point names go early: the recognizer keeps only the first 100 hints, and P1 was heard as 「비 일」 (10/28).
        let points=["P1","P2","P3","P4","P5","피원","피투","피쓰리","피포","피파이브","1번","2번","3번","1번 지점으로 돌아가 줘"]
        let hints=VoiceWakeWord.hints+points+voiceStages.map(\.name)+voiceStagePaths.values.flatMap {$0}+["연습용","실전용","취소","관련된 무대 열어줘","다음","계속","멈춰","P2 지점으로 다시 안내해 줘","피투","2번 지점","이전","무대 다시 선택"]
        voiceInputTask=Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.voiceShouldListen else {return}
            let vocabulary=VoiceVocabulary.phrases(stageNames:self.voiceStages.map(\.name),places:Array(Set(self.voiceStagePaths.values.flatMap {$0})))
            await self.voiceRecognition.start(contextualStrings:hints,vocabulary:vocabulary,listensForWakeWord:true)
        }
    }
    func stopVoiceExperiment() {
        voiceInputTask?.cancel();voiceInputTask=nil
        voiceRecognitionRequested=false;voiceTurnActive=false
        voice.stop()
        voiceRecognition.stop();listeningChime.stop()
    }
    func retryVoiceListening() {
        guard voiceCanOfferInput else {return}
        // Manual retry can interrupt an instruction; it never advances a navigation phase.
        generation=UUID();voice.stop();instructionDone=true
        stopVoiceExperiment()
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message="다시 말씀하실 수 있도록 안내를 멈췄어요."
            captureReplay(force:true)
        }
        voiceInputError=nil;voiceListeningEnabled=true;voiceReadyChimePending=true
        syncVoiceListening()
    }
    /// Speech heard while the conversation is closed belongs to someone else until it contains the call.
    func voicePartial(_ text:String) {
        guard voiceShouldListen else {return}
        if !voiceTurnActive {
            guard VoiceWakeWord.matches(text) else {return}
            if voiceRecognition.listensInEnglish {voiceWoken();return}
            keepVoiceConversation()
            voiceSpeechDetected()
        }
    }
    /// 「Hear I am」 heard in English: chime, pause any movement and take the next words in Korean.
    func voiceWoken() {
        keepVoiceConversation()
        generation=UUID();voice.stop();instructionDone=true
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message="말씀을 듣고 있어요. 잠시 멈춰주세요."
            captureReplay(force:true)
        }
        listeningChime.play()
        logSignal("voice_wake","english")
    }
    func voiceSpeechDetected() {
        guard voiceShouldListen, !voiceTurnActive, voiceAwake else {return}
        // Invalidate delayed narration callbacks before cutting the speech already playing.
        generation=UUID();voice.stop();instructionDone=true
        voiceTurnActive=true;voiceInitialPromptPending=false
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message="말씀을 듣고 있어요. 잠시 멈춰주세요."
            captureReplay(force:true)
        }
        listeningChime.play()
        logSignal("voice_listening","speech_detected")
    }
    func voiceInputRecovering(_ message:String) {
        guard voiceShouldListen else {return}
        generation=UUID();voice.stop();instructionDone=true
        voiceTurnActive=false
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            self.message="음성 입력을 다시 연결하는 동안 안내를 멈췄어요."
            captureReplay(force:true)
        }
        // Do not narrate this transient state into the microphone or cancel the pending retry.
        logSignal("voice_input_recovery",message)
    }
    /// A call, another app's sound or a headset change stops the microphone. There is no retry button
    /// on screen, so listening comes back by itself shortly after.
    func voiceInputInterrupted(_ message:String) {
        voiceInputFailed(message)
        let error=voiceInputError
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:1_500_000_000)
            guard let self, self.voiceInputError == error, !self.voiceListeningEnabled else {return}
            self.retryVoiceListening()
        }
    }
    func voiceInputFailed(_ error:String) {
        stopVoiceExperiment()
        voiceRecognitionRequested=false;voiceTurnActive=false
        voiceListeningEnabled=false;voiceInputError=error
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true;signals.stopDirection();quietUntil=nil
            message="음성 입력이 중단되어 연습 안내를 멈췄어요."
        }
        if active {read([error])}
    }
    func handleVoiceCommand(_ text:String) {
        guard voiceShouldListen else {return}
        let accepted=voiceTurnActive || voiceAwake
        voiceTurnActive=false
        var text=text
        voicePendingRequest=nil
        // A lower recognition candidate may hold the call or an exact command the best one missed (#92).
        let alternatives=voiceRecognition.lastAlternatives
        if VoiceWakeWord.request(in:text) == nil, let called=alternatives.first(where:{VoiceWakeWord.request(in:$0) != nil}) {
            logSignal("voice_alternative","\(text) -> \(called)");text=called
        }
        if let request=VoiceWakeWord.request(in:text) {
            keepVoiceConversation()
            if request.isEmpty {logSignal("voice_wake",text);read(["네, 말씀하세요."]);return}
            text=request
        } else if !accepted {
            logSignal("voice_ignored","not called");return
        }
        if VoiceCommandParser.parse(text) == nil,
           let better=alternatives.map({VoiceWakeWord.request(in:$0) ?? $0}).first(where:{VoiceCommandParser.parse($0) != nil}) {
            logSignal("voice_alternative","\(text) -> \(better)");text=better
        }
        keepVoiceConversation()
        logSignal("voice_command",text)
        if let pending=pendingVoiceIntent {
            pendingVoiceIntent=nil
            switch VoiceIntentCopy.answer(text) {
            case true?: logSignal("voice_intent_confirmed","\(pending)");performVoiceCommand(pending,confirmed:true);return
            case false?: logSignal("voice_intent_declined","\(pending)");read([VoiceIntentCopy.declined]);return
            case nil: break
            }
        }
        // Pre-saved plans and new scans live in other tabs; those tabs answer instead. With nothing saved
        // the stage list offers a scan, so 「응」 opens it.
        let appRequest=VoiceAppRequest.resolve(text) ?? (voiceStages.isEmpty && VoiceIntentCopy.answer(text) == true ? .scan : nil)
        if phase == .selection, !started, let appRequest, let open=(appRequest == .plans ? onOpenPlans : onOpenScan) {
            logSignal("voice_app_request","\(appRequest)");open();return
        }
        let parsed=VoiceCommandParser.parse(text)
        if parsed == .cancel, !started {voiceSelectionControlsVisible=false;cancelVoiceSelection();return}
        if phase == .selection, !voiceChoosingMode, parsed != .practice, parsed != .performance,
           parsed != .repeatInstruction, parsed != .pause, parsed != .next, parsed != .start, parsed != .continueGuidance,
           parsed != .back, parsed != .chooseStageAgain,
           selectStageWithVoice(text) {
            return
        }
        if let command=parsed {
            logSignal("voice_intent","exact \(command)")
            performVoiceCommand(command)
        } else if !resolveVoiceIntent(text) {
            readVoiceCommandNotUnderstood()
        }
    }
    /// Phrases that differ from the list are given to the on-device Apple Intelligence model (#87).
    /// It may only pick what the current screen offers; a guess is asked back before acting.
    private func resolveVoiceIntent(_ text:String) -> Bool {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *), AppleIntelligenceVoiceIntentResolver.isAvailable else {return false}
        let screen=voiceScreen, began=ProcessInfo.processInfo.systemUptime
        // 「삐원으로 가」 reaches the model as 「P1으로 가」; the model reads numbers from sound poorly.
        let request=VoicePointSpelling.normalized(text)
        if request != text {logSignal("voice_point_spelling","\(text) -> \(request)")}
        voicePendingRequest=text
        Task { [weak self] in
            let decision=await AppleIntelligenceVoiceIntentResolver().resolve(request,screen:screen)
            guard let self, self.voiceShouldListen, self.voicePendingRequest == text, self.voiceScreen == screen else {return}
            self.voicePendingRequest=nil
            let seconds=String(format:"%.2fs",ProcessInfo.processInfo.systemUptime-began)
            switch decision {
            case .command(let command):
                self.logSignal("voice_intent","model \(command) \(seconds)");self.performVoiceCommand(command)
            case .confirm(let command):
                self.logSignal("voice_intent","ask \(command) \(seconds)")
                self.pendingVoiceIntent=command;self.read([VoiceIntentCopy.question(command)])
            case .none:
                self.logSignal("voice_intent","none \(seconds)");self.readVoiceCommandNotUnderstood()
            }
        }
        return true
        #else
        return false
        #endif
    }
    private func readVoiceCommandNotUnderstood() {
        read(["요청을 확실히 이해하지 못했어요. \(phase == .selection ? "무대 선택 화면에서는 장소나 무대 이름을, 사용 방식 화면에서는 연습용 또는 실전용을 말씀해주세요." : "계속, 멈춰, 또는 P2로 다시 안내해 줘처럼 한 가지 요청을 말씀해주세요.")"])
    }
    private func performVoiceCommand(_ command:VoiceCommand, confirmed:Bool = false) {
            switch command {
            case .practice,.performance:
                if phase == .selection, voiceChoosingMode {selectVoiceMode(command == .practice ? .practice : .performance)}
                else if phase == .selection {read(["먼저 사용할 무대를 선택해주세요. 장소 이름으로 검색하거나 무대 이름을 말씀해주세요."])}
                else {read(["사용 방식은 안내 시작 전에 선택할 수 있어요. 계속이라고 말씀하면 현재 안내를 이어갑니다."])}
            case .returnToPoint(let index): requestVoiceReturn(to:index)
            case .continueGuidance,.next,.start: advanceWithVoice()
            case .pause:
                if phase == .guiding || phase == .starting {pause()}
                else if phase == .paused {read(["안내를 멈췄어요. 계속이라고 말씀하면 이어서 안내해요."])}
                else {read(["현재 단계에서 기다릴게요. 준비되면 다음이라고 말씀해주세요."])}
            case .repeatInstruction: replay()
            case .cancel:
                read([started ? "요청을 취소했어요. 안내는 멈춘 상태예요. 계속이라고 말씀하면 다시 안내해요." : "요청을 취소했어요. 사용할 무대나 사용 방식을 말씀해주세요."])
            case .showAllStages:
                guard phase == .selection, !voiceChoosingMode else {read(["저장된 무대 목록은 무대 선택 화면에서 들을 수 있어요."]);return}
                guard !voiceStages.isEmpty else {selectionDescription(empty:true);return}
                showVoiceStageResults(query:nil,ids:nil)
            case .chooseStage(let number):
                let items=visibleVoiceStages
                guard phase == .selection, !voiceChoosingMode, number > 0, number <= items.count else {read(["화면에 있는 무대 번호를 말씀해주세요."]);return}
                select(items[number-1])
            case .back:
                // The same step back as the 「취소 · 이전 선택」 button; after the start there is no earlier step.
                if canCancelVoiceSelection {cancelVoiceSelection()}
                else if started {read(["안내를 시작한 뒤에는 이전 단계가 없어요. 무대를 바꾸려면 무대 다시 선택이라고 말씀해주세요."])}
                else {read(["지금이 첫 단계예요. 사용할 무대 이름이나 목록 번호를 말씀해주세요."])}
            case .chooseStageAgain:
                guard phase != .selection || voiceChoosingMode || selected != nil else {selectionDescription(empty:voiceStages.isEmpty);return}
                // Leaving a started run drops it, so that is asked first; before the start nothing is lost.
                if started && !confirmed {
                    pendingVoiceIntent = .chooseStageAgain;read([VoiceIntentCopy.question(.chooseStageAgain)]);return
                }
                logSignal("voice_choose_stage_again",started ? "run_dropped" : "before_start")
                resetSignals();voicePausedNavigation=false
                chooseAgain()
            }
    }
    private func selectStageWithVoice(_ text:String) -> Bool {
        if let ordinal=VoiceStageSearch.ordinal(text) {
            let items=visibleVoiceStages
            guard ordinal > 0, ordinal <= items.count else {
                read(["화면에 있는 무대 번호를 말씀해주세요."]);return true
            }
            select(items[ordinal-1]);return true
        }
        switch VoiceStageSearch.resolve(text,names:voiceStages.map(\.name),contexts:voiceStages.map {voiceStagePaths[$0.id] ?? []}) {
        case .selected(let index): select(voiceStages[index]);return true
        case .results(let query,let indices):
            let ids=indices.map {voiceStages[$0].id}
            // A request such as 「저장된 무대 다 불러와 줘」 matches no name; let the model read it first.
            // A keyword search that found nothing still says so.
            if ids.isEmpty, !VoiceStageSearch.isKeywordSearch(text), resolveVoiceIntent(text) {return true}
            showVoiceStageResults(query:query,ids:ids);return true
        case .none: return false
        }
    }
    private func showVoiceStageResults(query:String?,ids:[UUID]?) {
        voiceSelectionControlsVisible=false
        voiceRecognition.discardPendingSpeech()
        selected=nil;guide=nil;run=nil;pendingRecord=nil
        voiceSearchQuery=query;voiceSearchIDs=ids
        announceVoiceStageResults()
    }
    func advanceWithVoice() {
        guard voiceExperiment, active else {return}
        switch phase {
        case .selection:
            if canContinueVoiceSelection {voiceSelectionControlsVisible=false;continueVoiceSelection();return}
            read([voiceChoosingMode ? "연습용 또는 실전용이라고 말씀하면 바로 다음 단계로 넘어갑니다." : "사용할 무대 이름이나 목록 번호를 말씀해주세요."])
        case .checkpoint:
            if canVerify {verifyCheckpoint()} else {read(["확인점을 아직 확인할 수 없어요. 휴대폰 조준점을 저장한 확인점에 맞춰주세요."])}
        case .wear:
            if canAdvanceInstruction && tracking.ready {finishWear()} else {read(["위치 추적과 착용 상태를 먼저 확인해주세요."])}
        case .departure:
            if departureReady && canAdvanceInstruction {startGuidance()} else {read([departureStatus])}
        case .paused:
            if canResume && canAdvanceInstruction {voicePausedNavigation=false;startGuidance()} else {read(["현재 위치에서 안내를 재개할 수 없어요. 동선과 확인점을 다시 확인해주세요."])}
        case .failed,.interrupted: restore()
        default: break
        }
    }
    func requestVoiceReturn(to number:Int) {
        guard voiceMode == .practice, started, phase == .paused || phase == .guiding else {
            read(["지점으로 돌아가기는 연습 안내를 시작한 후 사용할 수 있어요."]);return
        }
        guard let pose=freshPose(), var guide else {read(["현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요."]);return}
        guard let index=guide.rehearsalPointIndex(number:number) else {
            read(["저장된 동선에 P\(number) 지점이 없어요. 지점 이름을 다시 확인해주세요."]);return
        }
        do {
            try guide.beginRehearsalReturn(to:index,position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guide.pause()
            self.guide=guide;aligningStep=nil;performanceHoldRemaining=0;phase = .paused;voicePausedNavigation=false
            tracking.setGuidanceTarget(guide.targetIndex)
            logSignal("rehearsal_return_requested","destination=\(voicePointName(index)) first=P\(guide.targetIndex)")
            startGuidance()
        } catch {
            read(["\(voicePointName(index))로 돌아갈 수 없어요. \(error.localizedDescription)"])
        }
    }
    func reachedVoiceReturn(_ index:Int, time:Double) {
        guard voiceExperiment else {return}
        invalidateTasks();resetSignals();phase = .paused;voicePausedNavigation=true
        arrivedName="\(voicePointName(index))";message="\(voicePointName(index))에 도착했어요. 계속이라고 말씀하면 다음 지점으로 안내해요."
        captureReplay(force:true)
        aligningStep=guide?.route.step(at:index).flatMap {$0.facingEdge == nil ? nil : $0}
        logSignal("rehearsal_return_arrived","\(voicePointName(index))")
        let operation=generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:700_000_000)
            guard let self, self.generation == operation, self.active, !self.voiceTurnActive, self.guide?.rehearsalReturnArrivalIndex == index else {return}
            self.keepVoiceConversation()
            self.read([self.guide?.route.spokenPointName(at:index) ?? self.voicePointName(index),"\(self.voicePointName(index)) 지점에 도착했어요. 잠시 멈춰주세요. 계속이라고 말씀하면 다음 지점으로 안내해요."])
        }
    }
}
