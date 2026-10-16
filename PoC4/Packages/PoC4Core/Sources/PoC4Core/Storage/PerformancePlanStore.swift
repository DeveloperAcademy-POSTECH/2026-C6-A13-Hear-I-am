import Foundation

/// One atomic file per plan; independent from scanned world maps and their metadata.
public actor PerformancePlanStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func save(_ plan: PerformancePlan) throws {
        try plan.validate()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(plan).write(to: root.appendingPathComponent(plan.id.uuidString + ".json"), options: .atomic)
    }
    public func delete(_ id: UUID) throws {
        let file=root.appendingPathComponent(id.uuidString + ".json")
        if FileManager.default.fileExists(atPath:file.path) {try FileManager.default.removeItem(at:file)}
    }
    public func list() throws -> [PerformancePlan] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter {$0.pathExtension == "json"}.map { url in
                let plan = try JSONDecoder().decode(PerformancePlan.self, from: Data(contentsOf: url))
                try plan.validate()
                guard url.deletingPathExtension().lastPathComponent == plan.id.uuidString else { throw LabError.invalid("공연 사전 저장 ID가 일치하지 않습니다.") }
                return plan
            }.sorted { $0.updatedAt > $1.updatedAt }
    }
}
