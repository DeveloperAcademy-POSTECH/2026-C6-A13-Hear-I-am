import Foundation

/// The PoC1 direction rhythm (branch poc/1-orientation-haptics), carried over unchanged.
/// 0° is the next target. Front: one short. Back: one long.
/// Left: one long, then one short per 30°. Right: two quick, then one short per 30°.
public enum DirectionPattern {
    /// Only the 30° landmarks have a pattern, as in PoC1.
    public static let landmarks=[0,30,60,90,120,150,180,-150,-120,-90,-60,-30]
    static let sharpness: Float=0.8

    /// nil for angles that are not a 30° landmark. Positive is right, negative is left.
    public static func pulses(signedDegrees: Int) -> [DirectionPulse]? {
        let degrees=signedDegrees == -180 ? 180 : signedDegrees
        guard landmarks.contains(degrees) else { return nil }
        let magnitude=abs(degrees)
        let intensity: Float=magnitude == 30 ? 0.85 : magnitude == 60 ? 0.92 : 1.0
        func pulse(_ time: Double, _ duration: Double, sharpness: Float=sharpness) -> DirectionPulse {
            DirectionPulse(time:time,duration:duration,intensity:intensity,sharpness:sharpness)
        }
        if magnitude == 0 || magnitude == 180 { return [pulse(0,magnitude == 0 ? 0.10 : 0.45)] }
        let lead=degrees < 0 ? [pulse(0,0.10,sharpness:sharpness*0.5)] : [pulse(0,0.03),pulse(0.06,0.03)]
        return lead+(0..<magnitude/30).map { pulse(0.16+Double($0)*0.09,0.035) }
    }
    /// Readable label for logs, e.g. "left_60" or "front".
    public static func name(signedDegrees: Int) -> String {
        let degrees=signedDegrees == -180 ? 180 : signedDegrees
        if degrees == 0 { return "front" }
        if degrees == 180 { return "back" }
        return (degrees < 0 ? "left_" : "right_")+String(abs(degrees))
    }
}
