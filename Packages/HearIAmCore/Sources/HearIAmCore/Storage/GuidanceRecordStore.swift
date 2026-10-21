import Foundation

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
                  existing.activeSeconds == record.activeSeconds, existing.replay == record.replay else { throw LabError.invalid("이미 저장된 안내 기록과 일치하지 않습니다.") }
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
