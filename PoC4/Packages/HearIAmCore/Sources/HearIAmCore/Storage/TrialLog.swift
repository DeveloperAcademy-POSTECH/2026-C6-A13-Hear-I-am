import Foundation

/// Serial queue preserves sample/event order and streams to disk without retaining a session-sized array.
public final class TrialLog {
    private let queue=DispatchQueue(label:"HearIAm.log",qos:.utility)
    private var handle: FileHandle?
    private var failure: Error?
    public let url: URL
    public init(directory: URL, metadata: [String:String]) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        url=directory.appendingPathComponent("trial-"+UUID().uuidString+".jsonl")
        let data=try JSONSerialization.data(withJSONObject:["event":"header","metadata":metadata],options:.sortedKeys)
        try (data+Data([10])).write(to:url,options:.atomic)
        handle=try FileHandle(forWritingTo:url); try handle?.seekToEnd()
    }
    public func append(_ record: TrialRecord) {
        queue.async { [self] in
            guard failure==nil, let handle else { return }
            do {
                let encoder=JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
                try handle.write(contentsOf:encoder.encode(record)+Data([10]))
            } catch { failure=error }
        }
    }
    public func checkFailure(_ callback: @escaping (String?) -> Void) {
        queue.async { [self] in callback(failure?.localizedDescription) }
    }
    public func close(_ completion: @escaping (Result<URL,Error>) -> Void) {
        queue.async { [self] in
            do {
                try handle?.synchronize(); try handle?.close(); handle=nil
                if let failure { throw failure }
                completion(.success(url))
            } catch { handle=nil; completion(.failure(error)) }
        }
    }
    deinit { try? handle?.close() }
}
