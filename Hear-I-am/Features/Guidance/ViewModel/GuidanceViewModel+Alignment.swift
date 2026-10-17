import Foundation
import HearIAmCore

/// Tilt alone preserves the verified AR session. Tracking loss still uses interrupt().
extension GuidanceViewModel {
    func beginAlignment() {
        guard phase == .guiding, guide?.state == .guiding else { return }
        invalidateTasks();guide?.pauseForUnclearHeading();phase = .aligning;cue=nil
        message="교정 후 위치와 방향이 1초 이상 확인되면 같은 목표로 자동 재개해요."
        lastPoseTime=nil
        tracking.event("guide_paused",detail:"unclearHeading:p\(targetIndex):horizontalRatio=\(tracking.guidanceHorizontalRatio ?? 0)")
        speakAlignmentPrompt()
    }

    func speakAlignmentPrompt() {
        lastAlignmentPrompt=ProcessInfo.processInfo.systemUptime
        tracking.event("guide_alignment_prompt",detail:"p\(targetIndex)")
        read(["후면 카메라를 몸 앞쪽으로 향하게 하고 수평을 맞춰 주세요."])
    }

    func tickAlignment() {
        guard let position=freshPosition() else {
            interrupt("위치 추적이 끊겼어요. 확인점을 다시 확인해주세요.");return
        }
        guard position.time != lastPoseTime, var guide else { return }
        lastPoseTime=position.time
        guard tracking.guidanceHorizontalRatio != nil else {
            interrupt("카메라 방향 정보를 확인할 수 없어요. 확인점을 다시 확인해주세요.");return
        }
        if let issue=guide.positionIssue(position.point) {
            invalidateTasks();guide.pause();self.guide=guide;phase = .paused
            message=issue == .obstacleProximity ? "등록한 기물과 가까워요. 현재 위치와 동선을 확인해주세요." : "저장된 동선의 안내 범위를 벗어났어요. 현재 위치와 동선을 확인해주세요."
            tracking.event("guide_alignment_cancelled",detail:"\(issue):p\(targetIndex)")
            read(["잠시 멈춰주세요. \(message)"]);return
        }
        let recovered=guide.observeAutomaticRecovery(time:position.time,position:position.point,
            headingDegrees:tracking.heading ?? .nan,trackingValid:tracking.ready,allowsResume:!speaking && audioIssue == nil)
        self.guide=guide
        if recovered {
            invalidateTasks();phase = .guiding
            cue=guide.cue(position:position.point,headingDegrees:tracking.heading ?? .nan)
            tracking.event("guide_auto_resumed",detail:"unclearHeading:p\(targetIndex)")
            // Hold arrival advancement while announcing resumption; route checks remain active.
            announcingArrival=true
            read(["카메라 방향이 확인됐습니다. \(targetName) 안내를 다시 시작합니다."]) { [weak self] in
                guard let self, self.phase == .guiding else { return }
                self.announcingArrival=false
                if let pose=self.freshPose(), let cue=self.guide?.cue(position:pose.point,headingDegrees:pose.heading) {
                    self.voice.direction(cue.speech)
                }
            }
        } else if tracking.heading == nil, !speaking, ProcessInfo.processInfo.systemUptime-lastAlignmentPrompt >= 6 {
            speakAlignmentPrompt()
        }
    }
}
