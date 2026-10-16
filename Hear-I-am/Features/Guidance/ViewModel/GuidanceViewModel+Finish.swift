import Foundation
import HearIAmCore

/// 안내 완료: the final announcement, then saving one completion record.
extension GuidanceViewModel {
    func playCompletion() {
        guard phase != .finishing || !speaking else { return }
        if let guide { run?.arrive(guide:guide,at:Date(),uptime:ProcessInfo.processInfo.systemUptime) }
        invalidateTasks();phase = .finishing;cue=nil;message="종료 안내를 읽고 있어요."
        // Guidance stops now; the validation camera stays live until the user finishes.
        audioIssue=nil
        let operation=generation
        voice.play([GuidanceCopy.completed],final:true) { [weak self] finished in
            guard let self, finished, self.generation == operation, self.active else { return }
            self.phase = .completed;self.instructionDone=true;self.message="출발부터 마지막 지점까지 안내를 완료했어요."
        }
    }
    func completedRecord() throws -> GuidanceRecord {
        guard phase == .completed, guide?.state == .completed, let run else {
            throw LabError.invalid("마지막 도착 안내가 끝난 후 종료해주세요.")
        }
        if let pendingRecord { return pendingRecord }
        let record=try run.record(completionSpoken:true,finishedAt:Date())
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
            } catch {saveError="기록을 저장하지 못했어요. 다시 시도해주세요. \(error.localizedDescription)"}
        }
    }
    /// Stops the session, timers and audio. Called once when the screen closes.
    func finish() {
        active=false;invalidateTasks();timer?.invalidate();timer=nil
        observations.forEach {NotificationCenter.default.removeObserver($0)};observations=[]
        tracking.endSession();voice.deactivate()
    }
}
