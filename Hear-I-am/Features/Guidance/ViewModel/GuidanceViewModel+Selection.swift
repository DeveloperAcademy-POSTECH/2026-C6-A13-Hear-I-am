import HearIAmCore

/// 1 / 4 · 무대 선택
extension GuidanceViewModel {
    func selectionDescription(empty: Bool) {
        guard phase == .selection, selected == nil, selectedPlan == nil else { return }
        read([empty ? "저장된 무대나 사전 동선이 없습니다. 홈에서 공연 사전 저장 또는 무대 준비하기를 먼저 진행해주세요." : "안내에 사용할 무대 또는 사전 동선을 선택해주세요."])
    }
    func select(_ item: ScanManifest) {
        guard phase == .selection else { return }
        guard let route=item.route, route.conflicts(boundaryMargin:item.settings.boundaryMargin,obstacleClearance:item.settings.obstacleClearance).isEmpty else {
            read(["이 무대에는 사용할 수 있는 동선이 없습니다. 무대를 다시 준비해주세요."]);return
        }
        selectedPlan=nil;selected=item;guide=RouteGuide(route:route,settings:item.settings,usesRouteCorridor:true)
        started=false;cue=nil;pendingRecord=nil
        run=GuidanceRun(stageID:item.id,stageName:item.name,route:route)
        tracking.setGuidanceTarget(1)
        read(["\(item.name)을 선택했습니다. 내부 지점은 \(max(0,route.points.count-2))개입니다."])
    }
    func selectPlan(_ plan: PerformancePlan) {
        guard phase == .selection else { return }
        guard let calibrated=try? plan.calibratedStage(startWorld:Point3(0,0,0),cameraForward:Point3(0,0,-1)),
              calibrated.route.conflicts(boundaryMargin:calibrated.settings.boundaryMargin,obstacleClearance:calibrated.settings.obstacleClearance).isEmpty else {
            read(["이 사전 동선에는 사용할 수 있는 경로가 없습니다. 동선을 다시 확인해주세요."]);return
        }
        selected=nil;selectedPlan=plan
        guide=RouteGuide(route:calibrated.route,settings:calibrated.settings,usesRouteCorridor:true,allowsFreeMovement:true)
        started=false;cue=nil;pendingRecord=nil
        run=GuidanceRun(stageID:plan.id,stageName:plan.name,route:calibrated.route)
        tracking.setGuidanceTarget(1)
        let widthText=String(format:"%.1f",plan.stageWidth)
        let depthText=String(format:"%.1f",plan.stageDepth)
        read(["\(plan.name) 사전 동선을 선택했습니다. 무대 크기 가로 \(widthText)미터, 세로 \(depthText)미터, 내부 지점은 \(max(0,plan.points.count-2))개입니다."])
    }
    func chooseAgain() {
        invalidateTasks();tracking.endSession();guide=nil;run=nil;pendingRecord=nil;selected=nil;selectedPlan=nil;started=false;phase = .selection
        read(["안내에 사용할 무대를 다시 선택해주세요."])
    }
}
