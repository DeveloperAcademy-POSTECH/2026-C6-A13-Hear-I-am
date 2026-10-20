import Foundation

/// Test-only mono beeps: pitch gives the turn side, count gives angular error.
/// A group finishes before its count can change. No missed groups are queued.
public struct CountedDirectionGate: Sendable {
    public static let leftHertz=1200.0, rightHertz=600.0
    public static let interval=1.2, beepLength=0.12, beepGap=0.12
    public static let enterDegrees=10.0, exitDegrees=16.0, steadySeconds=0.35
    public static let maximumSampleGap=0.5, rearMargin=8.0
    public struct Update: Equatable, Sendable {
        public let stopPrevious: Bool
        public let sound: SignalSound?
    }
    public private(set) var isAligned=false
    public private(set) var count: Int?
    public private(set) var toRight: Bool?
    private var alignedSince: Double?
    private var lastTime: Double?
    private var lastPlayedAt: Double?
    public init() {}
    public mutating func reset() { self=Self() }
    /// Do not carry pending dwell or queued groups through speech or stale sensors.
    public mutating func suspend() {
        alignedSince=nil;lastTime=nil;lastPlayedAt=nil;count=nil;toRight=nil
    }
    public mutating func update(time: Double, bearing: Double) -> Update {
        guard time.isFinite, bearing.isFinite,
              lastTime.map({time > $0 && time-$0 <= Self.maximumSampleGap}) ?? true else {
            suspend();return Update(stopPrevious:true,sound:nil)
        }
        lastTime=time
        let wrapped=HeadingMath.wrapDegrees(bearing)
        let angle=wrapped == -180 && bearing > 0 ? 180 : wrapped, error=abs(angle)
        if isAligned && error < Self.exitDegrees {
            return Update(stopPrevious:false,sound:nil)
        }
        if isAligned { isAligned=false;alignedSince=nil;lastPlayedAt=nil }
        if error <= Self.enterDegrees {
            let entering=alignedSince == nil
            alignedSince=alignedSince ?? time;count=nil;lastPlayedAt=nil
            if time-(alignedSince ?? time) >= Self.steadySeconds {
                isAligned=true;toRight=nil
                return Update(stopPrevious:true,sound:.countDirectionAligned)
            }
            return Update(stopPrevious:entering,sound:nil)
        }
        alignedSince=nil
        let nextSide=error >= 180-Self.rearMargin ? (toRight ?? (angle > 0)) : angle > 0
        let changedSide=toRight != nil && nextSide != toRight
        toRight=nextSide;count=error > 90 ? 3 : error > 30 ? 2 : 1
        if changedSide || lastPlayedAt.map({time-$0 >= Self.interval}) ?? true {
            lastPlayedAt=time
            return Update(stopPrevious:true,sound:.countDirection(toRight:nextSide,count:count!))
        }
        return Update(stopPrevious:false,sound:nil)
    }
}
