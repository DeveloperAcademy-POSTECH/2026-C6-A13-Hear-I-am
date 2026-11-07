import Foundation
import OSLog
import HearIAmCore

/// Only app-owned diagnostic logs expire. Scans, photos, routes and user records are untouched.
/// iOS cannot run this while the app is terminated; startup and foreground entry catch up then.
enum DiagnosticLogMaintenance {
    private static let queue=DispatchQueue(label:"HearIAm.log-retention",qos:.utility)
    private static let logger=Logger(subsystem:"org.heariam.poc4.scanlab",category:"LogRetention")
    private static var timer: DispatchSourceTimer?
    private static var lastRun: Date?
    private static let interval: TimeInterval=60*60

    static func start() {
        queue.async {
            guard timer == nil else {return}
            let source=DispatchSource.makeTimerSource(queue:queue)
            source.schedule(deadline:.now(),repeating:interval,leeway:.seconds(30))
            source.setEventHandler {runIfNeeded(force:false)}
            timer=source
            source.resume()
        }
    }

    /// Voice writes request a throttled check; returning to the foreground always checks immediately.
    static func schedule(force: Bool = false) {
        queue.async {runIfNeeded(force:force)}
    }

    private static func runIfNeeded(force: Bool) {
        let now=Date()
        if !force,let previous=lastRun {
            let elapsed=now.timeIntervalSince(previous)
            if elapsed >= 0 && elapsed < interval {return}
        }
        guard let documents=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else {return}
        let result=DiagnosticLogRetention.prune(documents:documents,now:now)
        // Keep diagnostic contents and paths out of system logs. A failure retries on the next pass.
        if result.failureCount > 0 {
            logger.error("Diagnostic retention failed for \(result.failureCount) item(s); will retry.")
        }
        lastRun=now
    }
}
