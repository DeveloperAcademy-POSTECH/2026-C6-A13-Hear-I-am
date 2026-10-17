import HearIAmCore

/// 2 / 4 · 현장 확인: restoring the saved space, then verifying the checkpoint.
extension GuidanceViewModel {
    /// The button works as soon as tracking allows; tapping cuts any instruction still playing.
    var canVerify: Bool { phase == .checkpoint && tracking.canVerify }

    func restore() {
        guard let selected, active, !tracking.busy else { return }
        invalidateTasks();departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        tracking.endSession();tracking.setActive(true);tracking.errorMessage=nil
        message="저장한 공연장 위치를 확인하고 있어요."
        phase = .restoring
        read(["휴대폰을 손에 들고 주변을 천천히 비춰주세요."])
        tracking.restore(selected)
    }
    func verifyCheckpoint() {
        guard canVerify else { return }
        tracking.errorMessage=nil;tracking.verifyCheckpoint()
        if tracking.ready {
            phase = .wear;message="확인점이 일치합니다."
            read(["확인점이 일치합니다.","휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요."])
        } else {
            message=tracking.errorMessage ?? "저장된 확인점과 위치가 맞지 않아요."
            read(["\(message) 확인점을 다시 비춰주세요."])
        }
    }
    func tickRestoring() {
        if let error=tracking.errorMessage { fail(error);return }
        if !tracking.busy && tracking.mode == .idle { fail(tracking.status);return }
        // Move on as soon as the space is found; the new line replaces the one still playing.
        if tracking.canVerify {
            phase = .checkpoint;message="중앙 조준점을 저장한 확인점에 맞춰주세요."
            read(["공연장을 찾았습니다. 확인점에 조준점을 맞추고 눌러주세요."])
        }
    }
    func tickCheckpoint() {
        if tracking.mode == .idle { fail(tracking.status) }
    }
    func fail(_ error: String) {
        phase = .failed;message=error;tracking.endSession()
        read(["공연장을 확인하지 못했습니다. \(error) 다시 시도해주세요."])
    }
}
