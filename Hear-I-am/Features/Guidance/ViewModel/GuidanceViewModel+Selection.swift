import HearIAmCore

/// 1 / 4 · 무대 선택
extension GuidanceViewModel {
    func selectionDescription(empty: Bool) {
        guard phase == .selection else { return }
        if voiceExperiment && !empty {
            read(["어느 무대를 사용할까요? 무대 이름을 말씀해주세요. 장소와 관련된 무대를 찾아달라고 하거나, 화면의 번호로 선택할 수도 있어요."])
            return
        }
        read([empty ? "저장된 무대가 없습니다. 홈에서 무대 준비하기를 통해 공간과 동선을 먼저 저장해주세요." : "안내에 사용할 무대를 선택해주세요."])
    }
    func select(_ item: ScanManifest) {
        guard phase == .selection else { return }
        guard let route=item.route, route.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty else {
            read(["이 무대에는 사용할 수 있는 동선이 없습니다. 무대를 다시 준비해주세요."]);return
        }
        selected=item;guide=RouteGuide(route:route,settings:item.settings,usesRouteCorridor:true)
        started=false;cue=nil;pendingRecord=nil
        run=GuidanceRun(stageID:item.id,stageName:item.name,route:route)
        tracking.setGuidanceTarget(1)
        var lines=["\(item.name)을 선택했습니다. 내부 지점은 \(max(0,route.points.count-2))개입니다."]
        if voiceExperiment {
            voiceRecognition.discardPendingSpeech();voiceTurnActive=false
            voiceMode=nil;voicePerformanceInputClosed=false;voiceChoosingMode=true
            lines=["\(item.name)이 선택되었습니다.","연습용 또는 실전용을 선택해주세요. 취소라고 말씀하면 무대 선택으로 돌아갑니다."]
        }
        read(lines)
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;started=false;phase = .selection
        if voiceExperiment {voiceChoosingMode=false;voiceMode=nil;voicePerformanceInputClosed=false;voiceRecognition.discardPendingSpeech()}
        selectionDescription(empty:voiceStages.isEmpty && voiceExperiment)
    }
}
