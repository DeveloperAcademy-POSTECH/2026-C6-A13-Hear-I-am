import Foundation
import HearIAmCore

/// 4 / 4 · 출발 준비: the wearer must hold a valid start (or resume) pose for one second.
extension GuidanceViewModel {
    var departureStatus: String {
        guard let pose=freshPose(), let guide else {
            return tracking.heading == nil ? "카메라가 바닥이나 천장을 향하지 않도록 허리 앞쪽에 세워주세요." : "현재 위치를 다시 확인하고 있어요."
        }
        if !started, pose.point.distance(to:guide.route.points[0]) > guide.settings.startRadius {
            return "지정한 출발점에 더 가까이 서주세요."
        }
        if let issue=guide.positionIssue(pose.point) {
            return issue == .obstacleProximity ? "등록한 기물과 가까워요. 출발 위치와 동선을 확인해주세요." : "저장한 동선 위에 서주세요."
        }
        return departureReady ? "위치와 몸의 방향이 확인됐어요." : "위치와 방향을 확인 중이에요. 잠시 멈춰주세요."
    }
    /// Starts from departure, or resumes from a pause, after the start announcement finishes.
    func startGuidance() {
        guard (phase == .departure && departureReady || phase == .paused && canResume), canAdvanceInstruction, active else { return }
        invalidateTasks()
        phase = .starting
        let instructions=started ? ["안내를 다시 시작합니다."] : ["안내를 시작합니다.",
            "높은 비프가 나면 왼쪽으로, 낮은 비프가 나면 오른쪽으로 몸을 돌려주세요. 방향에 가까워질수록 세 번, 두 번, 한 번 울립니다. 방향이 맞으면 띠링 후 조용해집니다. 지점에 도착하면 또로롱 소리가 납니다. 방향을 맞춘 뒤 남은 거리를 미터 단위로 읽고, 옆을 지나는 기물의 이름을 알려드립니다."]
        read(instructions+["\(targetName)으로 이동합니다."]) { [weak self] in
            guard let self, self.phase == .starting, var guide=self.guide else { return }
            guard let pose=self.freshPose() else { self.interrupt("현재 위치를 확인할 수 없어요. 확인점을 다시 확인해주세요.");return }
            let success=self.started ? guide.resume(position:pose.point,trackingValid:true) : guide.start(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
            guard success else {
                self.phase = .departure;self.departureReady=false;self.departureGate.reset();self.readyAnnounced=false
                self.read(["출발 조건이 달라졌습니다. 위치와 방향을 다시 확인해주세요."]);return
            }
            self.guide=guide;self.run?.begin(at:Date(),uptime:ProcessInfo.processInfo.systemUptime);self.started=true;self.phase = .guiding;self.lastPoseTime=nil
            self.resetSignals()
        }
    }
    func tickDeparture(pose: (point: FloorPoint, heading: Double, time: Double), guide: RouteGuide) {
        let eligible=started ? guide.canResume(position:pose.point,trackingValid:true) : guide.ready(position:pose.point,headingDegrees:pose.heading,trackingValid:true)
        departureReady=departureGate.observe(time:pose.time,eligible:eligible)
        if !eligible {
            if readyAnnounced {read(["출발 위치 또는 방향이 달라졌습니다. 다시 확인해주세요."])}
            readyAnnounced=false
        }
        if departureReady, !readyAnnounced, instructionDone, !speaking {
            readyAnnounced=true
            read([started ? "재개 준비가 완료됐습니다. 안내 다시 시작 버튼을 눌러주세요." : "출발 준비가 완료됐습니다. 안내 시작 버튼을 누르면 첫 번째 지점으로 안내합니다."])
        }
    }
}
