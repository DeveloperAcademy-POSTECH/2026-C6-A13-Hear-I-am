import CoreMotion
import Foundation
import OrientationCore

@MainActor
protocol WalkingFeed: AnyObject {
    func start(cycleID: UUID, from startDate: Date,
               onSample: @escaping @MainActor (WalkingSample) -> Void,
               onStatus: @escaping @MainActor (String) -> Void)
    func stop()
    func queryFinal(cycleID: UUID, from startDate: Date, to endDate: Date,
                    completion: @escaping @MainActor (WalkingSample?, String?) -> Void)
}

@MainActor
final class PedometerFeed: WalkingFeed {
    private let driver = PedometerDriver()
    private var revision: UInt = 0

    func start(cycleID: UUID, from startDate: Date,
               onSample: @escaping @MainActor (WalkingSample) -> Void,
               onStatus: @escaping @MainActor (String) -> Void) {
        revision &+= 1
        let token = revision
        onStatus("걸음 센서 준비 중 · 처리된 자료는 늦게 도착할 수 있어요.")
        Task { [driver, weak self] in
            await driver.start(from: startDate, revision: token) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard self?.revision == token else { return }
                    switch event {
                    case .sample(let sample):
                        onSample(sample)
                        onStatus("걸음 센서 수신 중 · 마지막 수신 \(Date().formatted(date: .omitted, time: .standard))")
                    case .status(let message): onStatus(message)
                    }
                }
            }
        }
    }

    /// Core Motion invokes legacy Objective-C handlers on its own queue, not our actor.
    nonisolated static func makeHandler(from start: Date,
        reply: @escaping @Sendable (WalkingSample?, String?) -> Void)
        -> @Sendable (CMPedometerData?, (any Error)?) -> Void {
        { data, error in
            let sample = data.map { WalkingSample(startDate: start, endDate: $0.endDate,
                                                  steps: $0.numberOfSteps.intValue, distance: $0.distance?.doubleValue) }
            reply(sample, error?.localizedDescription)
        }
    }

    func stop() {
        revision &+= 1
        let token = revision
        Task { await driver.stop(revision: token) }
    }

    func queryFinal(cycleID: UUID, from startDate: Date, to endDate: Date,
                    completion: @escaping @MainActor (WalkingSample?, String?) -> Void) {
        Task {
            await driver.queryFinal(cycleID: cycleID, from: startDate, to: endDate) { sample, error in
                Task { @MainActor in completion(sample, error) }
            }
        }
    }
}

/// Permission checks and Core Motion calls may involve IPC. Keep all of them off MainActor.
private actor PedometerDriver {
    enum Event: Sendable { case sample(WalkingSample), status(String) }
    private var live: CMPedometer?
    private var revision: UInt = 0
    private var refreshTask: Task<Void, Never>?
    private var lastLiveSample = Date.distantPast
    private var queryInFlight = false
    private var finalQueries: [UUID: CMPedometer] = [:]

    func start(from startDate: Date, revision: UInt, reply: @escaping @Sendable (Event) -> Void) {
        guard revision >= self.revision else { return }
        stop(revision: revision)
        guard CMPedometer.isStepCountingAvailable() else {
            reply(.status("걸음 센서 미지원 · 방향 측정은 계속됩니다.")); return
        }
        switch CMPedometer.authorizationStatus() {
        case .denied, .restricted:
            reply(.status("걸음 권한 없음 · 설정의 동작 및 피트니스에서 허용해 주세요.")); return
        default: break
        }
        let pedometer = live ?? CMPedometer()
        live = pedometer
        lastLiveSample = .distantPast
        pedometer.startUpdates(from: startDate, withHandler: PedometerFeed.makeHandler(from: startDate) { [weak self] sample, message in
            Task { await self?.deliver(sample, error: message, revision: revision, isLive: true, reply: reply) }
        })
        // Query the system's processed cache if live delivery is silent. This does not invent steps.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self else { return }
                await self.refresh(from: startDate, revision: revision, reply: reply)
            }
        }
    }

    func stop(revision: UInt) {
        guard revision >= self.revision else { return }
        self.revision = revision
        refreshTask?.cancel()
        refreshTask = nil
        queryInFlight = false
        live?.stopUpdates()
    }

    private func refresh(from start: Date, revision: UInt, reply: @escaping @Sendable (Event) -> Void) {
        guard revision == self.revision, !queryInFlight,
              Date().timeIntervalSince(lastLiveSample) >= 3,
              CMPedometer.authorizationStatus() == .authorized else { return }
        queryInFlight = true
        live?.queryPedometerData(from: start, to: Date(), withHandler: PedometerFeed.makeHandler(from: start) { [weak self] sample, message in
            Task { await self?.deliver(sample, error: message, revision: revision, isLive: false, reply: reply) }
        })
    }

    private func deliver(_ sample: WalkingSample?, error: String?, revision: UInt, isLive: Bool,
                         reply: @Sendable (Event) -> Void) {
        guard revision == self.revision else { return }
        if isLive { lastLiveSample = Date() } else { queryInFlight = false }
        if let error { reply(.status("걸음 수신 오류: \(error)")) }
        else if let sample { reply(.sample(sample)) }
    }

    func queryFinal(cycleID: UUID, from start: Date, to end: Date,
                    completion: @escaping @Sendable (WalkingSample?, String?) -> Void) {
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized,
              end > start else { completion(nil, "종료 시 수신값 · 걸음 최종 조회 불가"); return }
        let query = CMPedometer()
        finalQueries[cycleID] = query
        query.queryPedometerData(from: start, to: end, withHandler: PedometerFeed.makeHandler(from: start) { [weak self] sample, message in
            Task {
                await self?.finishQuery(cycleID: cycleID)
                completion(sample, message.map { "종료 시 수신값 · 최종 조회 오류: \($0)" })
            }
        })
    }

    private func finishQuery(cycleID: UUID) { finalQueries[cycleID] = nil }
}
