import Foundation

/// A single quiet note follows the target angle; no cadence, pulse envelope or audio-clip restart.
public struct ContinuousDirectionGate: Sendable {
    public enum Resolution: String, CaseIterable, Hashable, Sendable { case smooth, tenHertz }
    public static let lowHertz=40.0, centerHertz=60.0, highHertz=80.0
    public static let enterDegrees=10.0, exitDegrees=16.0, steadySeconds=0.35, maximumSampleGap=0.5
    public var resolution: Resolution
    public struct Update: Equatable, Sendable {
        public let hertz: Double?
        public let aligned: Bool
    }
    public private(set) var isAligned=false
    private var alignedSince: Double?
    private var lastTime: Double?
    private var rearSign: Double?
    public init(resolution: Resolution = .smooth) { self.resolution=resolution }
    public mutating func reset() { self=Self(resolution:resolution) }
    public mutating func suspend() { alignedSince=nil;lastTime=nil }
    /// Negative target bearing: turn left, falling from 80 toward 60 Hz as the error shrinks.
    public static func hertz(bearing: Double, resolution: Resolution = .smooth) -> Double? {
        guard bearing.isFinite else { return nil }
        let angle=max(-180,min(180,bearing))
        if abs(angle) <= enterDegrees { return centerHertz }
        if resolution == .tenHertz {
            return angle > 0 ? (abs(angle) > 90 ? 40 : 50) : (abs(angle) > 90 ? 80 : 70)
        }
        return centerHertz-angle/180*20
    }
    public mutating func update(time: Double, bearing: Double) -> Update {
        guard time.isFinite, bearing.isFinite,
              lastTime.map({time > $0 && time-$0 <= Self.maximumSampleGap}) ?? true else {
            reset();return Update(hertz:nil,aligned:false)
        }
        lastTime=time
        let wrapped=HeadingMath.wrapDegrees(bearing)
        let angle=wrapped == -180 && bearing > 0 ? 180 : wrapped, error=abs(angle)
        if isAligned && error < Self.exitDegrees { return Update(hertz:60,aligned:false) }
        if isAligned { isAligned=false;alignedSince=nil }
        if error <= Self.enterDegrees {
            alignedSince=alignedSince ?? time
            if time-(alignedSince ?? time) >= Self.steadySeconds {
                isAligned=true;rearSign=nil
                return Update(hertz:60,aligned:true)
            }
        } else { alignedSince=nil }
        let candidate=angle > 0 ? 1.0 : -1.0
        let sign=error >= 172 ? (rearSign ?? candidate) : candidate
        rearSign=sign
        return Update(hertz:Self.hertz(bearing:sign*error,resolution:resolution),aligned:false)
    }
}

/// The audio thread owns phase, pitch and gain. One continuous harmonic waveform, no 12 Hz tremolo.
public struct ContinuousHarmonicOscillator: Sendable {
    private var phase=0.0, hertz=60.0, gain=0.0
    public init() {}
    public mutating func render(into output: UnsafeMutableBufferPointer<Float>, targetHertz: Double?, volume: Double=0.12, sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate > 0 else { for i in output.indices { output[i]=0 };return }
        let target=targetHertz.flatMap {$0.isFinite ? max(40,min(80,$0)) : nil}
        let targetGain=target == nil || !volume.isFinite ? 0 : max(0,min(0.3,volume))
        if gain == 0, let target { hertz=target }
        let pitchShare=1-exp(-1/(sampleRate*0.08)), gainShare=1-exp(-1/(sampleRate*0.015))
        for i in output.indices {
            if let target { hertz += (target-hertz)*pitchShare }
            gain += (targetGain-gain)*gainShare
            if gain < 0.000001 && targetGain == 0 { gain=0 }
            // Same fourth-harmonic blend as '높은 소리 섞음', with constant loudness.
            output[i]=Float((sin(phase)+0.35*sin(phase*4))/1.35*gain)
            phase += 2 * .pi*hertz/sampleRate
            if phase >= 2 * .pi { phase -= 2 * .pi }
        }
    }
}

public struct ContinuousToneCommand: Sendable {
    public let hertz: Double?
    public let volume: Double
    public let updatedAt: Double
    public init(hertz: Double?, volume: Double=0.12, updatedAt: Double) {
        self.hertz=hertz;self.volume=volume;self.updatedAt=updatedAt
    }
    public func activeHertz(at time: Double) -> Double? {
        guard time.isFinite, updatedAt.isFinite, time >= updatedAt,
              time-updatedAt <= ContinuousDirectionGate.maximumSampleGap else { return nil }
        return hertz.flatMap {$0.isFinite ? $0 : nil}
    }
}
