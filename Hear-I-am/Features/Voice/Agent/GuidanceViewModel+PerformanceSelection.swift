import Foundation
import HearIAmCore

extension GuidanceViewModel {
    var showsVoicePerformances:Bool {voicePerformanceID == nil && !voiceChoosingMode && !helperPreparation}
    var voicePerformanceChoices:[PerformanceVoiceChoice] {
        let ids=voiceSearchIDs ?? voiceStages.map(\.id)
        return PerformanceVoiceMenu.choices(catalog:voiceCatalog,stageIDs:ids)
    }
    var voiceSelectionNames:[String] {
        showsVoicePerformances ? voicePerformanceChoices.map(\.name) : visibleVoiceStages.map {voiceStageTitle($0)}
    }
    var voiceSelectedPerformanceName:String? {
        if voicePerformanceID == PerformanceVoiceMenu.unassignedID {return "미분류 무대"}
        return voiceCatalog.performances.first {$0.id == voicePerformanceID}?.name
    }
    func voiceStageTitle(_ item:ScanManifest)->String {
        [voiceCatalog.venue(for:item.id)?.name,item.name].compactMap {$0}.joined(separator:" · ")
    }
    func selectVoicePerformance(_ id:UUID) {
        guard phase == .selection,!voiceChoosingMode,voicePerformanceChoices.contains(where:{$0.id == id}) else {return}
        prepareForVoiceTouch()
        selected=nil;guide=nil;run=nil;pendingRecord=nil
        voicePerformanceID=id
        voiceSelectionControlsVisible=false
        // One saved stage needs no 「어느 무대?」 question (11/02 test): it is taken straight away.
        if visibleVoiceStages.count == 1, let only=visibleVoiceStages.first {select(only);return}
        announceVoiceStageResults()
    }
    func selectVisibleVoiceItem(_ number:Int) {
        if showsVoicePerformances {
            guard voicePerformanceChoices.indices.contains(number-1) else {read(["화면에 있는 공연 번호를 말씀해주세요."]);return}
            selectVoicePerformance(voicePerformanceChoices[number-1].id)
        } else {
            guard visibleVoiceStages.indices.contains(number-1) else {read(["화면에 있는 무대 번호를 말씀해주세요."]);return}
            select(visibleVoiceStages[number-1])
        }
    }
    /// Whether the words pick one item of the list on screen, by its name, its place or its number (#156).
    func voiceHeardChoice(_ text:String) -> Bool {
        guard phase == .selection, !voiceChoosingMode else {return false}
        if showsVoicePerformances {return VoiceEcho.isChoice(text,names:voicePerformanceChoices.map(\.name))}
        let candidates=voicePerformanceID == nil ? voiceStages : visibleVoiceStages
        return VoiceEcho.isChoice(text,names:candidates.map(\.name),
                                  contexts:candidates.map {(voiceStagePaths[$0.id] ?? [])+[voiceStageTitle($0)]})
    }
}

/// 실전용 by voice (#167). The space is found as in 연습용; the helper then aims at the two checkpoints on the
/// camera screen (Figma 1028:18949 · 18930 · 18968) and taps 「완료」. From there the walking screen waits
/// (1028:18921) with the microphone closed, and guidance starts by itself once the performer holds the start.
extension GuidanceViewModel {
    /// The performer's own voice flow in 실전용, as opposed to the helper's preparation opened from a performance.
    var voicePerformanceFlow: Bool {voiceExperiment && !helperPreparation && voiceMode == .performance}
    /// After 「완료」: the waiting walking screen stands in for the wear and departure steps.
    var performanceWaiting: Bool {voicePerformanceFlow && [.wear,.departure].contains(phase)}

    /// A tap on the camera screen measures the checkpoint under the crosshair.
    func capturePerformanceCheckpoint() {
        guard voicePerformanceFlow, phase == .checkpoint, !performanceCheckpointsDone else {return}
        prepareForVoiceTouch()
        guard canVerify else {
            read([tracking.canVerify ? "확인점을 아직 확인할 수 없어요." : "위치 추적이 안정될 때까지 잠시 기다려주세요."]);return
        }
        verifyCheckpoint()
    }
    /// 「완료」: the wear step folds into the wait, so the departure gate starts counting at once.
    func confirmPerformanceCheckpoints() {
        guard voicePerformanceFlow, phase == .checkpoint, performanceCheckpointsDone, tracking.ready, canAdvanceInstruction else {return}
        prepareForVoiceTouch()
        invalidateTasks();approachNotice=nil
        voicePerformanceInputClosed=true
        voiceRecognition.discardPendingSpeech();voiceTurnActive=false
        performanceCheckpointsDone=false
        phase = .departure;departureReady=false;departureGate.reset();readyAnnounced=false;lastPoseTime=nil
        logSignal("voice_performance_confirmed","checkpoints=2")
        read(VoiceStepCopy.performanceWaiting)
    }
}
