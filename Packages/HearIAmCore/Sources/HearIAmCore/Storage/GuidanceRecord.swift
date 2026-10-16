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
    public var reachedPointCount: Int { route.points.count - 1 }
    public var routeLength: Double {
        zip(route.points, route.points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }
    public func validate() throws {
        try route.validate()
        guard version == 1, !stageName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              activeSeconds.isFinite, activeSeconds >= 0,
              [startedAt, completedAt, finishedAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              startedAt <= completedAt, completedAt <= finishedAt else {
            throw LabError.invalid("완료 기록의 정보가 올바르지 않습니다.")
        }
    }
}
