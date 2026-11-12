import HearIAmCore

/// 2 / 4 · 현장 확인: restoring the saved space, then verifying the checkpoint.
extension GuidanceViewModel {
    var canVerify: Bool { phase == .checkpoint && canAdvanceInstruction && tracking.canVerify }

    func restore(voiceIntroduction: String? = nil) {
        guard let selected, active, !tracking.busy, phase != .selection || canAdvanceInstruction else { return }
        clearTrackingRecovery()
        invalidateTasks();departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        performanceCheckpointsDone=false
        tracking.endSession();tracking.setActive(true);tracking.errorMessage=nil
        message=L("저장한 공연장 위치를 확인하고 있어요.")
        phase = .restoring
        let instruction=isPractice ? L("저장한 실제 공간 안에서 휴대폰을 손에 들고 제자리에서 천천히 한 바퀴 돌아주세요. 공간을 찾으면 알려드릴게요.") : L("조력자가 휴대폰을 들고 저장한 공연장 주변을 천천히 비춰주세요. 공간을 찾은 뒤 확인점 두 개를 맞춥니다.")
        read((voiceIntroduction.map {[$0]} ?? [])+[instruction])
        tracking.restore(selected,validation:isPractice ? .relocalization : .checkpoints)
    }
    func verifyCheckpoint() {
        guard canVerify else { return }
        invalidateTasks()
        tracking.errorMessage=nil;tracking.verifyCheckpoint()
        if tracking.ready, voicePerformanceFlow {
            // The helper confirms with 「완료」 on the same screen (Figma 1028:18968).
            performanceCheckpointsDone=true;message=L("두 확인점 기준으로 위치와 방향을 보정했습니다.")
            read(VoiceStepCopy.performanceCheckpointsDone)
        } else if tracking.ready {
            phase = .wear;message=L("두 확인점 기준으로 위치와 방향을 보정했습니다.")
            read(voiceShouldListen ? VoiceStepCopy.wear : [L("두 확인점 보정을 완료했습니다."),GuidanceCopy.doNotDisturb,L("휴대폰을 허리 앞쪽에 세로로 고정해주세요. 후면 카메라는 몸 바깥쪽을 향하고 렌즈는 가리지 말아주세요.")])
        } else if tracking.measuredCheckpoints.count == 1 {
            message=L("확인점 1번을 측정했습니다. 저장한 확인점 2번에 조준점을 맞춰주세요.")
            read(voicePerformanceFlow ? VoiceStepCopy.performanceCheckpoint(2) : voiceShouldListen ? VoiceStepCopy.checkpoint(2) : [message])
        } else {
            message=tracking.errorMessage ?? L("저장된 확인점과 위치가 맞지 않아요.")
            read([L("%@ 확인점 1번부터 다시 비춰주세요.", message)])
        }
    }
    func tickRestoring() {
        guard !voiceTurnActive else {return}
        if let error=tracking.errorMessage { fail(error);return }
        if !tracking.busy && tracking.mode == .idle { fail(tracking.status);return }
        if isPractice, tracking.ready, canAdvanceInstruction {
            invalidateTasks();phase = .wear
            message=L("저장한 공간을 찾았어요. 확인점 보정 없이 연습을 시작해요.")
            // Said in one breath before (11/09–10): 방해 금지 once per app run, the wearing in one sentence.
            // 「다시 말해줘」 still gives the whole wearing instruction (replay).
            let doNotDisturb=Self.doNotDisturbSaid ? [] : [L("방해 금지 모드를 켜주세요.")]
            Self.doNotDisturbSaid=true
            read([L("공연장을 찾았어요.")]+doNotDisturb+[L("휴대폰을 허리 앞에 세로로 차고, 다 차면 ‘착용 완료’라고 말해주세요.")])
            return
        }
        if tracking.canVerify, canAdvanceInstruction {
            invalidateTasks()
            phase = .checkpoint;message=L("중앙 조준점을 저장한 확인점 1번에 맞춰주세요.")
            read(voicePerformanceFlow ? VoiceStepCopy.performanceCheckpoint(1) : voiceShouldListen ? VoiceStepCopy.checkpoint(1) : [L("공연장을 찾았습니다. 저장한 확인점 1번에 조준점을 맞추고 눌러주세요.")])
        }
    }
    func tickCheckpoint() {
        if tracking.mode == .idle { fail(tracking.status); return }
        if voicePerformanceFlow {
            // On within 50 cm, off past 80 cm, so the button does not flicker at the edge.
            let distance=tracking.canVerify && !performanceCheckpointsDone ? tracking.nextCheckpointAimDistance() : nil
            let aimed=distance.map {$0 <= (checkpointAimed ? 0.8 : 0.5)} ?? false
            if aimed != checkpointAimed {checkpointAimed=aimed}
        }
        if performanceCheckpointsDone, !tracking.ready {
            performanceCheckpointsDone=false;message=L("추적이 변경됐어요. 확인점 1번부터 다시 확인해주세요.")
            read([message]);return
        }
        if tracking.measuredCheckpoints.isEmpty && message == L("확인점 1번을 측정했습니다. 저장한 확인점 2번에 조준점을 맞춰주세요.") {
            message=L("추적이 변경됐어요. 확인점 1번부터 다시 확인해주세요.")
            read([message])
        }
    }
    func fail(_ error: String) {
        phase = .failed;message=error;tracking.endSession()
        read([voiceShouldListen ? VoiceStepCopy.failed(error) : L("공연장을 확인하지 못했습니다. %@ 다시 시도해주세요.", error)])
    }
}
