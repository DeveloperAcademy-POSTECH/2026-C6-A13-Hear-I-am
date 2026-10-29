import Foundation
import HearIAmCore

/// 3 / 4 · 허리띠 착용: the wearer fixes the phone and presses 「착용 완료」. The 8-second countdown was removed on 10/21.
extension GuidanceViewModel {
    func finishWear() {
        guard phase == .wear, canAdvanceInstruction, tracking.ready, active else { return }
        invalidateTasks();phase = .departure;departureGate.reset();readyAnnounced=false
        read(voiceShouldListen ? VoiceStepCopy.departure(started:started) : [started ? "착용 상태를 확인하고 있습니다. 안내를 중단한 동선 위에서 준비해주세요." : "착용 상태를 확인하고 있습니다. 지정한 출발점에서 잠시 멈춰주세요. 몸이 향한 방향을 기준으로 안내합니다."])
    }
}
