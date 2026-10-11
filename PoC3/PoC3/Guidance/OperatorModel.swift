import Combine
import Foundation
import UIKit

@MainActor
final class OperatorModel: ObservableObject {
    let scanner = StageScanController()
    let link = NearbyLink()
    @Published private(set) var startPoint: MapPoint?
    @Published private(set) var target: MapPoint?
    @Published private(set) var status = "착용 폰 연결 후 무대를 스캔하세요"
    @Published private(set) var active = false
    @Published private(set) var calibrated = false
    @Published private(set) var bodyDegrees: Double?
    @Published private(set) var wearerReady = false
    private var revision: UInt64 = 0
    private var routeID = UUID()
    private var referenceID: UUID?
    private var runID: UUID?
    private var lastPoll: WearerPoll?
    private var lastPollAt = -Double.infinity
    private var timer: Timer?
    var now: Double { ProcessInfo.processInfo.systemUptime }
    var position: MapPoint? { scanner.normalTracking && !scanner.needsRestart ? scanner.guide.position : nil }
    var canCalibrate: Bool {
        position != nil && startPoint != nil && target != nil && wearerReady && link.connected && !active
    }
    func begin() {
        guard timer == nil else { return }
        link.onMessage = { [weak self] message in self?.receive(message) }
        link.onDisconnect = { [weak self] in self?.invalidate("연결 끊김 · 재연결 후 정면 보정하세요") }
        link.start(.operatorDevice)
        UIApplication.shared.isIdleTimerDisabled = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }
    func selectPerson(_ id: Int) {
        scanner.guide.select(id, time: now)
        startPoint = nil; target = nil
        invalidate("P 선택 완료 · 현재 위치를 시작점으로 확정하세요")
    }
    func captureStart() {
        guard let p = position, GuidanceMath.fresh(scanner.guide.lastObservation, now: now) else { return }
        startPoint = p
        invalidate("시작점 S 확정 · D를 지정하고 P를 객석 방향으로 정렬하세요")
    }
    func setTarget(_ point: MapPoint) {
        guard let map = scanner.guidanceMap, let startPoint,
              BodyNavigationMath.validPoint(point), GuidanceMath.routeInside(startPoint, point, polygon: map.floorPolygon) else {
            status = "시작점부터 D까지 직선이 무대 안에 있어야 합니다"; return
        }
        guard (point - startPoint).length > 0.3 else { status = "D는 시작점에서 0.3m보다 멀리 지정하세요"; return }
        target = point
        invalidate("D 설정 완료 · P가 객석을 바라보면 정면 보정을 요청하세요")
    }
    func calibrate() {
        guard canCalibrate else { return }
        revision &+= 1
        referenceID = UUID(); calibrated = false; bodyDegrees = nil
        status = "착용 폰 정면 보정 대기 · P는 객석을 바라보고 그대로 서세요"
    }
    func start() {
        guard canCalibrate, calibrated, let p = position, let target, let startPoint,
              (p - startPoint).length <= 0.5,
              GuidanceMath.routeInside(p, target, polygon: scanner.guide.polygon) else {
            status = "연결·소리·보정을 확인하고 P를 시작점 0.5m 이내에 배치하세요"; return
        }
        revision &+= 1
        runID = UUID(); active = true; status = "안내 중 · 착용 폰에서 소리 출력"
    }
    func pause(_ reason: String = "운영자가 안내를 중지했습니다") {
        revision &+= 1
        let previous = runID
        active = false; runID = nil; status = reason
        if let previous { link.send(.stop(previous), reliable: true) }
    }
    func invalidate(_ reason: String) {
        pause(reason)
        routeID = UUID(); referenceID = nil; calibrated = false; bodyDegrees = nil
    }
    func resetScan() {
        startPoint = nil; target = nil
        invalidate("다시 스캔한 후 P·S·D를 지정하세요")
        scanner.reset()
    }
    private func tick() {
        scanner.guide.expire(time: now)
        wearerReady = link.connected && now - lastPollAt <= 0.5 && lastPoll?.bodyReady == true && lastPoll?.speakerReady == true
        calibrated = wearerReady && referenceID != nil && lastPoll?.calibratedReference == referenceID
        if !wearerReady { bodyDegrees = nil }
        if active {
            guard wearerReady, calibrated, let p = position, let target else {
                pause("위치·방향·연결 확인 필요 · 안내 시작을 다시 누르세요"); return
            }
            if !GuidanceMath.routeInside(p, target, polygon: scanner.guide.polygon) {
                pause("P→D 직선이 무대 경계에 닿습니다 · 위치 확인 필요")
            }
        }
    }
    private func receive(_ message: PeerMessage) {
        switch message {
        case .poll(let poll):
            lastPoll = poll; lastPollAt = now
            bodyDegrees = poll.relativeDegrees.flatMap { $0.isFinite ? $0 : nil }
            if active, poll.stoppedRun == runID { pause("착용자가 중지했습니다 · 다시 시작하려면 상태를 확인하세요") }
            if active, poll.arrivedRun == runID {
                revision &+= 1
                active = false; runID = nil; status = "도착 완료 · 다음 이동은 시작점과 D를 다시 지정하세요"
            }
            tick()
            let age = max(0, now - scanner.guide.lastObservation)
            let p = age <= 0.5 ? position : nil
            link.send(.stage(StageReply(pollID: poll.id, revision: revision, routeID: routeID, referenceID: referenceID,
                                       runID: active ? runID : nil, polygon: scanner.guide.polygon,
                                       start: startPoint, position: p, target: target,
                                       positionAge: age.isFinite ? age : 1, message: status)))
        case .stop(let stopped):
            if stopped == nil || stopped == runID { pause("착용 폰에서 안내를 중지했습니다") }
        case .stage: break
        }
    }
    func suspend() {
        invalidate("앱 비활성 · P 정렬과 정면 보정을 다시 하세요")
    }
    func end() {
        pause(); timer?.invalidate(); timer = nil
        scanner.stop(); link.stop()
        UIApplication.shared.isIdleTimerDisabled = false
    }
}
