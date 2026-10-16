import UIKit
import PoC4Core

/// Writes one experiment log (Documents/Trials/trial-<UUID>.jsonl) per AR session.
@MainActor
final class TrialLogger {
    /// Tracking state stamped onto every event at the moment it is recorded.
    struct Context { let tracking: String; let verified: Bool; let mapping: String }

    let directory: URL
    private var log: TrialLog?
    private var sequence=0
    var isOpen: Bool { log != nil }

    init(directory: URL) { self.directory=directory }

    /// Returns an error message when the file cannot be created; the caller must not start the session.
    func begin(metadata: [String:String]) -> String? {
        do {
            sequence=0
            log=try TrialLog(directory:directory,metadata:metadata)
            return nil
        } catch { log=nil; return "로그를 만들 수 없습니다: "+error.localizedDescription }
    }
    func record(_ name: String, detail: String="", position: Point3?=nil, heading: Double?=nil,
                error: Double?=nil, time: Double, context: Context) {
        sequence+=1
        log?.append(TrialRecord(sequence:sequence,uptime:time,event:name,detail:detail,
            position:position,heading:heading,tracking:context.tracking,
            verified:context.verified,errorMeters:error,
            coordinateSpace:(name.hasPrefix("reference_") || name.hasPrefix("corner_") || name=="route_point" || name=="checkpoint") ? "ar-world" : "stage",
            mapping:context.mapping))
    }
    func checkFailure(_ callback: @escaping (String?) -> Void) { log?.checkFailure(callback) }
    /// Closes the file. `onFailure` receives a message when the final flush fails.
    func close(onFailure: @escaping @MainActor (String) -> Void) {
        guard let logger=log else { return }
        log=nil
        logger.close { result in
            Task { @MainActor in
                if case .failure(let error)=result { onFailure("로그 마무리 실패: "+error.localizedDescription) }
            }
        }
    }
}
