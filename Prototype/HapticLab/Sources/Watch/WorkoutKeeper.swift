import Foundation
import HealthKit
import WatchKit

/// **E5 · 백그라운드 유지 시험**
///
/// 문서끼리 말이 다른 지점을 직접 가른다.
/// - `play(_:)` 문서 : *"HealthKit 으로 심박을 재는 중에는 햅틱을 부르지 마라"*
/// - 워크아웃 세션 문서 : *"앱이 워크아웃 세션 중 **햅틱을 제공하면** Audio 백그라운드 모드도 추가하라"*
///
/// 둘 중 어느 쪽이 맞는지가 **공연 길이의 상한을 가른다.** 문서로는 못 가리므로 실기기로 잰다.
@MainActor
final class WorkoutKeeper: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var startedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var heartRateSamples = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?

    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            lastError = "이 기기에서는 HealthKit 을 쓸 수 없다"
            return
        }
        let share: Set = [HKQuantityType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func start() {
        guard !isRunning else { return }
        let config = HKWorkoutConfiguration()
        // 무대 안내는 운동이 아니다. 이 선언이 심사에서 받아들여지는지도 확인 대상이다.
        config.activityType = .other
        config.locationType = .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            self.session = session
            session.delegate = self
            session.startActivity(with: Date())
            isRunning = true
            startedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        session?.end()
        session = nil
        isRunning = false
        startedAt = nil
    }
}

extension WorkoutKeeper: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        let running = (toState == .running)
        Task { @MainActor in self.isRunning = running }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastError = message
            self.isRunning = false
        }
    }
}
