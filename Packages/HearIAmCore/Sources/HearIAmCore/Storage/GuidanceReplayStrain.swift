import Foundation

/// How cleanly each replay sample follows the walk, from 0 (on the planned path) to 1 (clearly off it), for colouring
/// the walked trail green → yellow → orange the way a running app colours pace.
///
/// Green is kept for walking along the current leg toward its next point. A sample strains when the person
///  - strays from the current leg (another part of the route does not count: being there is the wrong place),
///  - walks somewhere other than toward the next point, or turns back and forth looking for the way,
///  - stands still away from any point of the route,
///  - or when guidance paused because they left the corridor, the stage or came near an obstacle, or was finding them
///    again.
/// The value rises within about half a second and falls back over a second and a half, so a wrong turn shows at once
/// and only a sustained good walk turns the trail green again.
public enum GuidanceReplayStrain {
    /// Strays up to this far from the current leg are a normal walk; this far off counts as fully off it (m).
    public static let freeDeviation=0.25
    public static let fullDeviation=0.7
    /// The recent stretch judged for direction (s), and the least net travel over it worth judging (m).
    public static let directionSeconds=1.2
    public static let directionTravel=0.3
    /// The share of net travel that must close the distance to the next point to count as heading there (cos ≈ 45°).
    public static let goodHeading=0.7
    /// Near the next point the direction is not judged: people slow down and turn there (m).
    public static let nearTarget=0.6
    /// Standing within this window and distance counts as lingering (s · m).
    public static let lingerSeconds=1.6
    public static let lingerDistance=0.2
    /// Lingering this close to a point of the route is the planned stop, not a stray (m).
    public static let pointRadius=0.6
    /// Easing time constants toward more and toward less strain (s).
    public static let riseSeconds=0.5
    public static let fallSeconds=1.5

    /// One value per sample, in sample order.
    public static func values(replay: GuidanceReplay,path: [FloorPoint]) -> [Double] {
        let samples=replay.samples
        var values=[Double](),eased=0.0
        for (i,s) in samples.enumerated() {
            let target=raw(i,replay:replay,path:path)
            if i>0 {
                let dt=max(0,s.time-samples[i-1].time)
                let tau=target>eased ? riseSeconds : fallSeconds
                eased+=(target-eased)*(1-exp(-dt/tau))
            } else {eased=target}
            values.append(eased)
        }
        return values
    }

    static func raw(_ i: Int,replay: GuidanceReplay,path: [FloorPoint]) -> Double {
        let samples=replay.samples,s=samples[i]
        var value: Double
        switch s.status {
        case .offRoute,.outsideStage,.obstacle: value=1
        case .recovering: value=0.8
        case .guiding,.paused,.untracked: value=0
        }
        guard let p=s.position else {return value}
        let leg=path.indices.contains(s.targetIndex) && s.targetIndex>0 ? Array(path[(s.targetIndex-1)...s.targetIndex]) : path
        let deviation=GuidanceReplayAnalysis.deviation(p,points:leg)
        value=max(value,min(1,max(0,(deviation-freeDeviation)/(fullDeviation-freeDeviation))))
        guard s.status == .guiding else {return value}

        // The recent tracked stretch toward the same point.
        let span=max(directionSeconds,lingerSeconds)+0.001
        var j=i
        while j>0,s.time-samples[j-1].time<=span,samples[j-1].targetIndex == s.targetIndex,
              replay.connects(samples[j-1],samples[j]) {j-=1}
        let stretch=samples[j...i]
        let recent=stretch.filter {s.time-$0.time<=directionSeconds+0.001}.compactMap(\.position)
        let nearPoint=path.contains {$0.distance(to:p)<=pointRadius}
        if let first=recent.first,s.time-samples[j].time>=directionSeconds-0.001,path.indices.contains(s.targetIndex) {
            let net=first.distance(to:p)
            let walked=zip(recent,recent.dropFirst()).map {$0.distance(to:$1)}.reduce(0,+)
            let next=path[s.targetIndex]
            if next.distance(to:p)>nearTarget {
                if net>=directionTravel {
                    // Heading: how much of the net travel brought the next point closer (1 straight there, 0 sideways).
                    let closing=(first.distance(to:next)-p.distance(to:next))/net
                    value=max(value,min(1,max(0,(goodHeading-closing)/goodHeading)))
                }
                // Turning back and forth: far more ground walked than gained.
                if walked>0.6 && walked>2.5*net {value=max(value,0.7)}
            }
        }
        // Lingering: still guiding, yet standing in a small spot away from the route's points.
        if !nearPoint && s.time-samples[j].time>=lingerSeconds-0.001 {
            let window=stretch.filter {s.time-$0.time<=lingerSeconds+0.001}.compactMap(\.position)
            if window.count>1 && window.allSatisfy({$0.distance(to:p)<=lingerDistance}) {value=max(value,0.7)}
        }
        return value
    }
}
