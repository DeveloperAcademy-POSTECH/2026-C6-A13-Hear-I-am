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

/// A session UUID is the filename, making a repeated finish/save idempotent.
public actor GuidanceRecordStore {
    public let root: URL
    public init(root: URL) { self.root=root }
    @discardableResult public func save(_ record: GuidanceRecord) throws -> GuidanceRecord {
        try record.validate()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let url=root.appendingPathComponent(record.id.uuidString+".json")
        if FileManager.default.fileExists(atPath:url.path) {
            let existing=try decode(url)
            guard existing.stageID == record.stageID, existing.route == record.route,
                  existing.startedAt == record.startedAt, existing.completedAt == record.completedAt,
                  existing.activeSeconds == record.activeSeconds else { throw LabError.invalid("이미 저장된 안내 기록과 일치하지 않습니다.") }
            return existing
        }
        try JSONEncoder().encode(record).write(to:url,options:.atomic)
        return record
    }
    public func list() throws -> [GuidanceRecord] {
        guard FileManager.default.fileExists(atPath:root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:.skipsHiddenFiles)
            .filter { $0.pathExtension == "json" }.map { try decode($0) }
            .sorted { $0.finishedAt == $1.finishedAt ? $0.id.uuidString < $1.id.uuidString : $0.finishedAt > $1.finishedAt }
    }
    private func decode(_ url: URL) throws -> GuidanceRecord {
        let record=try JSONDecoder().decode(GuidanceRecord.self,from:Data(contentsOf:url))
        try record.validate()
        guard url.deletingPathExtension().lastPathComponent == record.id.uuidString else { throw LabError.invalid("안내 기록 ID가 일치하지 않습니다.") }
        return record
    }
}
