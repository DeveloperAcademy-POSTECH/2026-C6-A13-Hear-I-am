import Foundation

/// Monotonic elapsed time excludes pauses and recovery. No record exists for an aborted run.
public struct GuidanceRun: Sendable {
    public let id = UUID()
    private let stageID: UUID
    private let stageName: String
    private let route: StageRoute
    private var startedAt: Date?
    private var completedAt: Date?
    private var segmentStart: Double?
    private var activeSeconds = 0.0
    private var replayStart: Double?
    private var replayEnd: Double?
    private var replaySamples: [GuidanceReplaySample]=[]
    private var replayTruncated=false
    public init(stageID: UUID, stageName: String, route: StageRoute) {
        self.stageID=stageID; self.stageName=stageName; self.route=route
    }
    public mutating func begin(at date: Date, uptime: Double) {
        guard startedAt == nil, uptime.isFinite else { return }
        startedAt=date; replayStart=uptime; setRunning(true, uptime:uptime)
    }
    public mutating func setRunning(_ running: Bool, uptime: Double) {
        guard startedAt != nil, completedAt == nil, uptime.isFinite else { return }
        if running {
            if segmentStart == nil { segmentStart=uptime }
        } else if let start=segmentStart {
            activeSeconds += max(0,uptime-start); segmentStart=nil
        }
    }
    public mutating func arrive(guide: RouteGuide, at date: Date, uptime: Double) {
        guard guide.state == .completed, guide.route == route, let startedAt, completedAt == nil else { return }
        setRunning(false,uptime:uptime)
        completedAt=max(date,startedAt)
        replayEnd=max(0,uptime-(replayStart ?? uptime),replaySamples.last?.time ?? 0)
    }
    /// This observer never mutates guidance rules. Only fresh, verified poses are supplied by the app.
    public mutating func capture(position: FloorPoint?,heading: Double?,targetIndex: Int,status: GuidanceReplayStatus,uptime: Double,force: Bool = false) {
        guard let start=replayStart,completedAt==nil,uptime.isFinite,uptime>=start,
              route.points.indices.contains(targetIndex),targetIndex>0 else {return}
        let elapsed=uptime-start
        // The synchronous departure observer follows begin by a few microseconds. Keep that pose at t=0.
        // A genuinely delayed first sample must leave its preceding interval unrecorded.
        let time=replaySamples.isEmpty && elapsed<0.01 ? 0 : elapsed
        let valid=position?.valid == true && status != .untracked
        let value=GuidanceReplaySample(time:time,position:valid ? position : nil,
            heading:valid ? heading.flatMap {$0.isFinite ? HeadingMath.wrapDegrees($0) : nil} : nil,
            targetIndex:targetIndex,status:valid ? status : .untracked)
        if let last=replaySamples.last {
            guard time>=last.time else {return}
            if time==last.time {replaySamples[replaySamples.count-1]=value;return}
            if !force,time-last.time<Self.sampleIntervalTolerance,last.status==value.status,last.targetIndex==targetIndex {return}
        }
        guard replaySamples.count<GuidanceReplay.maximumSamples else {replayTruncated=true;return}
        replaySamples.append(value)
    }
    private static let sampleIntervalTolerance=GuidanceReplay.sampleInterval-0.0001
    public func record(completionSpoken: Bool, finishedAt: Date) throws -> GuidanceRecord {
        guard completionSpoken, let startedAt, let completedAt else {
            throw LabError.invalid("마지막 지점의 도착 안내가 끝난 후 기록을 저장할 수 있습니다.")
        }
        let replay: GuidanceReplay? = replaySamples.isEmpty ? nil : GuidanceReplay(duration:replayEnd ?? 0,samples:replaySamples,truncated:replayTruncated)
        let value=GuidanceRecord(version:replay == nil ? 1 : 2,id:id,stageID:stageID,stageName:stageName,route:route,
                                 startedAt:startedAt,completedAt:completedAt,finishedAt:max(finishedAt,completedAt),activeSeconds:activeSeconds,replay:replay)
        try value.validate(); return value
    }
}
