import Foundation

/// Platform-independent sequencing. Late finish callbacks can never finish a replacement message.
public struct NarrationQueue: Sendable {
    public struct Line: Equatable, Sendable {
        public let id: UUID
        public let text: String
    }
    public private(set) var current: Line?
    private var pending: [Line] = []
    public private(set) var protectsCompletion=false
    public init() {}
    @discardableResult public mutating func replace(_ texts: [String], completion: Bool = false) -> Line? {
        guard !protectsCompletion else { return nil }
        pending=texts.filter { !$0.isEmpty }.map { Line(id:UUID(),text:$0) }
        current=pending.isEmpty ? nil : pending.removeFirst()
        protectsCompletion=completion && current != nil
        return current
    }
    @discardableResult public mutating func offerDirection(_ text: String) -> Line? {
        guard current == nil else { return nil }
        return replace([text])
    }
    /// Returns false for a canceled/old utterance. True means this line actually finished.
    @discardableResult public mutating func finish(_ id: UUID) -> Bool {
        guard current?.id == id else { return false }
        current=pending.isEmpty ? nil : pending.removeFirst()
        if current == nil { protectsCompletion=false }
        return true
    }
    public mutating func cancel() { current=nil; pending=[]; protectsCompletion=false }
}
