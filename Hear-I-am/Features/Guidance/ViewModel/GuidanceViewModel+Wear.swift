import Foundation
import HearIAmCore

/// 3 / 4 · 허리띠 착용: the wearer fixes the phone and presses 「착용 완료」. The 8-second countdown was removed on 10/21.
extension GuidanceViewModel {
    func finishWear() {
        guard phase == .wear, canAdvanceInstruction, tracking.ready, active else { return }
        invalidateTasks();approachNotice=nil;phase = .departure;departureGate.reset();readyAnnounced=false
        if usesPracticeEntry, !started {
            read(["현재 위치에서 출발을 준비해요. 잠시 멈춰주세요. ‘출발’이라고 말하면 출발점을 거치지 않고 P1부터 안내해요."])
            return
        }
        read(voiceShouldListen ? VoiceStepCopy.departure(started:started) : [started ? "착용 상태를 확인하고 있습니다. 안내를 중단한 동선 위에서 준비해주세요." : "착용 상태를 확인하고 있습니다. 스캔한 공간에서 출발점까지 안내 버튼을 누르면 출발점으로 안내합니다. 몸이 향한 방향을 기준으로 안내합니다."])
    }
}
