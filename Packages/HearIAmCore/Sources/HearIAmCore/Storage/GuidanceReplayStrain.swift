import Foundation

/// How cleanly each replay sample follows the walk, from 0 (on the planned path) to 1 (clearly off it), for colouring
/// the walked trail green → yellow → orange the way a running app colours pace.
///
/// A sample strains when the person strays from the planned path, when guidance paused because they left the
/// corridor, the stage or came near an obstacle, while guidance was finding them again, or when they stood still away
/// from any point of the route. The value eases toward that over about a second, so the trail drifts to orange and
/// back instead of flickering sample by sample.
public enum GuidanceReplayStrain {
    /// Strays up to this far are a normal walk (m).
    public static let freeDeviation=0.4
    /// The guide's corridor: this far off counts as fully off the path (m).
    public static let fullDeviation=RouteGuide.corridorRadius
    /// Standing within this window and distance counts as lingering (s · m).
    public static let lingerSeconds=2.5
    public static let lingerDistance=0.2
    /// Lingering this close to a point of the route is the planned stop, not a stray (m).
    public static let pointRadius=0.6
    /// Easing time constants toward more and toward less strain (s).
    public static let riseSeconds=0.8
    public static let fallSeconds=1.2

    /// One value per sample, in sample order.
    public static func values(replay: GuidanceReplay,path: [FloorPoint]) -> [Double] {
        let samples=replay.samples
        var values=[Double](),eased=0.0,windowStart=0
        for (i,s) in samples.enumerated() {
            let target=raw(i,samples:samples,path:path,windowStart:&windowStart)
            if i>0 {
                let dt=max(0,s.time-samples[i-1].time)
                let tau=target>eased ? riseSeconds : fallSeconds
                eased+=(target-eased)*(1-exp(-dt/tau))
            } else {eased=target}
            values.append(eased)
        }
        return values
    }

    private static func raw(_ i: Int,samples: [GuidanceReplaySample],path: [FloorPoint],windowStart: inout Int) -> Double {
        let s=samples[i]
        var value: Double
        switch s.status {
        case .offRoute,.outsideStage,.obstacle: value=1
        case .recovering: value=0.6
        case .guiding,.paused,.untracked: value=0
        }
        guard let p=s.position else {return value}
        let deviation=GuidanceReplayAnalysis.deviation(p,points:path)
        value=max(value,min(1,max(0,(deviation-freeDeviation)/(fullDeviation-freeDeviation))))
        // Lingering: still guiding, yet the last few seconds stayed within a small spot away from the route's points.
        while windowStart<i && s.time-samples[windowStart].time>lingerSeconds {windowStart+=1}
        if s.status == .guiding,windowStart>0 || s.time-samples[0].time>=lingerSeconds {
            let recent=samples[max(0,windowStart-1)...i].compactMap(\.position)
            let still=recent.count>1 && recent.allSatisfy {$0.distance(to:p)<=lingerDistance}
            let nearPoint=path.contains {$0.distance(to:p)<=pointRadius}
            if still && !nearPoint {value=max(value,0.6)}
        }
        return value
    }
}
