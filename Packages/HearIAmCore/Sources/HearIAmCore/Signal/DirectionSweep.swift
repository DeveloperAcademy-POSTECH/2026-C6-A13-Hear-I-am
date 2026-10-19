import Foundation

/// A mono pitch glide. Turn is the required body rotation, not the measured rotation.
public struct DirectionSweep: Equatable, Sendable {
    public enum Turn: String, Sendable { case left, right }
    public static let duration=0.45, interval=0.85
    public let turn: Turn
    /// Five-degree buckets bound the audio cache to 72 waveforms.
    public let extent: Int
    public init(turn: Turn, errorDegrees: Double) {
        self.turn=turn
        extent=errorDegrees.isFinite ? max(1,min(36,Int((min(180,abs(errorDegrees))/5).rounded()))) : 1
    }
    public var spanHertz: Double { 80+520*Double(extent)/36 }
    public var startHertz: Double { 900+(turn == .left ? -1 : 1)*spanHertz/2 }
    public var endHertz: Double { 900+(turn == .left ? 1 : -1)*spanHertz/2 }
}

/// Direction state for #48. Positive bearing means the target is to the right.
/// No timer is owned here: only fresh pose updates may produce a sound.
public struct DirectionSweepGate: Sendable {
    public static let enterDegrees=10.0, exitDegrees=16.0, steadySeconds=0.35
    public static let rearMarginDegrees=8.0, maximumSampleGap=0.5
    public struct Update: Equatable, Sendable {
        public let stopPrevious: Bool
        public let sound: SignalSound?
    }
    public private(set) var isAligned=false
    private var alignedSince: Double?
    private var lastTime: Double?
    private var lastSweepTime: Double?
    private var turn: DirectionSweep.Turn?
    public init() {}
    public mutating func reset() { self=Self() }
    /// Speech/warnings take precedence. Preserve the confirmation latch, but require a fresh dwell
    /// if alignment had not yet been confirmed. Never replay a queued/stale alignment afterwards.
    public mutating func suspend() { alignedSince=nil;lastTime=nil;lastSweepTime=nil }

    public mutating func update(time: Double, bearing: Double) -> Update {
        guard time.isFinite, bearing.isFinite,
              lastTime.map({time > $0 && time-$0 <= Self.maximumSampleGap}) ?? true else {
            reset();return Update(stopPrevious:true,sound:nil)
        }
        lastTime=time
        let angle=HeadingMath.wrapDegrees(bearing), error=abs(angle)
        if isAligned && error < Self.exitDegrees { return Update(stopPrevious:false,sound:nil) }
        if isAligned { isAligned=false;alignedSince=nil;lastSweepTime=nil }
        if error <= Self.enterDegrees {
            let entering=alignedSince == nil
            alignedSince=alignedSince ?? time
            lastSweepTime=nil
            if time-(alignedSince ?? time) >= Self.steadySeconds {
                isAligned=true;turn=nil
                return Update(stopPrevious:true,sound:.directionAligned)
            }
            return Update(stopPrevious:entering,sound:nil)
        }
        alignedSince=nil
        // At the rear seam retain the last instruction within 8° of 180°.
        // For an exact rear target without history choose left deterministically.
        let candidate: DirectionSweep.Turn=angle > 0 && error < 180 ? .right : .left
        let next=error >= 180-Self.rearMarginDegrees ? (turn ?? candidate) : candidate
        let changed=next != turn
        turn=next
        if changed || lastSweepTime.map({time-$0 >= DirectionSweep.interval}) ?? true {
            lastSweepTime=time
            return Update(stopPrevious:changed,sound:.directionSweep(DirectionSweep(turn:next,errorDegrees:error)))
        }
        return Update(stopPrevious:false,sound:nil)
    }
}
