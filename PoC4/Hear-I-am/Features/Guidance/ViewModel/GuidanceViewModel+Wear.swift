import Foundation
import HearIAmCore

/// 3 / 4 · 허리띠 착용: an 8-second countdown that reads the last three seconds aloud.
extension GuidanceViewModel {
    func beginWear() {
        guard phase == .wear || phase == .countdown, tracking.ready, active else { return }
        invalidateTasks();phase = .countdown;countdown=8
        let operation=generation
        read(["지금부터 8초 동안 착용해주세요. 마지막 3초를 알려드릴게요."]) { [weak self] in
            guard let self, self.generation == operation else { return }
            self.countdownTask=Task { [weak self] in
                guard let self else { return }
                for remaining in stride(from:8,through:1,by:-1) {
                    guard !Task.isCancelled, self.generation == operation, self.active, self.tracking.ready else { return }
                    self.countdown=remaining
                    let began=ProcessInfo.processInfo.systemUptime
                    if remaining <= 3 {
                        let finished=await withCheckedContinuation { continuation in
                            self.voice.play([String(remaining)]) { continuation.resume(returning:$0) }
                        }
                        guard finished, !Task.isCancelled, self.generation == operation else { return }
                    }
                    let delay=max(0,1-(ProcessInfo.processInfo.systemUptime-began))
                    do { try await Task.sleep(nanoseconds:UInt64(delay*1_000_000_000)) } catch { return }
                }
                guard self.generation == operation, self.active, self.tracking.ready else { return }
                self.phase = .departure;self.countdownTask=nil;self.departureGate.reset();self.readyAnnounced=false
                self.read([self.started ? "착용 상태를 확인하고 있습니다. 안내를 중단한 동선 위에서 준비해주세요." : "착용 상태를 확인하고 있습니다. 지정한 출발점에서 잠시 멈춰주세요. 몸이 향한 방향을 기준으로 안내합니다."])
            }
        }
    }
}
