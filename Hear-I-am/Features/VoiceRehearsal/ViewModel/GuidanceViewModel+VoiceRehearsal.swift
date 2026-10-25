import Foundation
import Combine
import HearIAmCore

/// Opt-in #69 experiment. Commands use the same guards as the existing touch controls.
extension GuidanceViewModel {
    var voiceCanOfferInput: Bool {
        guard voiceExperiment, active, !showExit, !savingRecord, escape == nil, audioIssue == nil else {return false}
        if voiceMode == .performance && (started || phase == .starting) {return false}
        return [.selection,.checkpoint,.wear,.departure,.guiding,.paused,.failed,.interrupted].contains(phase)
    }
    var voiceShouldListen: Bool { voiceCanOfferInput && voiceListeningEnabled }
    var voiceProcessingCommand: Bool {voiceTurnActive && !voiceRecognition.isListening}
    var voiceStatusTitle: String {
        if voiceMode == .performance && (started || phase == .starting) {return "실전 안내 중 · 음성 인식 꺼짐"}
        if voiceTurnActive {return voiceProcessingCommand ? "말씀을 확인하고 있어요" : "듣고 있어요 · 이동 안내 일시정지"}
        if phase == .paused, let index=guide?.rehearsalReturnArrivalIndex {return "P\(index)에 도착했어요"}
        if voiceInputError != nil {return "음성 입력을 확인해주세요"}
        if !voiceListeningEnabled {return "음성 입력 꺼짐"}
        if speaking {return "안내가 끝나면 들을게요"}
        if phase == .guiding, let index=guide?.rehearsalReturnDestinationIndex {return "P\(index)로 다시 안내 중"}
        return voiceRecognition.isListening ? "말씀하시면 들을게요" : "음성 입력 준비 중"
    }
    var voiceStatusDetail: String {
        if voiceMode == .performance && (started || phase == .starting) {return "마이크를 끈 상태로 저장된 동선을 안내해요."}
        if phase == .paused, guide?.rehearsalReturnArrivalIndex != nil {return "‘계속’이라고 말하거나 안내 다시 시작을 눌러주세요."}
        if voiceTurnActive {return "예: ‘P2 지점으로 다시 안내해 줘’, ‘계속’, ‘멈춰’."}
        if speaking {return "앱 음성이 끝난 뒤 말씀해주세요. 버튼으로 다시 말할 수도 있어요."}
        if phase == .selection {return selected == nil ? "저장한 무대 이름이나 목록 순서를 말씀해주세요." : voiceMode == nil ? "‘연습용’ 또는 ‘실전용’이라고 말씀해주세요." : "‘다음’이라고 말하면 현장 확인으로 넘어가요."}
        if phase == .guiding {return "띠링이 들리면 잠시 멈춰주세요. 지나온 내부 지점으로 돌아갈 수 있어요."}
        return "‘다음’ 또는 ‘계속’이라고 말씀해주세요. 위치·착용 확인은 그대로 필요해요."
    }

    func configureVoiceExperiment() {
        guard voiceExperiment else {return}
        voiceRecognition.onSpeechDetected={ [weak self] in self?.voiceSpeechDetected() }
        voiceRecognition.onTranscript={ [weak self] text in self?.voiceTranscript=text }
        voiceRecognition.onFinal={ [weak self] text in self?.handleVoiceCommand(text) }
        voiceRecognition.onError={ [weak self] error in self?.voiceInputFailed(error) }
        voiceRecognition.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in:&voiceSubscriptions)
        voiceRecognition.$isListening.dropFirst().sink { [weak self] listening in
            guard let self, listening, self.voiceReadyChimePending, self.voiceShouldListen else {return}
            self.voiceReadyChimePending=false
            self.listeningChime.play()
        }.store(in:&voiceSubscriptions)
    }
    func prepareVoiceExperiment(records:[ScanManifest]) {
        guard voiceExperiment else {return}
        voiceStages=records
        voiceReadyChimePending=true
        syncVoiceListening()
    }
    func selectVoiceMode(_ mode:VoiceUsageMode) {
        guard voiceExperiment, phase == .selection else {return}
        voiceMode=mode
        read([mode == .practice ? "연습용을 선택했어요. 안내 중 말씀하시면 잠시 멈추고 들을게요." : "실전용을 선택했어요. 안내가 시작되면 음성 인식을 끕니다.", selected == nil ? "사용할 무대 이름을 말씀해주세요." : "다음이라고 말씀하면 현장 확인으로 넘어갑니다."])
        syncVoiceListening()
    }
    func syncVoiceListening() {
        guard voiceExperiment else {return}
        guard voiceShouldListen else {
            voiceInputTask?.cancel();voiceInputTask=nil
            voiceRecognitionRequested=false
            voiceRecognition.stop();voiceTurnActive=false
            return
        }
        guard !voiceRecognitionRequested else {return}
        voiceRecognitionRequested=true
        voiceRecognition.setOutputSuppressed(speaking)
        let hints=voiceStages.map(\.name)+["연습용","실전용","다음","계속","멈춰","P2 지점으로 다시 안내해 줘","피투","2번 지점"]
        voiceInputTask=Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled, self.voiceShouldListen else {return}
            await self.voiceRecognition.start(contextualStrings:hints)
        }
    }
    func stopVoiceExperiment() {
        voiceInputTask?.cancel();voiceInputTask=nil
        voiceRecognitionRequested=false;voiceTurnActive=false
        voiceRecognition.stop();listeningChime.stop()
    }
    func disableVoiceListening() {
        voiceListeningEnabled=false;voiceInputError=nil
        stopVoiceExperiment()
    }
    func retryVoiceListening() {
        guard voiceCanOfferInput else {return}
        // Manual retry can interrupt an instruction; it never advances a navigation phase.
        generation=UUID();voice.stop();instructionDone=true
        stopVoiceExperiment()
        if phase == .guiding {
            guide?.pause();phase = .paused;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message="다시 말씀하실 수 있도록 안내를 멈췄어요."
            captureReplay(force:true)
        }
        voiceInputError=nil;voiceListeningEnabled=true;voiceReadyChimePending=true
        syncVoiceListening()
    }
    func voiceSpeechDetected() {
        guard voiceShouldListen, !speaking, !voiceTurnActive else {return}
        voiceTurnActive=true;voiceTranscript=""
        if phase == .guiding {
            guide?.pause();phase = .paused;voicePausedNavigation=true
            signals.stopDirection();quietUntil=nil
            message="말씀을 듣고 있어요. 잠시 멈춰주세요."
            captureReplay(force:true)
        }
        listeningChime.play()
        logSignal("voice_listening","speech_detected")
    }
    func voiceInputFailed(_ error:String) {
        stopVoiceExperiment()
        voiceRecognitionRequested=false;voiceTurnActive=false
        voiceListeningEnabled=false;voiceInputError=error
        if voiceMode == .practice, phase == .guiding {
            guide?.pause();phase = .paused;voicePausedNavigation=true;signals.stopDirection()
            message="음성 입력이 중단되어 연습 안내를 멈췄어요."
        }
        if active {read([error])}
    }
    func handleVoiceCommand(_ text:String) {
        guard voiceShouldListen, !speaking else {return}
        voiceTurnActive=false;voiceTranscript=text
        logSignal("voice_command",text)
        if phase == .selection, selectStageWithVoice(text) {return}
        if let command=VoiceCommandParser.parse(text) {
            switch command {
            case .practice,.performance:
                if phase == .selection {selectVoiceMode(command == .practice ? .practice : .performance)}
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
            }
        } else {read(["요청을 확실히 이해하지 못했어요. \(phase == .selection ? "무대 이름, 연습용, 실전용, 다음 중 하나를 말씀해주세요." : "계속, 멈춰, 또는 P2로 다시 안내해 줘처럼 한 가지 요청을 말씀해주세요.")"])}
    }
    private func selectStageWithVoice(_ text:String) -> Bool {
        func normalize(_ value:String)->String {
            value.lowercased().filter {$0.isLetter || $0.isNumber}
        }
        let query=normalize(text)
        let matches=voiceStages.filter { item in
            let name=normalize(item.name)
            return !name.isEmpty && (query == name || ["선택","선택해줘","사용","사용할게","로안내해줘"].contains {query == name+$0})
        }
        if matches.count == 1, let item=matches.first {select(item);return true}
        if matches.count > 1 {read(["같은 이름의 무대가 여러 개 있어요. 화면에서 저장 날짜를 확인해 선택해주세요."]);return true}
        // Ordinals are only interpreted as a list selection on the selection screen.
        let ordinals=["첫번째","두번째","세번째","네번째","다섯번째","여섯번째","일곱번째","여덟번째","아홉번째","열번째"]
        var ordinal:Int?
        if let i=ordinals.firstIndex(where:{query == $0 || query == $0+"무대" || query == $0+"선택"}) {ordinal=i}
        if let range=query.range(of:"^[0-9]+번(무대|선택)?$",options:.regularExpression) {
            ordinal=Int(query[range].prefix(while:{$0.isNumber})).map {$0-1}
        }
        if let ordinal, voiceStages.indices.contains(ordinal) {select(voiceStages[ordinal]);return true}
        return false
    }
    func advanceWithVoice() {
        guard voiceExperiment, active else {return}
        switch phase {
        case .selection:
            guard selected != nil else {read(["먼저 사용할 무대 이름을 말씀해주세요."]);return}
            guard voiceMode != nil else {read(["연습용 또는 실전용이라고 말씀해주세요."]);return}
            restore()
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
    func requestVoiceReturn(to index:Int) {
        guard voiceMode == .practice, started, phase == .paused || phase == .guiding else {
            read(["지점으로 돌아가기는 연습 안내를 시작한 후 사용할 수 있어요."]);return
        }
        guard let pose=freshPose(), var guide else {read(["현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요."]);return}
        do {
            try guide.beginRehearsalReturn(to:index,position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guide.pause()
            self.guide=guide;phase = .paused;voicePausedNavigation=false
            tracking.setGuidanceTarget(guide.targetIndex)
            logSignal("rehearsal_return_requested","destination=P\(index) first=P\(guide.targetIndex)")
            startGuidance()
        } catch {
            read(["P\(index)로 돌아갈 수 없어요. \(error.localizedDescription)"])
        }
    }
    func reachedVoiceReturn(_ index:Int, time:Double) {
        guard voiceExperiment else {return}
        invalidateTasks();resetSignals();phase = .paused;voicePausedNavigation=true
        arrivedName="P\(index)";message="P\(index)에 도착했어요. 계속이라고 말씀하면 다음 지점으로 안내해요."
        captureReplay(force:true)
        signals.play(.arrival)
        logSignal("rehearsal_return_arrived","P\(index)")
        let operation=generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds:700_000_000)
            guard let self, self.generation == operation, self.active, !self.voiceTurnActive, self.guide?.rehearsalReturnArrivalIndex == index else {return}
            self.read(["P\(index) 지점에 도착했어요. 잠시 멈춰주세요. 계속이라고 말씀하면 다음 지점으로 안내해요."])
        }
    }
    func tickVoiceHold(pose:(point:FloorPoint,heading:Double,time:Double)) {
        guard voiceExperiment, phase == .paused, escape == nil, voicePausedNavigation || voiceTurnActive || guide?.rehearsalReturnArrivalIndex != nil, let guide else {return}
        let warning=warnings.update(position:pose.point,headingDegrees:pose.heading,obstacles:guide.route.obstacles)
        signals.setWarning(warning?.level)
    }
}
