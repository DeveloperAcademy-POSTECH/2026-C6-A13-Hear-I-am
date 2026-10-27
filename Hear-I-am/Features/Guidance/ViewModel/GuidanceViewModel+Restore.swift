import HearIAmCore

/// 2 / 4 · 현장 확인: restoring the saved space, then verifying the checkpoint.
extension GuidanceViewModel {
    var canVerify: Bool { phase == .checkpoint && canAdvanceInstruction && tracking.canVerify }

    func restore(voiceIntroduction: String? = nil) {
        guard let selected, active, !tracking.busy, phase != .selection || canAdvanceInstruction else { return }
        invalidateTasks();departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        tracking.endSession();tracking.setActive(true);tracking.errorMessage=nil
        message="저장한 공연장 위치를 확인하고 있어요."
        phase = .restoring
        read((voiceIntroduction.map {[$0]} ?? [])+["휴대폰을 손에 들고 주변을 천천히 비춰주세요."])
        tracking.restore(selected)
    }
    func verifyCheckpoint() {
        guard canVerify else { return }
        invalidateTasks()
        tracking.errorMessage=nil;tracking.verifyCheckpoint()
        if tracking.ready {
            phase = .wear;message="두 확인점 기준으로 위치와 방향을 보정했습니다."
            read(["두 확인점 보정을 완료했습니다.",GuidanceCopy.doNotDisturb,"휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요."])
        } else if tracking.measuredCheckpoints.count == 1 {
            message="확인점 1번을 측정했습니다. 저장한 확인점 2번에 조준점을 맞춰주세요."
            read([message])
        } else {
            message=tracking.errorMessage ?? "저장된 확인점과 위치가 맞지 않아요."
            read(["\(message) 확인점 1번부터 다시 비춰주세요."])
        }
    }
    func tickRestoring() {
        guard !voiceTurnActive else {return}
        if let error=tracking.errorMessage { fail(error);return }
        if !tracking.busy && tracking.mode == .idle { fail(tracking.status);return }
        if tracking.canVerify, canAdvanceInstruction {
            invalidateTasks()
            phase = .checkpoint;message="중앙 조준점을 저장한 확인점 1번에 맞춰주세요."
            read(["공연장을 찾았습니다. 저장한 확인점 1번에 조준점을 맞추고 눌러주세요."])
        }
    }
    func tickCheckpoint() {
        if tracking.mode == .idle { fail(tracking.status); return }
        if tracking.measuredCheckpoints.isEmpty && message.hasPrefix("확인점 1번을 측정했습니다.") {
            message="추적이 변경됐어요. 확인점 1번부터 다시 확인해주세요."
            read([message])
        }
    }
    func fail(_ error: String) {
        phase = .failed;message=error;tracking.endSession()
        read(["공연장을 확인하지 못했습니다. \(error) 다시 시도해주세요."])
    }
}
