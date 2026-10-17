import Foundation

/// Speaks a correction when the target stays more than 45° off the body for 1 second (decided 10/17).
/// Beyond 135° it says "뒤로 도세요". The same line is not repeated within 3 seconds.
public struct CorrectionGate: Sendable {
    public static let threshold=45.0, backThreshold=135.0, hold=1.0, repeatInterval=3.0
    private var offSince: Double?
    private var last: (correction: Correction, time: Double)?
    public init() {}
    public mutating func reset() { offSince=nil;last=nil }

    /// `bearing`: the target relative to the body, positive on the right. Returns a line to speak, or nil.
    public mutating func update(time: Double, bearing: Double) -> Correction? {
        guard time.isFinite, bearing.isFinite else { offSince=nil;return nil }
        let angle=HeadingMath.wrapDegrees(bearing)
        guard abs(angle) > Self.threshold else { offSince=nil;return nil }
        let since=offSince ?? time
        offSince=since
        guard time-since >= Self.hold else { return nil }
        let correction: Correction=abs(angle) > Self.backThreshold ? .back : angle > 0 ? .right : .left
        if let last, last.correction == correction, time-last.time < Self.repeatInterval { return nil }
        last=(correction,time)
        return correction
    }
}
