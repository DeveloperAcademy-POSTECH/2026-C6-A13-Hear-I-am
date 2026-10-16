import Foundation

public struct LibraryPins: Codable, Equatable, Sendable {
    public private(set) var ids: Set<UUID> = []
    public init() {}
    public mutating func toggle(_ id: UUID) { if !ids.insert(id).inserted { ids.remove(id) } }
    public mutating func remove(_ id: UUID) {ids.remove(id)}
    public func groups(_ records: [ScanManifest]) -> (pinned: [ScanManifest], recent: [ScanManifest]) {
        let sorted = records.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
        return (sorted.filter {ids.contains($0.id)}, sorted.filter {!ids.contains($0.id)})
    }
}
