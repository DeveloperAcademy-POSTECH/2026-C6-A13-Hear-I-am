import HearIAmCore

/// 1 / 4 · 무대 선택
extension GuidanceViewModel {
    func selectionDescription(empty: Bool) {
        guard phase == .selection else { return }
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
        read(["\(item.name)을 선택했습니다. 내부 지점은 \(max(0,route.points.count-2))개입니다."])
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;started=false;phase = .selection
        read(["안내에 사용할 무대를 다시 선택해주세요."])
    }
}
