import HearIAmCore

/// 1 / 4 · 무대 선택
extension GuidanceViewModel {
    func selectionDescription(empty: Bool) {
        guard phase == .selection else { return }
        if voiceExperiment && empty {read(VoiceAppRequest.noStageOffer);return}
        if voiceExperiment {
            // Opened without a request: the saved performances are offered as cards straight away (Figma 495:5160).
            let choices=voicePerformanceChoices
            if !choices.isEmpty, voiceStartedAsHelper != true {showVoiceChatCards(performances:choices,text:L("어떤 공연을 준비할까요?\n공연 이름이나 번호를 말씀해주세요."))}
            read([VoiceStepCopy.stageList],interruptible:true)
            return
        }
        read([empty ? L("저장된 무대가 없습니다. 조력자 화면의 스캔 탭을 통해 공간과 동선을 먼저 저장해주세요.") : L("안내에 사용할 무대를 선택해주세요.")])
    }
    func select(_ item: ScanManifest, advanceAutomatically: Bool = true) {
        guard phase == .selection else { return }
        guard item.supportsAlignment else {
            read([L("이 무대는 확인점이 하나인 이전 버전입니다. 열람은 가능하지만 안내하려면 무대를 다시 준비해 확인점 두 개를 저장해주세요.")]);return
        }
        guard let route=item.route, route.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty else {
            read([L("이 무대에는 사용할 수 있는 동선이 없습니다. 무대를 다시 준비해주세요.")]);return
        }
        selected=item;guide=RouteGuide(route:route,settings:item.settings,usesRouteCorridor:true,pausesForPositionIssues:false)
        started=false;aligningStep=nil;cue=nil;performanceHoldRemaining=0;pendingRecord=nil;performanceCheckpointsDone=false
        run=GuidanceRun(stageID:item.id,stageName:item.name,route:route)
        tracking.setGuidanceTarget(1)
        let lines=[L("%@을 선택했습니다. 내부 지점은 %@개입니다.", item.name, max(0,route.points.count-2))]
        if voiceExperiment {
            voiceRecognition.discardPendingSpeech();voiceTurnActive=false
            voiceMode=nil;voicePerformanceInputClosed=false;voiceChoosingMode=advanceAutomatically
            voiceSelectionControlsVisible = !advanceAutomatically
            // A mode said before or with the stage (「뱀파이어 연습용」, or 「연습용」 then a name) is not asked again (#174).
            if advanceAutomatically, let mode=voiceInitialMode {
                voiceInitialMode=nil
                logSignal("voice_mode_remembered","\(mode)")
                selectVoiceMode(mode,namingStage:true)
            }
            else if advanceAutomatically {readVoiceModeQuestion()}
            else {prepareForVoiceTouch()}
            return
        }
        read(lines)
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;started=false;aligningStep=nil;performanceHoldRemaining=0;performanceCheckpointsDone=false
        if voiceExperiment {voiceChoosingMode=false;voiceMode=nil;voicePerformanceInputClosed=false;voiceRecognition.discardPendingSpeech()}
        phase = .selection
        selectionDescription(empty:voiceStages.isEmpty && voiceExperiment)
    }
}
