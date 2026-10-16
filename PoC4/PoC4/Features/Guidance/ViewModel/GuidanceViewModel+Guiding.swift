import PoC4Core

/// 안내 중 · 일시정지: direction cues, arrivals and pauses along the saved route.
extension GuidanceViewModel {
    var canResume: Bool {
        guard let pose=freshPose(), let guide else { return false }
        return guide.canResume(position:pose.point,trackingValid:true)
    }
    func pause() {
        guard phase == .guiding || phase == .starting else { return }
        invalidateTasks();guide?.pause();phase = started ? .paused : .departure
        message="현재 목표는 \(targetName)이에요."
        read(["안내를 일시정지했습니다. 다시 시작 버튼을 누르면 이어서 안내합니다."])
    }
    func tickGuiding(pose: (point: FloorPoint, heading: Double, time: Double), guide current: RouteGuide) {
        var guide=current
        let previous=guide.targetIndex
        let update=guide.observe(time:pose.time,position:pose.point,headingDegrees:pose.heading,trackingValid:true,allowsTargetAdvance:!announcingArrival)
        self.guide=guide;cue=guide.cue(position:pose.point,headingDegrees:pose.heading)
        tracking.setGuidanceTarget(guide.targetIndex,completed:guide.state == .completed)
        if update.state == .completed { playCompletion();return }
        if update.state == .paused {
            phase = .paused
            switch guide.pauseReason {
            case .obstacleProximity: message="등록한 기물과 가까워졌어요. 현재 위치와 동선을 확인해주세요."
            case .offRoute,.outsideStage: message="저장된 동선의 안내 범위를 벗어났어요. 현재 위치와 동선을 확인해주세요."
            default: message="위치와 방향을 다시 확인해주세요."
            }
            read(["잠시 멈춰주세요. \(message)"]);return
        }
        if update.targetIndex != previous {
            let previousName=GuidanceCopy.target(previous,last:guide.route.points.count-1)
            announcingArrival=true;arrivedName=previousName
            read(["\(previousName)에 도착했습니다. \(targetName)으로 이동합니다."]) { [weak self] in
                guard let self, self.phase == .guiding else { return }
                self.announcingArrival=false;self.arrivedName=nil
                if let pose=self.freshPose(), let cue=self.guide?.cue(position:pose.point,headingDegrees:pose.heading) {
                    self.voice.direction(cue.speech)
                }
            }
        } else if let announcement=update.announcement { voice.direction(announcement) }
    }
}
