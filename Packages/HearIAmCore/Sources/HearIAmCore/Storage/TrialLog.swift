import Foundation

/// Serial queue preserves sample/event order and streams to disk without retaining a session-sized array.
public final class TrialLog {
    private let queue=DispatchQueue(label:"HearIAm.log",qos:.utility)
    private var handle: FileHandle?
    private var failure: Error?
    public let url: URL
    public init(directory: URL, metadata: [String:String]) throws {
        let created=directory.appendingPathComponent("trial-"+UUID().uuidString+".jsonl")
        url=created
        handle=try DiagnosticLogRetention.withFileAccess {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            let clock=ISO8601DateFormatter()
            clock.formatOptions=[.withInternetDateTime,.withFractionalSeconds]
            let data=try JSONSerialization.data(withJSONObject:["event":"header","time":clock.string(from:Date()),"metadata":metadata],options:.sortedKeys)
            try (data+Data([10])).write(to:created,options:.atomic)
            let opened=try FileHandle(forWritingTo:created)
            do {try opened.seekToEnd()} catch {try? opened.close();throw error}
            DiagnosticLogRetention.registerActive(created)
            return opened
        }
    }
    public func append(_ record: TrialRecord) {
        queue.async { [self] in
            DiagnosticLogRetention.withFileAccess {
                guard failure==nil, let handle else { return }
                do {
                    let encoder=JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                    try handle.write(contentsOf:encoder.encode(record)+Data([10]))
                } catch { failure=error }
            }
        }
    }
    public func checkFailure(_ callback: @escaping (String?) -> Void) {
        queue.async { [self] in callback(failure?.localizedDescription) }
    }
    public func close(_ completion: @escaping (Result<URL,Error>) -> Void) {
        queue.async { [self] in
            let result: Result<URL,Error> = DiagnosticLogRetention.withFileAccess {
                defer {handle=nil;DiagnosticLogRetention.unregisterActive(url)}
                do {
                    do {try handle?.synchronize()} catch {try? handle?.close();throw error}
                    try handle?.close()
                    if let failure {throw failure}
                    return .success(url)
                } catch {return .failure(error)}
            }
            DiagnosticLogRetention.pruneAfterClosing(url)
            completion(result)
        }
    }
    deinit {
        let needsCleanup=DiagnosticLogRetention.withFileAccess {
            let wasOpen=handle != nil
            try? handle?.close()
            DiagnosticLogRetention.unregisterActive(url)
            return wasOpen
        }
        if needsCleanup {
            let closedURL=url
            DispatchQueue.global(qos:.utility).async {DiagnosticLogRetention.pruneAfterClosing(closedURL)}
        }
    }
}
