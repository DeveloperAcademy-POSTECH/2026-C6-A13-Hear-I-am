import Foundation

public enum GuidanceReplayStatus: String, Codable, Sendable {
    case guiding, paused, offRoute, outsideStage, obstacle, recovering, untracked
}
public struct GuidanceReplaySample: Codable, Equatable, Sendable {
    public let time: Double
    public let position: FloorPoint?
    public let heading: Double?
    public let targetIndex: Int
    public let status: GuidanceReplayStatus
    public init(time: Double, position: FloorPoint?, heading: Double?, targetIndex: Int, status: GuidanceReplayStatus) {
        self.time=time;self.position=position;self.heading=heading;self.targetIndex=targetIndex;self.status=status
    }
}

/// Elapsed time includes pauses and tracking gaps, independently of the existing active-duration metric.
public struct GuidanceReplay: Codable, Equatable, Sendable {
    public static let sampleInterval=0.2
    public static let maximumSamples=72_000
    public static let maximumInterpolationGap=0.75
    public let duration: Double
    public let samples: [GuidanceReplaySample]
    public let truncated: Bool
    public init(duration: Double, samples: [GuidanceReplaySample], truncated: Bool = false) {
        self.duration=duration;self.samples=samples;self.truncated=truncated
    }
    public func validate(pointCount: Int) throws {
        guard duration.isFinite,duration>=0,!samples.isEmpty,samples.count<=Self.maximumSamples else {
            throw LabError.invalid("이동 기록의 길이가 올바르지 않습니다.")
        }
        var previous = -Double.infinity
        for s in samples {
            guard s.time.isFinite,s.time>=0,s.time<=duration+0.001,s.time>previous,
                  (1..<pointCount).contains(s.targetIndex),s.position?.valid ?? true,
                  s.heading.map({$0.isFinite && abs($0)<=180}) ?? true,
                  s.position != nil || s.heading == nil,
                  s.status != .untracked || s.position == nil else {
                throw LabError.invalid("이동 기록의 위치 또는 시간이 올바르지 않습니다.")
            }
            previous=s.time
        }
    }
    /// Never draw or measure across missing tracking, stale samples or a physically implausible jump.
    public func connects(_ a: GuidanceReplaySample, _ b: GuidanceReplaySample) -> Bool {
        guard let x=a.position,let y=b.position else {return false}
        let dt=b.time-a.time
        return dt>0 && dt<=Self.maximumInterpolationGap && x.distance(to:y)<=4*dt+0.15
    }
    public func index(at time: Double) -> Int? {
        guard time.isFinite,let first=samples.first,time>=first.time else {return nil}
        var low=0,high=samples.count
        while low<high {let mid=(low+high)/2;if samples[mid].time<=time {low=mid+1} else {high=mid}}
        return max(0,low-1)
    }
    public func pose(at time: Double) -> GuidanceReplaySample? {
        guard let index=index(at:time) else {return nil}
        let a=samples[index]
        guard let from=a.position else {return nil}
        if abs(time-a.time)<0.0001 {return a}
        guard samples.indices.contains(index+1) else {
            return time<=duration && time-a.time<=Self.sampleInterval+0.001 ? a : nil
        }
        let b=samples[index+1]
        guard connects(a,b),let to=b.position else {return nil}
        let fraction=max(0,min(1,(time-a.time)/(b.time-a.time)))
        let heading: Double?
        if let ah=a.heading,let bh=b.heading {
            heading=HeadingMath.wrapDegrees(ah+HeadingMath.wrapDegrees(bh-ah)*fraction)
        } else {heading=a.heading}
        return GuidanceReplaySample(time:time,position:FloorPoint(from.x+(to.x-from.x)*fraction,from.y+(to.y-from.y)*fraction),
            heading:heading,targetIndex:a.targetIndex,status:a.status)
    }
}

public struct GuidanceReplayEvent: Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {case start, arrival(Int), status(GuidanceReplayStatus), finish}
    public let time: Double
    public let kind: Kind
    public var id: String {"\(time)-\(kind)"}
}

/// Precompute summaries once when opening a record; scrubbing only performs a binary search.
public struct GuidanceReplayAnalysis: Sendable {
    public let distance: Double
    public let maximumDeviation: Double
    public let missingSeconds: Double
    public let events: [GuidanceReplayEvent]
    public init(replay: GuidanceReplay,route: StageRoute) {
        var distance=0.0,maximum=0.0,covered=0.0
        var events=[GuidanceReplayEvent(time:0,kind:.start)]
        for (i,s) in replay.samples.enumerated() {
            if let p=s.position {maximum=max(maximum,Self.deviation(p,route:route))}
            guard i>0 else {continue}
            let previous=replay.samples[i-1]
            if replay.connects(previous,s),let a=previous.position,let b=s.position {
                distance+=a.distance(to:b);covered+=s.time-previous.time
            }
            if s.targetIndex>previous.targetIndex {events.append(.init(time:s.time,kind:.arrival(previous.targetIndex)))}
            if s.status != previous.status {events.append(.init(time:s.time,kind:.status(s.status)))}
        }
        events.append(.init(time:replay.duration,kind:.finish))
        self.distance=distance;self.maximumDeviation=maximum
        self.missingSeconds=max(0,replay.duration-covered);self.events=events
    }
    public static func deviation(_ p: FloorPoint,route: StageRoute) -> Double {
        zip(route.points,route.points.dropFirst()).map {p.distance(toSegmentFrom:$0.0,to:$0.1)}.min() ?? 0
    }
}
