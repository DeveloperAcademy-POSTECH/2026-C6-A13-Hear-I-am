import Foundation

/// PoC1's landmark detector (AngleLandmarkDetector), carried over with integer landmarks.
/// The default landmarks are the 45° field set in DirectionPattern.
/// Feed the body angle relative to the next target (0° = facing it). A landmark fires when the
/// angle enters ±3° of it or a fast turn jumps across it, and fires again only after leaving ±6°.
/// Consecutive samples are assumed to be less than 180° apart. Call reset() after a sensor gap.
public struct LandmarkDetector: Sendable {
    public let landmarks: [Int]
    public let entryTolerance: Double
    public let rearmTolerance: Double
    private var latched: Set<Int>=[]
    private var previousWrapped: Double?
    private var previousContinuous: Double?

    public init(landmarks: [Int]=DirectionPattern.landmarks, entryTolerance: Double=3, rearmTolerance: Double=6) {
        self.landmarks=Array(Set(landmarks.filter { (-180...180).contains($0) }.map { $0 == -180 ? 180 : $0 })).sorted()
        let entry=entryTolerance.isFinite && (0..<90).contains(entryTolerance) ? entryTolerance : 3
        self.entryTolerance=entry
        self.rearmTolerance=rearmTolerance.isFinite && rearmTolerance > entry && rearmTolerance < 180 ? rearmTolerance : max(6,entry+1)
    }
    public mutating func reset() { latched.removeAll(); previousWrapped=nil; previousContinuous=nil }

    /// Returns at most one landmark: the last one newly reached along this movement. Nothing is queued.
    /// An invalid reading breaks interpolation so a later sample cannot cross an unseen arc.
    @discardableResult public mutating func update(relativeDegrees: Double) -> Int? {
        guard relativeDegrees.isFinite else { previousWrapped=nil; previousContinuous=nil; return nil }
        let wrapped=HeadingMath.wrapDegrees(relativeDegrees)
        let previous=previousContinuous
        let delta=previousWrapped.map { HeadingMath.signedDeltaDegrees(from:$0,to:wrapped) } ?? 0
        let current=previous.map { $0+delta } ?? wrapped
        var latest: (landmark: Int, progress: Double)?
        for landmark in landmarks {
            let base=Double(landmark)
            let occurrence=base+360*((current-base)/360).rounded()
            let distance=abs(current-occurrence)
            if latched.contains(landmark) {
                if distance > rearmTolerance { latched.remove(landmark) }
                continue
            }
            let crossed: Bool
            if let previous, delta > 0 { crossed=previous < occurrence && occurrence <= current }
            else if let previous, delta < 0 { crossed=current <= occurrence && occurrence < previous }
            else { crossed=false }
            guard distance <= entryTolerance || crossed else { continue }
            // A fast sample that already left the outer window stays armed.
            if distance <= rearmTolerance { latched.insert(landmark) }
            let progress=previous != nil && delta != 0 ? (crossed ? abs(occurrence-previous!)/abs(delta) : 1) : -distance
            if latest == nil || progress > latest!.progress { latest=(landmark,progress) }
        }
        previousWrapped=wrapped; previousContinuous=current
        return latest?.landmark
    }
}
