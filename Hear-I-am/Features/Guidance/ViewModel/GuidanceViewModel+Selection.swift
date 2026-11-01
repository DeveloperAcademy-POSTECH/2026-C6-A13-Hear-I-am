import HearIAmCore

/// 1 / 4 · 무대 선택
extension GuidanceViewModel {
    func selectionDescription(empty: Bool) {
        guard phase == .selection else { return }
        if voiceExperiment && empty {read(VoiceAppRequest.noStageOffer);return}
        if voiceExperiment {
            read([VoiceStepCopy.stageList],interruptible:true)
            return
        }
        read([empty ? "저장된 무대가 없습니다. 장소 탭의 새 스캔을 통해 공간과 동선을 먼저 저장해주세요." : "안내에 사용할 무대를 선택해주세요."])
    }
    func select(_ item: ScanManifest, advanceAutomatically: Bool = true) {
        guard phase == .selection else { return }
        guard item.supportsAlignment else {
            read(["이 무대는 확인점이 하나인 이전 버전입니다. 열람은 가능하지만 안내하려면 무대를 다시 준비해 확인점 두 개를 저장해주세요."]);return
        }
        guard let route=item.route, route.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty else {
            read(["이 무대에는 사용할 수 있는 동선이 없습니다. 무대를 다시 준비해주세요."]);return
        }
        selected=item;guide=RouteGuide(route:route,settings:item.settings,usesRouteCorridor:true,pausesForPositionIssues:false)
        started=false;aligningStep=nil;cue=nil;performanceHoldRemaining=0;pendingRecord=nil
        run=GuidanceRun(stageID:item.id,stageName:item.name,route:route)
        tracking.setGuidanceTarget(1)
        let lines=["\(item.name)을 선택했습니다. 내부 지점은 \(max(0,route.points.count-2))개입니다."]
        if voiceExperiment {
            voiceRecognition.discardPendingSpeech();voiceTurnActive=false
            voiceMode=nil;voicePerformanceInputClosed=false;voiceChoosingMode=advanceAutomatically
            voiceSelectionControlsVisible = !advanceAutomatically
            if advanceAutomatically {readVoiceModeQuestion()}
            else {prepareForVoiceTouch()}
            return
        }
        read(lines)
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;started=false;aligningStep=nil;performanceHoldRemaining=0
        if voiceExperiment {voiceChoosingMode=false;voiceMode=nil;voicePerformanceInputClosed=false;voiceRecognition.discardPendingSpeech()}
        phase = .selection
        selectionDescription(empty:voiceStages.isEmpty && voiceExperiment)
    }
}
