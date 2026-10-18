import UIKit
import HearIAmCore

/// One log file per visit to the tab: Documents/SoundTests/trial-<UUID>.jsonl.
/// Visible in the Files app under this app, so results can be pulled off the phone.
@MainActor final class SoundTestLog {
    private var log: TrialLog?
    private var sequence=0
    private(set) var fileName: String?

    /// Returns an error message when the file cannot be created; testing still works without a log.
    func open() -> String? {
        guard log == nil else { return nil }
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        do {
            sequence=0
            let created=try TrialLog(directory:docs.appendingPathComponent("SoundTests",isDirectory:true),metadata:[
                "source":"sound-test","device":UIDevice.current.model,"os":UIDevice.current.systemVersion,
                "appVersion":Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                "route":HearAudioSession.route])
            log=created;fileName=created.url.lastPathComponent
            return nil
        } catch { return "로그 파일을 만들 수 없어요: "+error.localizedDescription }
    }
    func record(_ event: String, _ detail: String) {
        sequence+=1
        log?.append(TrialRecord(sequence:sequence,uptime:ProcessInfo.processInfo.systemUptime,event:event,detail:detail))
    }
    func close() { log?.close { _ in };log=nil }
}
