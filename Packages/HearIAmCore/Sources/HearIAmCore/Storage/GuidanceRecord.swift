import Foundation

/// A completed run, independent of later edits to or deletion of the source stage.
public struct GuidanceRecord: Codable, Equatable, Identifiable, Sendable {
    public let version: Int
    public let id: UUID
    public let stageID: UUID
    public let stageName: String
    public let route: StageRoute
    public let startedAt: Date
    public let completedAt: Date
    public let finishedAt: Date
    public let activeSeconds: Double
    public let replay: GuidanceReplay?
    /// First saved route point visited by this completed run. Missing on older full-route records.
    /// A direct practice entry skips the saved start and any chair/stair points before P1.
    public let firstGuidedPointIndex: Int?
    public let practiceOrigin: FloorPoint?
    /// The performance and space the stage was filed under when the run finished, so a later move or deletion of the
    /// stage does not rename past runs (#179). Empty when it was not filed; nil on records saved before.
    public let performanceName: String?
    public let venueName: String?
    public init(version: Int,id: UUID,stageID: UUID,stageName: String,route: StageRoute,startedAt: Date,completedAt: Date,
                finishedAt: Date,activeSeconds: Double,replay: GuidanceReplay? = nil,firstGuidedPointIndex: Int? = nil,practiceOrigin: FloorPoint? = nil,
                performanceName: String? = nil,venueName: String? = nil) {
        self.version=version;self.id=id;self.stageID=stageID;self.stageName=stageName;self.route=route
        self.startedAt=startedAt;self.completedAt=completedAt;self.finishedAt=finishedAt;self.activeSeconds=activeSeconds;self.replay=replay;self.firstGuidedPointIndex=firstGuidedPointIndex;self.practiceOrigin=practiceOrigin
        self.performanceName=performanceName;self.venueName=venueName
    }
    public var reachedPointCount: Int { route.points.count - (firstGuidedPointIndex ?? 1) }
    /// The planned polyline for this run, including its temporary entry but excluding unvisited earlier points.
    /// Original route indices remain unchanged in replay samples and in the saved route snapshot.
    public var guidancePath: [FloorPoint] {
        guard let practiceOrigin, let first=firstGuidedPointIndex, route.points.indices.contains(first) else {return route.points}
        return [practiceOrigin]+Array(route.points.dropFirst(first))
    }
    public var guidancePathHeights: [Double] {
        let heights=route.pointHeights ?? Array(repeating:0,count:route.points.count)
        guard practiceOrigin != nil, let first=firstGuidedPointIndex, heights.indices.contains(first) else {return heights}
        return [0]+Array(heights.dropFirst(first))
    }
    public var guidanceRouteLength: Double {
        zip(guidancePath,guidancePath.dropFirst()).reduce(0) {$0+$1.0.distance(to:$1.1)}
    }
    /// Full saved route length, retained for callers comparing against the original plan.
    public var routeLength: Double {
        zip(route.points, route.points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
    public func validate() throws {
        try route.validate()
        try replay?.validate(pointCount:route.points.count)
        guard (firstGuidedPointIndex == nil) == (practiceOrigin == nil), practiceOrigin?.valid ?? true else {
            throw LabError.invalid(L("안내 기록의 연습 출발 정보가 올바르지 않습니다."))
        }
        if let firstGuidedPointIndex {
            guard (1..<route.points.count).contains(firstGuidedPointIndex),
                  replay?.samples.allSatisfy({$0.targetIndex >= firstGuidedPointIndex}) ?? true else {
                throw LabError.invalid(L("안내 기록의 첫 지점이 올바르지 않습니다."))
            }
        }
        guard (version == 1 && replay == nil || version == 2 && replay != nil), !stageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              activeSeconds.isFinite, activeSeconds >= 0,
              [startedAt, completedAt, finishedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              startedAt <= completedAt, completedAt <= finishedAt else {
            throw LabError.invalid(L("완료 기록의 정보가 올바르지 않습니다."))
        }
    }
}
