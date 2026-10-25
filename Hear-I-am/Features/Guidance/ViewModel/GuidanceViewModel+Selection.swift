import HearIAmCore

/// 1 / 4 · 무대 선택
extension GuidanceViewModel {
    func selectionDescription(empty: Bool) {
        guard phase == .selection else { return }
        if voiceExperiment && !empty {
            let list=voiceStages.prefix(5).enumerated().map {"\($0.offset+1)번, \($0.element.name)"}.joined(separator:". ")
            let remainder=voiceStages.count > 5 ? " 다른 무대는 화면 목록에서 확인할 수 있어요." : ""
            read(["말로 안내를 시작합니다. 저장된 무대는 \(list)입니다.\(remainder)","무대 이름이나 목록 순서를 말씀해주세요. 연습용 또는 실전용을 선택한 뒤 다음이라고 말씀하면 됩니다."])
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
        if voiceExperiment {lines.append(voiceMode == nil ? "연습용 또는 실전용이라고 말씀해주세요." : "다음이라고 말씀하면 현장 확인으로 넘어갑니다.")}
        read(lines)
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;started=false;phase = .selection
        read(["안내에 사용할 무대를 다시 선택해주세요."])
    }
}
