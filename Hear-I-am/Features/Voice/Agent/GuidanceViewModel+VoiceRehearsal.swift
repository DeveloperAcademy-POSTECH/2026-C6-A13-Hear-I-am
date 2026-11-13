import Foundation
import Combine
import HearIAmCore

/// Opt-in #69 experiment. Commands use the same guards as the existing touch controls.
extension GuidanceViewModel {
    func voicePointName(_ index:Int) -> String {guide?.route.pointLabel(at:index) ?? L("지점")}
    /// What the current screen can do, offered to the Apple Intelligence model (#87).
    var voiceScreen: VoiceScreen {
        switch phase {
        case .selection: return voiceChoosingMode ? .modeChoice : .stageList(stageCount:voiceSelectionNames.count)
        case .starting,.guiding,.paused:
            return .guidance(pointCount:voiceMode == .practice && started ? max(0,(guide?.route.points.count ?? 0)-1) : 0)
        case .failed,.interrupted: return .recovery
        default: return .preparation
        }
    }

    var voiceCanOfferInput: Bool {
        guard voiceExperiment, !helperPreparation, !helperStart, !isSettingsPresented, active, !showExit, !savingRecord, escape == nil, audioIssue == nil else {return false}
        if voiceMode == .performance && voicePerformanceInputClosed {return false}
        return [.selection,.restoring,.checkpoint,.wear,.departure,.starting,.guiding,.paused,.failed,.interrupted].contains(phase)
    }
    var voiceShouldListen: Bool { voiceCanOfferInput && voiceListeningEnabled }
    /// True after 「히얼아이엠」 until the conversation has been quiet for a while (#90).
    /// Ten seconds after the last words, the performer's or the app's, listening stops and 「Hear I am」
    /// is needed again on the same screen (11/03). The app's own questions open it again.
    var voiceAwake: Bool {
        voiceConversationDeadline.map {ProcessInfo.processInfo.systemUptime < $0} ?? false
    }
    static var voiceAsleepStatus: String { L("‘Hear I am’ 하고 부르면 이어서 들을게요") }
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
    func keepVoiceConversation(_ seconds:Double = 10) {
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
            // After the last point nothing is listened to, so a restart must not cut the closing line.
            guard let self, !self.voiceHoldsOutputUntilClose else {return}
            // The line cut here (the first 「공연 찾기…」 on opening, 11/01) is said again once listening is back.
            if !self.instructionDone, !self.currentInstruction.isEmpty {self.voiceReplayAfterRecovery=true}
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
            if let request=self.settingsDeferredVoiceRequest,self.phase == .selection {
                let operation=self.generation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds:250_000_000)
                    guard let self,self.generation==operation,self.voiceShouldListen,self.phase == .selection,
                          self.settingsDeferredVoiceRequest==request else {return}
                    self.settingsDeferredVoiceRequest=nil
                    self.handleVoiceCommand(request)
                }
            } else if self.voiceInitialPromptPending {
                let operation=self.generation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds:250_000_000)
                    guard let self, self.generation == operation else {return}
                    self.runVoiceInitialRequest()
                }
            } else if self.voiceReplayAfterRecovery {
                self.voiceReplayAfterRecovery=false
                let operation=self.generation, lines=self.currentInstruction, interruptible=self.voiceNarrationInterruptible
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds:250_000_000)
                    guard let self, self.generation == operation, self.voiceShouldListen, !self.voiceTurnActive, !self.speaking else {return}
                    self.logSignal("voice_replay","after_recovery")
                    self.voiceChatSuppressNextLine=true
                    self.read(lines,interruptible:interruptible)
                }
            }
        }.store(in:&voiceSubscriptions)
    }
    func prepareVoiceExperiment(records:[ScanManifest],contexts:[UUID:[String]] = [:],catalog:PerformanceCatalog = PerformanceCatalog()) {
        guard voiceExperiment else {return}
        if voiceStartedAsHelper == nil {voiceStartedAsHelper=helperPreparation}
        #if DEBUG
        VoiceTestInbox.shared.guidance=self
        #endif
        // A stage outside every performance is not offered (#181); one left by a cut-off scan waits for its
        // performance on the helper's side.
        voiceStages=records.filter {catalog.folder(for:$0.id) != nil}
        voiceCatalog=catalog
        voiceStagePaths=contexts
        guard !isSettingsPresented else {voicePreparationDeferredBySettings=true;return}
        if helperStart {
            // Neither the scene nor the mode is asked: the space is looked for at once on the checkpoint screen.
            guard let id=voiceInitialStageID, let item=records.first(where:{$0.id == id}) else {
                read([L("준비할 무대를 찾을 수 없어요. 목록에서 다시 선택해주세요.")]);return
            }
            voiceInitialStageID=nil;voiceInitialMode=nil
            select(item,advanceAutomatically:false)
            guard selected != nil else {return}
            voiceChoosingMode=true;voiceMode = .performance;voiceSelectionControlsVisible=false
            prepareForVoiceTouch();audioIssue=nil
            restore()
            return
        }
        if helperPreparation {
            if let id=voiceInitialStageID, let item=records.first(where:{$0.id == id}) {
                voiceInitialStageID=nil;voiceInitialMode=nil
                select(item,advanceAutomatically:false)
                if selected != nil {voiceChoosingMode=true;selectVoiceMode(.performance)}
            } else {message=L("준비할 무대를 찾을 수 없어요. 목록에서 다시 선택해주세요.")}
            return
        }
        voiceInitialPromptPending=true
        voiceReadyChimePending=true
        // The request made on Home opens the conversation as its first bubble (Figma 495:5096).
        if let request=voiceInitialRequest, voiceChat.isEmpty {voiceChatSeededRequest=request;appendVoiceChat(.user(request))}
        else if case .user(let text)?=voiceChat.first?.kind, voiceChat.count == 1 {VoiceLog.write("chat_user",text,screen:"guidance.\(phase)")}
        keepVoiceConversation(30)
        syncVoiceListening()
        // What was asked on Home is answered at once. Waiting for the microphone to come back first kept
        // the performer waiting 1–3 s with nothing new on screen (11/03 device log); a line cut by that
        // restart is said again once listening is back (onRecoveryReady).
        DispatchQueue.main.async { [weak self] in self?.runVoiceInitialRequest() }
    }
    /// The request, stage or bare 「연습」 brought from Home or Siri, handled once.
    func runVoiceInitialRequest() {
        guard voiceInitialPromptPending, voiceShouldListen, phase == .selection, !voiceChoosingMode, !voiceTurnActive else {return}
        voiceInitialPromptPending=false
        if let id=voiceInitialStageID, let item=voiceStages.first(where:{$0.id == id}) {
            voiceInitialStageID=nil
            select(item)
            if let mode=voiceInitialMode, selected?.id == id {selectVoiceMode(mode)}
            voiceInitialMode=nil
        }
        else if let request=voiceInitialRequest {voiceInitialRequest=nil;handleVoiceCommand(request)}
        else {selectionDescription(empty:voiceStages.isEmpty)}
    }

    // MARK: Conversation (Figma 495:5074–5481)

    func appendVoiceChat(_ kind: VoiceChatEntry.Kind) {
        voiceChat.append(VoiceChatEntry(kind:kind))
        // The screen can be read back from the log after a test (11/02).
        switch kind {
        case .user(let text): VoiceLog.write("chat_user",text,screen:"guidance.\(phase)")
        case .app(let text): VoiceLog.write("chat_app",text,screen:"guidance.\(phase)")
        case .stages(let text,let cards): VoiceLog.write("chat_cards",text+" | "+cards.map {"\($0.number). \($0.name) [\($0.tags.joined(separator:","))]"}.joined(separator:" | "),screen:"guidance.\(phase)")
        }
        if voiceChat.count > 80 {voiceChat.removeFirst(voiceChat.count-80)}
    }
    /// The spinner line under the conversation while the app is doing something the performer waits for.
    var voiceChatStatus: String? {
        switch phase {
        case .restoring: return L("저장된 무대를 찾고 있어요")
        case .starting: return L("연습 안내를 시작하고 있어요")
        case .departure where !departureReady: return L("출발 위치를 확인하고 있어요")
        default: break
        }
        if voicePendingRequest != nil {return L("요청을 확인하고 있어요")}
        if voiceTurnActive {return L("듣고 있어요")}
        if voiceShouldListen, !voiceAwake, !speaking, !phase.showsRouteCamera {return Self.voiceAsleepStatus}
        return nil
    }
    /// The cards the list is read from; the spoken list is not repeated as text under them.
    func showVoiceChatCards(performances: [PerformanceVoiceChoice], text: String) {
        let cards=performances.enumerated().map {index,choice -> VoiceChatStage in
            let stages=choice.stageIDs.compactMap {id in voiceStages.first {$0.id == id}}
            var seen=Set<String>()
            let venues=stages.compactMap {voiceCatalog.venue(for:$0.id)?.name}.filter {seen.insert($0).inserted}
            let sample=stages.first {$0.route != nil} ?? stages.first
            return VoiceChatStage(id:choice.id,number:index+1,name:choice.name,
                                  tags:venues.isEmpty ? [L("저장된 무대 %@개", choice.stageIDs.count)] : Array(venues.prefix(2)),
                                  width:sample?.route?.area.width ?? 12,depth:sample?.route?.area.depth ?? 8,
                                  points:sample?.route?.points ?? [],objects:sample?.route?.obstacles ?? [])
        }
        appendVoiceChat(.stages(text,cards));voiceChatSuppressNextLine=true
    }
    func showVoiceChatCards(stages: [ScanManifest], text: String) {
        let cards=stages.enumerated().map {index,item in
            VoiceChatStage(id:item.id,number:index+1,name:item.name,
                           tags:[voiceCatalog.venue(for:item.id)?.name,voiceCatalog.folder(for:item.id)?.name].compactMap {$0},
                           width:item.route?.area.width ?? 12,depth:item.route?.area.depth ?? 8,
                           points:item.route?.points ?? [],objects:item.route?.obstacles ?? [])
        }
        appendVoiceChat(.stages(text,cards));voiceChatSuppressNextLine=true
    }
    /// The pencil on a bubble (Figma 495:5096): the app stops talking and the conversation stays open while
    /// the performer types.
    func beginVoiceEdit() {
        generation=UUID();voice.stop();instructionDone=true
        keepVoiceConversation(120)
    }
    /// A bubble edited by hand is answered as if it had been said. The last bubble is corrected where it
    /// is; an older one is asked again at the end. Typed words are the performer's own, so neither the
    /// call, the app's speech nor the echo filter can drop them (11/03: an edit was never carried out).
    func submitTypedRequest(_ text:String, replacing id:UUID? = nil) {
        let request=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard voiceExperiment, !request.isEmpty else {return}
        generation=UUID();voice.stop();instructionDone=true
        keepVoiceConversation()
        let lastUser=voiceChat.lastIndex {if case .user=$0.kind {return true};return false}
        if let id, let index=lastUser, voiceChat[index].id == id, index == voiceChat.count-1 {
            voiceChat[index]=VoiceChatEntry(id:id,kind:.user(request))
        } else {
            appendVoiceChat(.user(request))
        }
        VoiceLog.write("chat_typed",request,screen:"guidance.\(phase)")
        guard voiceShouldListen else {read([L("지금은 요청을 받을 수 없어요. 마이크가 켜지면 다시 말씀해주세요.")]);return}
        voiceChatSeededRequest=request
        voiceTurnActive=true;voiceTurnOverNarration=false
        handleVoiceCommand(request)
    }
    /// Where the next point lies against the body's heading, for the front-finding light on the walking screen.
    var voiceGlowBearing: Double? {
        let leading=phase == .approaching ? approachGuide : guide
        guard phase == .guiding || phase == .approaching, let guide=leading, let pose=signalPose, guide.route.points.indices.contains(guide.targetIndex),
              ProcessInfo.processInfo.systemUptime-pose.time <= 1 else {return nil}
        return StageHeading.bearing(from:pose.point,to:guide.route.points[guide.targetIndex],headingDegrees:pose.heading)
    }
    func voiceGlowAtTarget(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) -> Bool {
        guard guide.route.points.indices.contains(guide.targetIndex) else {return false}
        return pose.point.distance(to:guide.route.points[guide.targetIndex]) <= guide.settings.arrivalRadius
    }
    func resumeVoiceAfterSettings() {
        guard active else {return}
        if voicePreparationDeferredBySettings {
            voicePreparationDeferredBySettings=false
            prepareVoiceExperiment(records:voiceStages,contexts:voiceStagePaths,catalog:voiceCatalog)
            return
        }
        // The initial delayed selection may have been cancelled while settings opened.
        if phase == .selection,voiceInitialRequest != nil || voiceInitialStageID != nil {voiceInitialPromptPending=true}
        voiceReadyChimePending=voiceShouldListen
        syncVoiceListening()
    }
    func selectVoiceMode(_ mode:VoiceUsageMode, advanceAutomatically: Bool = true, namingStage: Bool = false) {
        guard voiceExperiment, phase == .selection, voiceChoosingMode, selected != nil else {return}
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        voicePerformanceInputClosed=false
        // 실전용 chosen by the performer stays in the voice flow (#167): the space is found as in 연습용, then the
        // helper takes the checkpoints on the camera screen. Opened by the helper, it keeps the helper's preparation.
        voiceMode=mode
        helperPreparation=mode == .performance && voiceStartedAsHelper == true
        if helperPreparation {stopVoiceExperiment();voiceListeningEnabled=false}
        else {voiceListeningEnabled=true;syncVoiceListening()}
        voiceSelectionControlsVisible = !advanceAutomatically
        if advanceAutomatically {continueVoiceSelection(namingStage:namingStage)}
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
        settingsDeferredVoiceRequest=nil
        generation=UUID();voice.stop();instructionDone=true
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
    }
    func continueVoiceSelection(namingStage: Bool = false) {
        guard voiceExperiment, active, canContinueVoiceSelection else {return}
        prepareForVoiceTouch()
        if voiceChoosingMode, let mode=voiceMode {
            // Selection does not depend on a working microphone or finishing a spoken prompt.
            // Subsequent position, checkpoint and output-audio checks are still enforced.
            audioIssue=nil
            // Chosen with the stage in one request, the stage is named too: nothing else confirmed it (#174).
            let introduction=namingStage && selected != nil ? L("%@, %@을 선택했습니다.", selected!.name, mode.title) : L("%@을 선택했습니다.", mode.title)
            restore(voiceIntroduction:introduction)
        } else if let mode=voiceInitialMode {
            // 「연습용」 said on Home or before a stage was chosen is not asked again (11/06 device log).
            voiceInitialMode=nil;voiceChoosingMode=true
            logSignal("voice_mode_remembered","\(mode)")
            selectVoiceMode(mode)
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
        let candidates=voiceSearchIDs.map {ids in ids.compactMap {id in voiceStages.first {$0.id == id}}} ?? voiceStages
        guard let id=voicePerformanceID else {return candidates}
        return candidates.filter {item in
            return voiceCatalog.assignments[item.id]?.performanceID == id
        }
    }
    var canCancelVoiceSelection: Bool {
        voiceExperiment && !helperStart && !started && (selected != nil || voiceChoosingMode || voicePerformanceID != nil || voiceSearchQuery != nil || phase != .selection)
            && ![.starting,.finishing,.completed].contains(phase)
    }
    /// Restore the caller's role, not the temporary helper handoff selected by live mode.
    func restoreVoiceSelectionOrigin() {
        guard voiceExperiment else {return}
        let helper=voiceStartedAsHelper ?? helperPreparation
        helperPreparation=helper
        voiceListeningEnabled = !helper
        if !helper {keepVoiceConversation(30)}
    }
    func cancelVoiceSelection() {
        guard voiceExperiment, !started else {return}
        restoreVoiceSelectionOrigin()
        defer {syncVoiceListening()}
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        invalidateTasks()
        if phase != .selection {
            tracking.endSession();tracking.errorMessage=nil
            voiceMode=nil;voicePerformanceInputClosed=false;performanceCheckpointsDone=false;voiceChoosingMode=selected != nil;phase = .selection
            read([L("사용 방식 선택으로 돌아왔어요."),L("연습용 또는 실전용이라고 말씀해주세요. 취소하면 무대를 다시 선택합니다.")])
        } else if voiceChoosingMode {
            voiceChoosingMode=false;voiceMode=nil;selected=nil;guide=nil;run=nil;pendingRecord=nil
            announceVoiceStageResults()
        } else if selected != nil {
            selected=nil;guide=nil;run=nil;pendingRecord=nil
            announceVoiceStageResults()
        } else if voicePerformanceID != nil {
            voicePerformanceID=nil;voiceSearchQuery=nil;voiceSearchIDs=nil
            announceVoiceStageResults()
        } else if voiceSearchQuery != nil {
            voiceSearchQuery=nil;voiceSearchIDs=nil
            selectionDescription(empty:voiceStages.isEmpty)
        } else {selectionDescription(empty:voiceStages.isEmpty)}
    }
    func announceVoiceStageResults() {
        if showsVoicePerformances {
            let choices=voicePerformanceChoices
            guard !choices.isEmpty else {read([L("저장된 무대를 찾지 못했어요. 다른 공연이나 공연장 이름을 말씀해주세요.")]);return}
            showVoiceChatCards(performances:choices,text:L("저장된 공연 %@개를 찾았어요.\n공연 이름이나 번호를 말씀해주세요.", choices.count))
            read([L("어떤 공연을 준비할까요?")]+choices.enumerated().map {L("%@번, %@. 저장된 무대 %@개.", $0.offset+1, $0.element.name, $0.element.stageIDs.count)}+[L("공연 이름이나 번호를 말씀해주세요.")],interruptible:true)
            return
        }
        let items=visibleVoiceStages
        if items.isEmpty {
            read([L("%@에 해당하는 저장된 공연이 없어요. 다른 장소나 공연 이름을 말해주세요. 취소하면 전체 목록으로 돌아가요.", voiceSearchQuery ?? L("요청한 이름"))])
            return
        }
        // Words of the new 공연 찾기 screen (IA 10/29).
        let title=L("%@의 어느 무대에서 진행할까요?", voiceSelectedPerformanceName ?? L("선택한 공연"))
        // Separate utterances keep a long result list interruptible at every item.
        let names=items.enumerated().map {L("%@번, %@.", $0.offset+1, voiceStageTitle($0.element))}
        showVoiceChatCards(stages:items,text:L("%@\n공연장 이름이나 무대 번호를 말씀해주세요.", title))
        read([title]+names+[L("공연장 이름이나 무대 번호를 말해주세요.")],interruptible:true)
    }
    /// After the last point the microphone stays on, unheard, until the screen closes. Releasing it there
    /// switched the audio session from the voice-processing output (call volume) to playback (media
    /// volume): the final ding was cut, poses stalled 0.6 s, and the closing lines came out much quieter
    /// (11/06, both runs). Nothing said in these phases is acted on: every handler checks voiceShouldListen.
    var voiceHoldsOutputUntilClose: Bool {
        voiceExperiment && active && voiceRecognitionRequested && [.finishing,.completed].contains(phase)
    }
    func syncVoiceListening() {
        guard voiceExperiment else {return}
        if !voiceShouldListen, voiceHoldsOutputUntilClose {voiceTurnActive=false;return}
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
        let points=["P1","P2","P3","P4","P5",L("피원"),L("피투"),L("피쓰리"),L("피포"),L("피파이브"),L("1번"),L("2번"),L("3번"),L("1번 지점으로 돌아가 줘")]
        let hints=VoiceWakeWord.hints+points+voiceStages.map(\.name)+voiceStagePaths.values.flatMap {$0}+[L("연습용"),L("실전용"),L("취소"),L("관련된 무대 열어줘"),L("다음"),L("계속"),L("멈춰"),L("P2 지점으로 다시 안내해 줘"),L("피투"),L("2번 지점"),L("이전"),L("무대 다시 선택")]
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
            message=L("다시 말씀하실 수 있도록 안내를 멈췄어요.")
            captureReplay(force:true)
        }
        voiceInputError=nil;voiceListeningEnabled=true;voiceReadyChimePending=true
        syncVoiceListening()
    }
    /// Speech heard while the conversation is closed belongs to someone else until it contains the call.
    func voicePartial(_ text:String) {
        guard voiceShouldListen else {return}
        // While the app speaks, anything the performer says cuts it and is answered at once, as in a talk
        // with a person (11/03). Noise and the app's own voice coming back do not stop it. A single word that
        // is in the line being read may be the start of that line's echo, so it waits for the next word.
        if speaking, voiceAwake, !voiceTurnActive {
            guard let request=voiceBargeInRequest(text) else {return}
            let single = !request.contains(" ")
            if !voiceNarrationHeld, single, VoiceStageSearch.normalized(spokenText).contains(VoiceStageSearch.normalized(request)) {return}
            voiceSpeechDetected(overNarration:true)
            showVoiceLiveText(text)
            return
        }
        if !voiceTurnActive {
            guard VoiceWakeWord.matches(text) else {return}
            if voiceRecognition.listensInEnglish {voiceWoken();return}
            keepVoiceConversation()
            voiceSpeechDetected()
        }
        if voiceTurnActive {showVoiceLiveText(text)}
    }
    /// Like dictation or Siri, the words appear in the bubble while they are said; the final text replaces
    /// them. The app's own voice, the call and noise are left out.
    func showVoiceLiveText(_ text:String) {
        var words=voiceTurnOverNarration ? VoiceEcho.strippingLeadingEcho(text,of:narrationLines) : text
        if let request=VoiceWakeWord.request(in:words) {words=request}
        voiceLiveText=VoiceNoise.request(words) ?? ""
        let live=voiceLiveText
        if !live.isEmpty, VoiceCommandParser.parse(live) != nil || VoiceStageSearch.ordinal(live) != nil || VoiceAppRequest.resolve(live) != nil {
            voiceRecognition.finishSoon()
        }
    }
    /// 「Hear I am」 heard in English: chime, pause any movement and take the next words in Korean.
    func voiceWoken() {
        keepVoiceConversation()
        generation=UUID();voice.stop();instructionDone=true
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message=L("말씀을 듣고 있어요. 잠시 멈춰주세요.")
            captureReplay(force:true)
        }
        listeningChime.play()
        logSignal("voice_wake","english")
    }
    /// What was heard over the app's speech, without the app's own words at the start. Any words of the
    /// performer's cut the app's speech and get an answer; until 11/03 only requests this screen could act
    /// on did, and everything else was dropped while the app talked. Noise and echo return nil.
    func voiceBargeInRequest(_ text:String) -> String? {
        // An item of the list being read is the answer it asks for, though the list holds the same words (#156).
        if voiceHeardChoice(text) {return VoiceNoise.request(text)}
        let request=VoiceEcho.strippingLeadingEcho(text,of:narrationLines)
        guard !request.isEmpty, !VoiceEcho.isEcho(request,of:narrationLines) else {return nil}
        return VoiceNoise.request(request)
    }
    /// The lines the app is saying or has just said, for telling its own voice from the user's.
    var narrationLines: [String] {[spokenText,previousSpokenText]}
    /// `overNarration`: the words heard over a list were checked and are not the app's own voice.
    func voiceSpeechDetected(overNarration: Bool = false) {
        guard voiceShouldListen, !voiceTurnActive, voiceAwake else {return}
        // Sound alone over the app's speech may be its own voice or someone nearby; the words decide
        // (voicePartial). The words are kept, not discarded: dropping them was why a request over the
        // app's speech was never heard (11/01).
        // Sound over the app's speech holds its voice at once, as a person stops when interrupted; the
        // first words then decide (voicePartial). If none come, the line goes on.
        if speaking && !overNarration {holdVoiceNarration();return}
        voiceNarrationHeld=false
        voiceTurnOverNarration=overNarration
        voiceLiveText=""
        // Invalidate delayed narration callbacks before cutting the speech already playing.
        generation=UUID();voice.stop();instructionDone=true
        voiceTurnActive=true;voiceInitialPromptPending=false
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message=L("말씀을 듣고 있어요. 잠시 멈춰주세요.")
            captureReplay(force:true)
        }
        listeningChime.play()
        logSignal("voice_listening","speech_detected")
    }
    private func holdVoiceNarration() {
        guard !voiceNarrationHeld else {return}
        voiceNarrationHeld=true
        voiceRecognition.holdNarration(true)
        logSignal("voice_hold","speech")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:1_300_000_000)
            guard let self, self.voiceNarrationHeld, !self.voiceTurnActive else {return}
            self.voiceNarrationHeld=false
            self.voiceRecognition.holdNarration(false)
            self.logSignal("voice_hold","resume")
        }
    }
    func voiceInputRecovering(_ message:String) {
        guard voiceShouldListen else {return}
        // The line cut by the restart (「어떤 공연을 준비할까요?」 right after Home, 11/03) is said again
        // once listening is back; its text is already in the conversation.
        if !instructionDone, !currentInstruction.isEmpty {voiceReplayAfterRecovery=true}
        voiceNarrationHeld=false
        generation=UUID();voice.stop();instructionDone=true
        voiceTurnActive=false
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            self.message=L("음성 입력을 다시 연결하는 동안 안내를 멈췄어요.")
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
        guard !isSettingsPresented else {return}
        // The microphone only kept the audio path for the closing lines: let it go without cutting them.
        if voiceHoldsOutputUntilClose {voiceRecognitionRequested=false;voiceRecognition.stop();return}
        stopVoiceExperiment()
        voiceRecognitionRequested=false;voiceTurnActive=false
        voiceListeningEnabled=false;voiceInputError=error
        if phase == .guiding || phase == .starting {
            guide?.pause();phase = started ? .paused : .departure;voicePausedNavigation=true;signals.stopDirection();quietUntil=nil
            message=L("음성 입력이 중단되어 연습 안내를 멈췄어요.")
        }
        if active {read([error])}
    }
    func handleVoiceCommand(_ text:String) {
        guard voiceShouldListen else {return}
        settingsDeferredVoiceRequest=nil
        let accepted=voiceTurnActive || voiceAwake
        let wasTurn=voiceTurnActive
        voiceTurnActive=false
        // Room noise comes back as 「.」, 「아.」 or 「이 .」 (11/02–03 device tests); it is no request, and the
        // fillers around real words are dropped (「이 . 계속」 is 「계속」).
        guard let cleaned=VoiceNoise.request(text) else {logSignal("voice_ignored","noise \(text)");return}
        let heard=text
        var text=cleaned
        if speaking, voiceAwake, !wasTurn {
            // The whole request came before its words cut in (voicePartial): the same rule decides here.
            guard let request=voiceBargeInRequest(text) else {logSignal("voice_ignored","while_speaking \(text)");return}
            voicePendingRequest=nil
            voiceSpeechDetected(overNarration:true);voiceTurnActive=false;voiceTurnOverNarration=false
            text=request
        }
        voicePendingRequest=nil
        if voiceTurnOverNarration {
            voiceTurnOverNarration=false
            let own=text
            if !voiceHeardChoice(text) {text=VoiceEcho.strippingLeadingEcho(text,of:narrationLines)}
            if text.isEmpty {logSignal("voice_ignored","echo \(own)");return}
        }
        logSignal("voice_heard",([text]+voiceRecognition.lastAlternatives.filter {$0 != text}).joined(separator:" | "))
        // A lower recognition candidate may hold the call or an exact command the best one missed (#92).
        let alternatives=voiceRecognition.lastAlternatives
        if VoiceWakeWord.request(in:text) == nil, let called=alternatives.first(where:{VoiceWakeWord.request(in:$0) != nil}) {
            logSignal("voice_alternative","\(text) -> \(called)");text=called
        }
        if let request=VoiceWakeWord.request(in:text) {
            keepVoiceConversation()
            if request.isEmpty {logSignal("voice_wake",text);read([L("네, 말씀하세요.")]);return}
            text=request
        } else if !accepted {
            logSignal("voice_ignored","not called");return
        }
        if VoiceCommandParser.parse(text) == nil,
           let better=alternatives.map({VoiceWakeWord.request(in:$0) ?? $0}).first(where:{VoiceCommandParser.parse($0) != nil}) {
            logSignal("voice_alternative","\(text) -> \(better)");text=better
        }
        // A lower candidate may name a stage the best one missed: 「실행 | 누리 랩 실행」 was not understood
        // and had to be said again (11/06 device log).
        if VoiceCommandParser.parse(text) == nil, !voiceHeardChoice(text),
           let better=alternatives.first(where:voiceHeardChoice) {
            logSignal("voice_alternative","\(text) -> \(better)");text=better
        }
        // One word out of the app's own line and nothing the app could act on: 「어떤」 from 「어떤 공연을
        // 준비할까요?」 had the model read the whole list out five seconds later (11/12). Nothing is said back.
        if VoiceEcho.isOwnWord(text,of:narrationLines), VoiceCommandParser.parse(text) == nil, voiceScreen.nearCommand(text) == nil,
           !voiceHeardChoice(text), VoiceIntentCopy.answer(text) == nil, VoiceAppRequest.resolve(text) == nil,
           !VoiceCommandParser.isClose(text), !alternatives.contains(where:VoiceCommandParser.isClose) {
            logSignal("voice_ignored","own_word \(text)");return
        }
        keepVoiceConversation()
        logSignal("voice_command",text)
        // 「닫기」, often heard as 「찾기」·「받기」 with 「닫기」 among the alternatives (11/03).
        if VoiceCommandParser.isClose(text) || (text.count <= 4 && VoiceCommandParser.parse(text) == nil && alternatives.contains(where:VoiceCommandParser.isClose)) {
            logSignal("voice_close",text);onVoiceClose?();return
        }
        // The request becomes the performer's bubble; the one brought from Home is already there.
        if voiceChatSeededRequest == heard {voiceChatSeededRequest=nil}
        else if !phase.showsRouteCamera {appendVoiceChat(.user(text))}
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
        // A name on screen wins over a new scan: a performance may itself be called 「무대 스캔」 (11/03).
        let heardName=VoiceStageSearch.normalized(text)
        let namesChoice=voiceSelectionNames.contains {name in
            let name=VoiceStageSearch.normalized(name);return name.count >= 2 && heardName.contains(name)
        }
        let appRequest=namesChoice ? nil : VoiceAppRequest.resolve(text) ?? (voiceStages.isEmpty && VoiceIntentCopy.answer(text) == true ? .scan : nil)
        if phase == .selection, !started, let appRequest, let open=(appRequest == .plans ? onOpenPlans : onOpenScan) {
            // Said and shown in the conversation first, then that screen opens, as on Home (11/03).
            logSignal("voice_app_request","\(appRequest)")
            read(appRequest == .plans ? VoiceAppRequest.plansHandoff : VoiceAppRequest.scanAnswer) {open()}
            return
        }
        let exact=VoiceCommandParser.parse(text)
        // 「연수용」 for 「연습용」: a sound or two from a command of this screen counts as that command, unless
        // the words pick something on the list (#192).
        let parsed=exact ?? (voiceHeardChoice(text) ? nil : voiceScreen.nearCommand(text))
        if parsed == .cancel, !started {voiceSelectionControlsVisible=false;cancelVoiceSelection();return}
        // 「뱀파이어 연습용」: the mode is kept and the rest finds the stage, which then starts in that mode (#174).
        if phase == .selection, !voiceChoosingMode, parsed == nil, let split=voiceModeWithStage(text) {
            voiceInitialMode = split.mode == .practice ? .practice : .performance
            logSignal("voice_mode_with_stage","\(split.mode) | \(split.rest)")
            if selectStageWithVoice(split.rest) {return}
            voiceInitialMode=nil
        }
        if phase == .selection, !voiceChoosingMode, parsed != .practice, parsed != .performance,
           parsed != .repeatInstruction, parsed != .pause, parsed != .next, parsed != .start, parsed != .continueGuidance,
           parsed != .back, parsed != .chooseStageAgain,
           selectStageWithVoice(text) {
            return
        }
        if let command=parsed {
            logSignal("voice_intent","\(exact == nil ? "near" : "exact") \(command)")
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
        // Not tied to `generation`: the microphone restarting right after Home changed it and the answer to
        // 「스캔 스캔 스킨」 was dropped without a word (11/03). A newer request or closing still drops it.
        let screen=voiceScreen, began=ProcessInfo.processInfo.systemUptime
        // 「삐원으로 가」 reaches the model as 「P1으로 가」; the model reads numbers from sound poorly.
        let request=VoicePointSpelling.normalized(text)
        if request != text {logSignal("voice_point_spelling","\(text) -> \(request)")}
        voicePendingRequest=text
        Task { [weak self] in
            var decision=await AppleIntelligenceVoiceIntentResolver().resolve(request,screen:screen).checked(heard:request)
            guard let self, self.voiceShouldListen, self.voicePendingRequest == text, self.voiceScreen == screen else {return}
            self.voicePendingRequest=nil
            let seconds=String(format:"%.2fs",ProcessInfo.processInfo.systemUptime-began)
            let guessed: VoiceCommand? = {switch decision {case .command(let c),.confirm(let c): return c; case .none: return nil}}()
            if case .chooseStage(let number)? = guessed {
                let items=self.voiceSelectionNames
                if !items.indices.contains(number-1) || !VoiceStageSearch.mentions(text,number:number,name:items[number-1]) {
                    self.logSignal("voice_intent_dropped","chooseStage(\(number)) for \(text)");decision = .none
                }
            }
            switch decision {
            case .command(let command):
                self.logSignal("voice_intent","model \(command) \(seconds)");self.performVoiceCommand(command)
            case .confirm(let command):
                self.logSignal("voice_intent","ask \(command) \(seconds)")
                self.pendingVoiceIntent=command;self.read([self.voiceQuestion(command)])
            case .none:
                self.logSignal("voice_intent","none \(seconds)");self.readVoiceCommandNotUnderstood()
            }
        }
        return true
        #else
        return false
        #endif
    }
    /// A stage is asked by its number and name, so the user hears which one would be picked.
    private func voiceQuestion(_ command:VoiceCommand) -> String {
        if case .chooseStage(let number)=command, voiceSelectionNames.indices.contains(number-1) {
            return L("%@번, %@. 선택할까요?", number, voiceSelectionNames[number-1])
        }
        return VoiceIntentCopy.question(command)
    }
    private func readVoiceCommandNotUnderstood() {
        logSignal("voice_not_understood","")
        read([L("요청을 확실히 이해하지 못했어요. %@", phase == .selection ? L("무대 선택 화면에서는 장소나 무대 이름을, 사용 방식 화면에서는 연습용 또는 실전용을 말씀해주세요.") : L("계속, 멈춰, 또는 P2로 다시 안내해 줘처럼 한 가지 요청을 말씀해주세요."))])
    }
    private func performVoiceCommand(_ command:VoiceCommand, confirmed:Bool = false) {
            switch command {
            case .practice,.performance:
                if phase == .selection, voiceChoosingMode {selectVoiceMode(command == .practice ? .practice : .performance)}
                else if phase == .selection {
                    // Kept for when a stage is chosen, so the mode is not asked again (#156).
                    voiceInitialMode = command == .practice ? .practice : .performance
                    read([L("먼저 사용할 무대를 선택해주세요. 장소 이름으로 검색하거나 무대 이름을 말씀해주세요.")])
                }
                else {read([L("사용 방식은 안내 시작 전에 선택할 수 있어요. 계속이라고 말씀하면 현재 안내를 이어갑니다.")])}
            case .returnToPoint(let index): requestVoiceReturn(to:index)
            case .continueGuidance,.next,.start: advanceWithVoice()
            case .pause:
                if phase == .guiding || phase == .starting {pause()}
                else if phase == .paused {read([L("안내를 멈췄어요. 계속이라고 말씀하면 이어서 안내해요.")])}
                else {read([L("현재 단계에서 기다릴게요. 준비되면 다음이라고 말씀해주세요.")])}
            case .repeatInstruction: replay()
            case .cancel:
                read([started ? L("요청을 취소했어요. 안내는 멈춘 상태예요. 계속이라고 말씀하면 다시 안내해요.") : L("요청을 취소했어요. 사용할 무대나 사용 방식을 말씀해주세요.")])
            case .showAllStages:
                guard phase == .selection, !voiceChoosingMode else {read([L("저장된 무대 목록은 무대 선택 화면에서 들을 수 있어요.")]);return}
                guard !voiceStages.isEmpty else {selectionDescription(empty:true);return}
                showVoiceStageResults(query:nil,ids:nil)
            case .chooseStage(let number):
                guard phase == .selection,!voiceChoosingMode else {return}
                selectVisibleVoiceItem(number)
            case .back:
                // The same step back as the 「취소 · 이전 선택」 button; after the start there is no earlier step.
                if canCancelVoiceSelection {cancelVoiceSelection()}
                else if started {read([L("안내를 시작한 뒤에는 이전 단계가 없어요. 무대를 바꾸려면 무대 다시 선택이라고 말씀해주세요.")])}
                else {read([L("지금이 첫 단계예요. 사용할 무대 이름이나 목록 번호를 말씀해주세요.")])}
            case .chooseStageAgain:
                guard phase != .selection || voiceChoosingMode || selected != nil else {selectionDescription(empty:voiceStages.isEmpty);return}
                // Leaving a started run drops it, so that is asked first; before the start nothing is lost.
                if started && !confirmed {
                    pendingVoiceIntent = .chooseStageAgain;read([VoiceIntentCopy.question(.chooseStageAgain)]);return
                }
                logSignal("voice_choose_stage_again",started ? "run_dropped" : "before_start")
                resetSignals();voicePausedNavigation=false;voicePerformanceID=nil
                chooseAgain()
            }
    }
    /// The mode said with a stage, unless a name on offer holds that word itself (a stage called 「연습 무대」).
    private func voiceModeWithStage(_ text:String) -> (mode:VoiceCommand,rest:String)? {
        guard let split=VoiceCommandParser.splitMode(text) else {return nil}
        let names=voiceSelectionNames+voiceStages.map(\.name)
        guard !names.contains(where:{$0.contains(split.stem)}) else {return nil}
        return (split.mode,split.rest)
    }
    private func selectStageWithVoice(_ text:String) -> Bool {
        if let ordinal=VoiceStageSearch.ordinal(text) ?? VoiceStageSearch.numbered(text,names:voiceSelectionNames) {
            selectVisibleVoiceItem(ordinal);return true
        }
        if showsVoicePerformances {
            let choices=voicePerformanceChoices
            if case .selected(let index)=VoiceStageSearch.resolve(text,names:choices.map(\.name)) {
                selectVoicePerformance(choices[index].id);return true
            }
        }
        let candidates=voicePerformanceID == nil ? voiceStages : visibleVoiceStages
        let aliases=candidates.map {item in
            (voiceStagePaths[item.id] ?? []) + [voiceStageTitle(item)]
        }
        switch VoiceStageSearch.resolve(text,names:candidates.map(\.name),contexts:aliases) {
        case .selected(let index): select(candidates[index]);return true
        case .results(let query,let indices):
            let ids=indices.map {candidates[$0].id}
            if ids.isEmpty,!VoiceStageSearch.isKeywordSearch(text),resolveVoiceIntent(text) {return true}
            showVoiceStageResults(query:query,ids:ids);return true
        case .none:return false
        }
    }
    private func showVoiceStageResults(query:String?,ids:[UUID]?) {
        voiceSelectionControlsVisible=false
        voiceRecognition.discardPendingSpeech()
        selected=nil;guide=nil;run=nil;pendingRecord=nil
        if ids == nil {voicePerformanceID=nil}
        voiceSearchQuery=query;voiceSearchIDs=ids
        announceVoiceStageResults()
    }
    func advanceWithVoice() {
        guard voiceExperiment, active else {return}
        switch phase {
        case .selection:
            if canContinueVoiceSelection {voiceSelectionControlsVisible=false;continueVoiceSelection();return}
            read([voiceChoosingMode ? L("연습용 또는 실전용이라고 말씀하면 바로 다음 단계로 넘어갑니다.") : L("사용할 무대 이름이나 목록 번호를 말씀해주세요.")])
        case .checkpoint:
            if performanceCheckpointsDone {confirmPerformanceCheckpoints()}
            else if canVerify {verifyCheckpoint()} else {read([L("확인점을 아직 확인할 수 없어요. 휴대폰 조준점을 저장한 확인점에 맞춰주세요.")])}
        case .wear:
            if canAdvanceInstruction && tracking.ready {finishWear()} else {read([L("위치 추적과 착용 상태를 먼저 확인해주세요.")])}
        case .departure:
            if departureReady && canAdvanceInstruction {startGuidance()} else {read([departureStatus])}
        case .paused:
            if canResume && canAdvanceInstruction {voicePausedNavigation=false;startGuidance()} else {read([isPractice ? L("현재 위치에서 안내를 재개할 수 없어요. 동선과 현재 위치를 다시 확인해주세요.") : L("현재 위치에서 안내를 재개할 수 없어요. 동선과 확인점을 다시 확인해주세요.")])}
        case .failed,.interrupted: restore()
        default: break
        }
    }
    func requestVoiceReturn(to number:Int) {
        guard voiceMode == .practice, started, phase == .paused || phase == .guiding else {
            read([L("지점으로 돌아가기는 연습 안내를 시작한 후 사용할 수 있어요.")]);return
        }
        guard let pose=freshPose(), var guide else {read([L("현재 위치를 확인할 수 없어요. %@", recoveryInstruction)]);return}
        guard let index=guide.rehearsalPointIndex(number:number) else {
            read([L("저장된 동선에 P%@ 지점이 없어요. 지점 이름을 다시 확인해주세요.", number)]);return
        }
        do {
            try guide.beginRehearsalReturn(to:index,position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guide.pause()
            self.guide=guide;aligningStep=nil;performanceHoldRemaining=0;phase = .paused;voicePausedNavigation=false
            tracking.setGuidanceTarget(guide.targetIndex)
            logSignal("rehearsal_return_requested","destination=\(voicePointName(index)) first=P\(guide.targetIndex)")
            startGuidance()
        } catch {
            read([L("%@로 돌아갈 수 없어요. %@", voicePointName(index), error.localizedDescription)])
        }
    }
    func reachedVoiceReturn(_ index:Int, time:Double) {
        guard voiceExperiment else {return}
        invalidateTasks();resetSignals();phase = .paused;voicePausedNavigation=true
        arrivedName="\(voicePointName(index))";message=L("%@에 도착했어요. 계속이라고 말씀하면 다음 지점으로 안내해요.", voicePointName(index))
        captureReplay(force:true)
        aligningStep=guide?.route.step(at:index).flatMap {$0.facingEdge == nil ? nil : $0}
        logSignal("rehearsal_return_arrived","\(voicePointName(index))")
        let operation=generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:700_000_000)
            guard let self, self.generation == operation, self.active, !self.voiceTurnActive, self.guide?.rehearsalReturnArrivalIndex == index else {return}
            self.keepVoiceConversation()
            self.read([self.guide?.route.spokenPointName(at:index) ?? self.voicePointName(index),L("%@ 지점에 도착했어요. 잠시 멈춰주세요. 계속이라고 말씀하면 다음 지점으로 안내해요.", self.voicePointName(index))])
        }
    }
}
