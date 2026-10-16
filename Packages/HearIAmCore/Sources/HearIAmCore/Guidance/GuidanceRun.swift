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
    public init(stageID: UUID, stageName: String, route: StageRoute) {
        self.stageID=stageID; self.stageName=stageName; self.route=route
    }
    public mutating func begin(at date: Date, uptime: Double) {
        guard startedAt == nil, uptime.isFinite else { return }
        startedAt=date; setRunning(true, uptime:uptime)
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
    }
    public func record(completionSpoken: Bool, finishedAt: Date) throws -> GuidanceRecord {
        guard completionSpoken, let startedAt, let completedAt else {
            throw LabError.invalid("마지막 지점의 도착 안내가 끝난 후 기록을 저장할 수 있습니다.")
        }
        let value=GuidanceRecord(version:1,id:id,stageID:stageID,stageName:stageName,route:route,
                                 startedAt:startedAt,completedAt:completedAt,finishedAt:max(finishedAt,completedAt),activeSeconds:activeSeconds)
        try value.validate(); return value
    }
}
