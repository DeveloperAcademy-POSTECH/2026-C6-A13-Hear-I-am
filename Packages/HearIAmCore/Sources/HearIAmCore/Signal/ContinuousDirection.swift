import Foundation

/// A stationary body/head error has one stationary pitch. No periodic sweep or pulse.
public struct ContinuousDirectionGate: Sendable {
    public static let lowHertz=400.0, centerHertz=600.0, highHertz=800.0
    public static let enterDegrees=10.0, exitDegrees=16.0, steadySeconds=0.35, maximumSampleGap=0.5
    public struct Update: Equatable, Sendable {
        public let hertz: Double?
        public let aligned: Bool
    }
    public private(set) var isAligned=false
    private var alignedSince: Double?
    private var lastTime: Double?
    private var rearSign: Double?
    public init() {}
    public mutating func reset() { self=Self() }
    public mutating func suspend() { alignedSince=nil;lastTime=nil }
    /// Negative: target on the left (below 600 Hz); positive: target on the right (above 600 Hz).
    public static func hertz(bearing: Double) -> Double? {
        guard bearing.isFinite else { return nil }
        return centerHertz+max(-180,min(180,bearing))/180*(highHertz-centerHertz)
    }
    public mutating func update(time: Double, bearing: Double) -> Update {
        guard time.isFinite, bearing.isFinite,
              lastTime.map({time > $0 && time-$0 <= Self.maximumSampleGap}) ?? true else {
            reset();return Update(hertz:nil,aligned:false)
        }
        lastTime=time
        let wrapped=HeadingMath.wrapDegrees(bearing)
        let angle=wrapped == -180 && bearing > 0 ? 180 : wrapped, error=abs(angle)
        if isAligned && error < Self.exitDegrees { return Update(hertz:nil,aligned:false) }
        if isAligned { isAligned=false;alignedSince=nil }
        if error <= Self.enterDegrees {
            alignedSince=alignedSince ?? time
            if time-(alignedSince ?? time) >= Self.steadySeconds {
                isAligned=true;rearSign=nil
                return Update(hertz:nil,aligned:true)
            }
        } else { alignedSince=nil }
        let candidate=angle > 0 ? 1.0 : -1.0
        let sign=error >= 172 ? (rearSign ?? candidate) : candidate
        rearSign=sign
        return Update(hertz:Self.hertz(bearing:sign*error),aligned:false)
    }
}

/// The audio thread owns this oscillator. Phase and pitch survive every render-buffer boundary.
public struct ContinuousSineOscillator: Sendable {
    private var phase=0.0, hertz=ContinuousDirectionGate.centerHertz, gain=0.0
    public init() {}
    public mutating func render(into output: UnsafeMutableBufferPointer<Float>, targetHertz: Double?, sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate > 0 else {
            for i in output.indices { output[i]=0 };return
        }
        let target=targetHertz.flatMap { $0.isFinite ? max(ContinuousDirectionGate.lowHertz,min(ContinuousDirectionGate.highHertz,$0)) : nil }
        // A fresh note starts at the requested pitch, rather than gliding in from the reference.
        if gain == 0, let target { hertz=target }
        let pitchShare=1-exp(-1/(sampleRate*0.06)), gainShare=1-exp(-1/(sampleRate*0.015))
        for i in output.indices {
            if let target { hertz += (target-hertz)*pitchShare }
            gain += ((target == nil ? 0.0 : 0.35)-gain)*gainShare
            if gain < 0.000001 && target == nil { gain=0 }
            output[i]=Float(sin(phase)*gain)
            phase += 2 * .pi*hertz/sampleRate
            if phase >= 2 * .pi { phase -= 2 * .pi }
        }
    }
}

/// A missed sensor/UI update cannot leave the continuous tone running indefinitely.
public struct ContinuousToneCommand: Sendable {
    public let hertz: Double?
    public let updatedAt: Double
    public init(hertz: Double?, updatedAt: Double) { self.hertz=hertz;self.updatedAt=updatedAt }
    public func activeHertz(at time: Double) -> Double? {
        guard time.isFinite, updatedAt.isFinite, time >= updatedAt,
              time-updatedAt <= ContinuousDirectionGate.maximumSampleGap else { return nil }
        return hertz.flatMap { $0.isFinite ? $0 : nil }
    }
}
