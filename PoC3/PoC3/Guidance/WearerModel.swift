import Foundation
import Combine
import UIKit

@MainActor
final class WearerModel: ObservableObject {
    let link = NearbyLink()
    let motion = BodyMotion()
    let speaker = SpeakerGuide()
    @Published private(set) var status = "폰을 배 앞에 세로로 고정하세요"
    @Published private(set) var relativeDegrees: Double?
    @Published private(set) var instruction: BodyInstruction?
    @Published private(set) var stage: StageReply?
    @Published private(set) var calibrated = false
    private var baseline: Double?
    private var referenceID: UUID?
    private var attemptedReference: UUID?
    private var routeID: UUID?
    private var currentRun: UUID?
    private var stoppedRun: UUID?
    private var arrivedRun: UUID?
    private var arrival = ArrivalGate()
    private var clock = ReplyClock()
    private var ledger = RunLedger()
    private var deadline = -Double.infinity
    private var lastReplyAt = -Double.infinity
    private var timer: Timer?
    private var activeScene = true
    private var wasGuiding = false
    var now: Double { ProcessInfo.processInfo.systemUptime }

    var currentPosition: MapPoint? { now <= deadline ? stage?.position : nil }
    func userStop() {
        link.send(.stop(nil), reliable: true)
        invalidate("사용자가 안내를 중지했습니다. 정면 보정 후 다시 시작하세요.")
    }
    func prepareAudio() {
        if currentRun != nil { halt("소리 재준비 · 운영자가 안내 시작을 다시 눌러주세요", speak: false) }
        speaker.prepare()
    }
    func readDirection() {
        guard currentRun == nil, let relativeDegrees else { return }
        if speaker.speechStyle == .clock {
            speaker.announce("무대 정면을 12시로 볼 때 현재 몸은 \(DirectionSpeechStyle.hour(degrees: relativeDegrees))시 방향입니다")
            return
        }
        let angle = Int(abs(relativeDegrees).rounded())
        speaker.announce(angle < 5 ? "현재 몸은 무대 정면을 향합니다" : "무대 정면에서 \(relativeDegrees < 0 ? "왼쪽" : "오른쪽") \(angle)도 방향입니다")
    }
    func begin() {
        guard timer == nil else { return }
        link.onMessage = { [weak self] in self?.receive($0) }
        link.onDisconnect = { [weak self] in
            self?.invalidate("연결이 끊겼습니다. 멈춰주세요.")
            self?.clock = ReplyClock(); self?.ledger = RunLedger()
        }
        speaker.onUnavailable = { [weak self] in self?.halt("소리 출력 확인 필요 · 운영자가 다시 시작해야 합니다", speak: false) }
        link.start(.wearer)
        motion.start()
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    private func tick() {
        guard activeScene else { return }
        speaker.validateOutput()
        let fresh = motion.fresh(at: now)
        if !fresh, baseline != nil { invalidate("몸 방향을 확인할 수 없습니다. 멈추고 정면을 다시 맞춰주세요.") }
        relativeDegrees = fresh ? baseline.flatMap { base in motion.heading.map { BodyNavigationMath.wrap($0 - base) } } : nil
        if link.connected {
            var poll = WearerPoll()
            poll.calibratedReference = calibrated ? referenceID : nil
            poll.relativeDegrees = relativeDegrees
            poll.bodyReady = fresh; poll.speakerReady = speaker.ready
            poll.stoppedRun = stoppedRun; poll.arrivedRun = arrivedRun
            clock.issue(poll.id, at: now)
            link.send(.poll(poll))
        }
        if currentRun != nil, now > deadline || now - lastReplyAt > 0.5 {
            halt("위치 또는 연결 수신이 늦습니다. 멈춰주세요.")
        }
        evaluate()
    }
    private func receive(_ message: PeerMessage) {
        guard activeScene else { return }
        switch message {
        case .stage(let reply):
            guard let sent = clock.accept(reply.pollID, at: now), ledger.accept(revision: reply.revision) else { return }
            if routeID != reply.routeID {
                if currentRun != nil { halt("이동 경로가 변경되었습니다. 멈추고 정면을 맞춰주세요.", speak: wasGuiding) }
                baseline = nil; calibrated = false; referenceID = nil; attemptedReference = nil
                routeID = reply.routeID
            }
            stage = reply; lastReplyAt = now
            if let newReference = reply.referenceID, newReference != attemptedReference,
               motion.fresh(at: now), let heading = motion.heading, speaker.ready {
                baseline = heading; referenceID = newReference; attemptedReference = newReference
                calibrated = true; relativeDegrees = 0
                status = "객석 방향을 정면 0°로 보정했습니다 · 안내 시작 대기"
                speaker.announce("현재 몸 방향을 무대 정면으로 설정했습니다")
            }
            if reply.referenceID != referenceID {
                baseline = nil; calibrated = false; referenceID = nil; relativeDegrees = nil
            }
            deadline = ReplyClock.positionDeadline(sent: sent, age: reply.positionAge) ?? -.infinity
            guard let run = reply.runID else {
                if currentRun != nil { halt("안내가 중지되었습니다. 멈춰주세요.", speak: arrivedRun != currentRun) }
                if !calibrated { status = reply.message }
                return
            }
            guard ledger.permits(run) else { return }
            guard calibrated, speaker.ready, reply.referenceID == referenceID,
                  now <= deadline, reply.position != nil else {
                stoppedRun = run; ledger.retire(run)
                link.send(.stop(run), reliable: true)
                halt("위치·방향·음성 출력를 확인한 뒤 다시 시작해주세요."); return
            }
            if currentRun != run { currentRun = run; arrival = ArrivalGate() }
            evaluate()
        case .stop(let run):
            if let run { ledger.retire(run) }
            if run == nil || currentRun == run {
                halt("안내가 중지되었습니다. 멈춰주세요.")
            }
        case .poll: break
        }
    }
    private func evaluate() {
        guard let run = currentRun, run != stoppedRun, run != arrivedRun else { return }
        guard let stage, let p = stage.position, let d = stage.target,
              let relativeDegrees, motion.fresh(at: now), now <= deadline, calibrated, speaker.ready,
              StageGeometry.validate(stage.polygon) == nil,
              GuidanceMath.routeInside(p, d, polygon: stage.polygon),
              let next = BodyNavigationMath.instruction(position: p, target: d, relativeDegrees: relativeDegrees) else {
            halt("위치 또는 방향 확인이 필요합니다. 멈춰주세요."); return
        }
        let previousKind = instruction?.kind
        instruction = next; wasGuiding = true
        if next.kind == .arrived {
            // Ask P to stop on first entry, rather than silently waiting for dwell.
            if previousKind != .arrived {
                speaker.stop(); speaker.announce("목적지 근처입니다. 멈춰주세요.")
            }
            if arrival.update(inside: true, now: now) {
                ledger.retire(run)
                arrivedRun = run; currentRun = nil; wasGuiding = false
                status = "도착 · 0.3m 이내에서 0.6초 확인"
                speaker.update(next, now: now)
            } else { status = "도착 범위 · 멈춰서 위치 확인 중" }
        } else {
            if previousKind == .arrived { speaker.stop() }
            _ = arrival.update(inside: false, now: now)
            status = speaker.phrase(next)
            speaker.update(next, now: now)
        }
    }
    func halt(_ reason: String = "사용자가 안내를 중지했습니다. 멈춰주세요.", speak: Bool = true) {
        let run = currentRun
        if let run { stoppedRun = run; ledger.retire(run); link.send(.stop(run), reliable: true) }
        currentRun = nil; instruction = nil; arrival = ArrivalGate()
        speaker.stop()
        if speak && wasGuiding { speaker.announce(reason) }
        wasGuiding = false; status = reason
    }
    func invalidate(_ reason: String) {
        halt(reason)
        baseline = nil; referenceID = nil; calibrated = false; relativeDegrees = nil
        // attemptedReference remains latched: the operator must request a NEW calibration.
    }
    func sceneChanged(active: Bool) {
        activeScene = active
        if !active {
            invalidate("앱 비활성 · 운영자에게 정면 재보정을 요청하세요")
            speaker.shutdown(); motion.stop()
        } else {
            motion.start()
            status = "소리를 다시 준비하고 정면 보정을 요청하세요"
        }
    }
    func end() {
        halt(speak: false); timer?.invalidate(); timer = nil
        speaker.shutdown(); motion.stop(); link.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
