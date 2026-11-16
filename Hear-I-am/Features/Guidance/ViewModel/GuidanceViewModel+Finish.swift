import Foundation
import HearIAmCore

/// 안내 완료: the final announcement, then saving one completion record.
extension GuidanceViewModel {
    static let dingBeforeSpeech=0.7
    func playCompletion() {
        guard phase != .finishing || !speaking else { return }
        let arriving=phase == .guiding
        captureReplay(force:true)
        if let guide { run?.arrive(guide:guide,at:Date(),uptime:ProcessInfo.processInfo.systemUptime) }
        // The completion record is saved separately; without this line the trial log never said the run finished (10/17).
        tracking.event("guidance_completed",detail:"points=\(guide?.route.points.count ?? 0)")
        invalidateTasks()
        // The last point dings like every other one (10/19); replaying the closing line does not.
        if arriving, let guide {
            signals.play(.arrival);logSignal("signal_arrival","\(GuidanceCopy.target(guide.targetIndex,last:guide.route.points.count-1)) final")
        }
        phase = .finishing;cue=nil
        // Guidance stops now; the validation camera stays live until the user finishes.
        // Let the ding ring out before the closing line covers it.
        readCompletion(after:arriving ? Self.dingBeforeSpeech : 0)
    }
    /// The closing line; heard to the end, guidance is complete and the record is saved. Cut off by leaving the app,
    /// a call or the audio route, it is said again on coming back or on Back: before, the run stayed 「finishing」
    /// with no way out and no record (#179).
    func readCompletion(after delay: Double = 0) {
        guard phase == .finishing else { return }
        audioIssue=nil;message=L("종료 안내를 읽고 있어요.")
        let operation=generation
        let speak={ [weak self] in
            guard let self, self.generation == operation, self.active else { return }
            self.voice.play([GuidanceCopy.completed],final:true) { [weak self] finished in
                guard let self, finished, self.generation == operation, self.active else { return }
                self.phase = .completed;self.instructionDone=true;self.message=GuidanceCopy.completed
            }
        }
        if delay > 0 {
            Task { @MainActor in try? await Task.sleep(nanoseconds:UInt64(delay*1e9));speak() }
        } else { speak() }
    }
    func completedRecord() throws -> GuidanceRecord {
        guard phase == .completed, guide?.state == .completed, let run else {
            throw LabError.invalid(L("마지막 도착 안내가 끝난 후 종료해주세요."))
        }
        if let pendingRecord { return pendingRecord }
        // The names it is filed under now stay with the record (#179).
        let record=try run.record(completionSpoken:true,finishedAt:Date(),performanceName:selected.flatMap {voiceCatalog.folder(for:$0.id)?.name} ?? "",
                                  venueName:selected.flatMap {voiceCatalog.venue(for:$0.id)?.name} ?? "")
        pendingRecord=record;return record
    }
    /// Saves the completion record once, then calls `onSaved`. Failures stay in `saveError`.
    /// The busy flag is set before returning so a second tap is ignored immediately.
    func saveRecord(to library: StageLibrary, onSaved: @escaping () -> Void) {
        guard !savingRecord else {return}
        savingRecord=true;saveError=nil
        Task {
            defer {savingRecord=false}
            do {
                let record=try completedRecord()
                try await library.saveGuidanceRecord(record)
                onSaved()
            } catch {
                saveError=L("기록을 저장하지 못했어요. 다시 시도해주세요. %@", error.localizedDescription)
                // The voice walking screen has no buttons at the end; its back button saves again and closes.
                if voiceExperiment, !helperPreparation {read([L("안내 기록을 저장하지 못했어요. 도와주시는 분이 왼쪽 위 뒤로 버튼을 누르면 다시 저장하고 처음 화면으로 돌아가요.")])}
                else if voiceExperiment {read([L("안내 기록을 저장하지 못했어요. 도와주시는 분이 화면 아래 기록 저장 다시 시도를 눌러주세요.")])}
            }
        }
    }
    /// Voice guidance ends without a button (Figma 22): the record saves itself as soon as the closing
    /// line is heard, the app says so, and the screen closes. On a failure the back button saves again.
    func saveRecordByVoice(to library: StageLibrary, close: @escaping () -> Void) {
        guard voiceExperiment, phase == .completed, pendingRecord == nil else {return}
        saveRecord(to:library) { [weak self] in
            guard let self else {return}
            logSignal("record_saved","voice")
            read([L("안내 기록을 저장했어요. 처음 화면으로 돌아갈게요.")]) {close()}
        }
    }
    /// Stops the session, timers and audio. Called once when the screen closes.
    func finish() {
        #if DEBUG
        if VoiceTestInbox.shared.guidance === self {VoiceTestInbox.shared.guidance=nil}
        #endif
        active=false;stopVoiceExperiment();invalidateTasks();timer?.invalidate();timer=nil
        observations.forEach {NotificationCenter.default.removeObserver($0)};observations=[]
        tracking.endSession();signals.shutdown();voice.deactivate()
    }
}
