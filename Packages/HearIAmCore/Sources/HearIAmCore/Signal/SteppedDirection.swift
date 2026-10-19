import Foundation

/// Short harmonic bursts: right 40/50, aligned 60, left 70/80 Hz.
/// Positive bearing means the target is to the right of the selected body/head direction.
public struct SteppedDirectionGate: Sendable {
    public static let pitches=[40,50,60,70,80]
    public static let interval=0.9, burstLength=0.25, alignmentGap=0.08
    public static let enterDegrees=10.0, exitDegrees=16.0, steadySeconds=0.35, maximumSampleGap=0.5
    public static let bandBoundary=90.0, bandMargin=5.0, rearMargin=8.0
    public struct Update: Equatable, Sendable {
        public let stopPrevious: Bool
        public let sound: SignalSound?
    }
    public private(set) var isAligned=false
    public private(set) var currentHertz: Int?
    private var alignedSince: Double?
    private var lastTime: Double?
    private var lastPlayedAt: Double?
    private var side: Int?
    private var outer=false
    public init() {}
    public mutating func reset() { self=Self() }
    /// Keep a confirmed alignment, but never queue a confirmation or pulse across a pause.
    public mutating func suspend() { alignedSince=nil;lastTime=nil;lastPlayedAt=nil;currentHertz=nil }
    public mutating func update(time: Double, bearing: Double) -> Update {
        guard time.isFinite, bearing.isFinite,
              lastTime.map({time > $0 && time-$0 <= Self.maximumSampleGap}) ?? true else {
            reset();return Update(stopPrevious:true,sound:nil)
        }
        lastTime=time
        let wrapped=HeadingMath.wrapDegrees(bearing)
        let angle=wrapped == -180 && bearing > 0 ? 180 : wrapped, error=abs(angle)
        if isAligned && error < Self.exitDegrees {
            currentHertz=60;return Update(stopPrevious:false,sound:nil)
        }
        if isAligned { isAligned=false;alignedSince=nil;lastPlayedAt=nil }
        if error <= Self.enterDegrees {
            let entering=alignedSince == nil
            alignedSince=alignedSince ?? time;lastPlayedAt=nil;currentHertz=60
            if time-(alignedSince ?? time) >= Self.steadySeconds {
                isAligned=true;side=nil
                return Update(stopPrevious:true,sound:.directionBuzzAligned)
            }
            return Update(stopPrevious:entering,sound:nil)
        }
        alignedSince=nil
        let candidate=angle > 0 ? 1 : -1
        let nextSide=error >= 180-Self.rearMargin ? (side ?? candidate) : candidate
        let changedSide=nextSide != side
        if changedSide { outer=error > Self.bandBoundary }
        else if outer && error < Self.bandBoundary-Self.bandMargin { outer=false }
        else if !outer && error > Self.bandBoundary+Self.bandMargin { outer=true }
        let hertz=nextSide > 0 ? (outer ? 40 : 50) : (outer ? 80 : 70)
        let changedPitch=currentHertz != hertz
        side=nextSide;currentHertz=hertz
        if changedPitch || lastPlayedAt.map({time-$0 >= Self.interval}) ?? true {
            lastPlayedAt=time
            return Update(stopPrevious:changedPitch,sound:.directionBuzz(hertz:hertz))
        }
        return Update(stopPrevious:false,sound:nil)
    }
}
