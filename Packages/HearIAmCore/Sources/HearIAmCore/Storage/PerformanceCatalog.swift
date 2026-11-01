import Foundation

public struct PerformanceVenueTag: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id=id; self.name=name }
}

public struct PerformanceFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var notes: String
    public var defaultPlanID: UUID?
    public var venues: [PerformanceVenueTag]
    public let createdAt: Date
    public var updatedAt: Date
    public init(id: UUID = UUID(), name: String, notes: String = "", defaultPlanID: UUID? = nil,
                venues: [PerformanceVenueTag] = [], createdAt: Date = Date()) {
        self.id=id; self.name=name; self.notes=notes; self.defaultPlanID=defaultPlanID
        self.venues=venues; self.createdAt=createdAt; self.updatedAt=createdAt
    }
}

public struct PerformanceAssignment: Codable, Equatable, Sendable {
    public var performanceID: UUID
    public var venueID: UUID?
    /// Original place and subfolder names remain available after the one-time migration.
    public var legacyPath: [String]
    public init(performanceID: UUID, venueID: UUID? = nil, legacyPath: [String] = []) {
        self.performanceID=performanceID; self.venueID=venueID; self.legacyPath=legacyPath
    }
}

/// Classification only. Deleting folders or tags never deletes a scan, map, plan or record.
public struct PerformanceCatalog: Codable, Equatable, Sendable {
    public var version = 1
    public var migrationCompleted = false
    public var performances: [PerformanceFolder] = []
    public var assignments: [UUID: PerformanceAssignment] = [:]
    /// Preserve addresses, photos, empty subfolders and favorites that do not fit the new hierarchy.
    public var legacyPlaces: PlaceFolderIndex?
    public init() {}
    public func folder(for scanID: UUID) -> PerformanceFolder? {
        guard let assignment=assignments[scanID] else {return nil}
        return performances.first {$0.id==assignment.performanceID}
    }
    public func venue(for scanID: UUID) -> PerformanceVenueTag? {
        guard let assignment=assignments[scanID], let id=assignment.venueID else {return nil}
        return folder(for:scanID)?.venues.first {$0.id==id}
    }
    public func validate() throws {
        guard version==1 else {throw LabError.invalid("지원하지 않는 공연 보관함 버전입니다.")}
        guard Set(performances.map(\.id)).count==performances.count else {throw LabError.invalid("공연 식별자가 중복됩니다.")}
        try Self.validateNames(performances.map(\.name), label:"공연")
        for folder in performances {
            guard folder.notes.count<=2000 else {throw LabError.invalid("공연 설명은 2000자 이내로 입력해주세요.")}
            guard Set(folder.venues.map(\.id)).count==folder.venues.count else {throw LabError.invalid("공연장 태그 식별자가 중복됩니다.")}
            try Self.validateNames(folder.venues.map(\.name), label:"공연장 태그")
        }
        for value in assignments.values {
            guard let folder=performances.first(where:{$0.id==value.performanceID}),
                  value.venueID==nil || folder.venues.contains(where:{$0.id==value.venueID}) else {
                throw LabError.invalid("무대의 공연 또는 공연장 태그를 찾을 수 없어요.")
            }
        }
        try legacyPlaces?.validate()
    }
    static func validateNames(_ names: [String], label: String) throws {
        guard names.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=80}) else {
            throw LabError.invalid("\(label) 이름은 1~80자로 입력해주세요.")
        }
        guard Set(names.map(PlaceSearch.normalized)).count==names.count else {
            throw LabError.invalid("같은 이름이 이미 있어요. 다른 \(label) 이름을 입력해주세요.")
        }
    }

    /// Deterministic grouping; persisted IDs are generated only before the first atomic commit.
    public static func migrating(scans: [ScanManifest], plans: [PerformancePlan], places: PlaceFolderIndex) throws -> PerformanceCatalog {
        try places.validate()
        var result=PerformanceCatalog();result.legacyPlaces=places
        for scan in scans.sorted(by:{$0.id.uuidString<$1.id.uuidString}) {
            let key=PlaceSearch.normalized(scan.name)
            let index: Int
            if let existing=result.performances.firstIndex(where:{PlaceSearch.normalized($0.name)==key}) {index=existing}
            else {result.performances.append(.init(name:scan.name.trimmingCharacters(in:.whitespacesAndNewlines)));index=result.performances.count-1}
            var venueID: UUID?
            if let destination=places.destination(for:scan.id),let place=places.places.first(where:{$0.id==destination.placeID}) {
                if let tag=result.performances[index].venues.first(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(place.name)}) {venueID=tag.id}
                else {let tag=PerformanceVenueTag(name:place.name);result.performances[index].venues.append(tag);venueID=tag.id}
            }
            result.assignments[scan.id] = .init(performanceID:result.performances[index].id,venueID:venueID,
                                               legacyPath:places.destination(for:scan.id)==nil ? [] : places.path(for:scan.id))
        }
        // Every independent plan remains reachable, including multiple plans sharing a name.
        for plan in plans.sorted(by:{$0.id.uuidString<$1.id.uuidString}) {
            if let index=result.performances.firstIndex(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(plan.name) && $0.defaultPlanID==nil}) {
                result.performances[index].defaultPlanID=plan.id
            } else {
                var name=plan.name.trimmingCharacters(in:.whitespacesAndNewlines), suffix=2
                while result.performances.contains(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(name)}) {
                    let tail=" (\(suffix))";name=String(plan.name.prefix(80-tail.count))+tail;suffix+=1
                }
                result.performances.append(.init(name:name,defaultPlanID:plan.id))
            }
        }
        result.migrationCompleted=true
        try result.validate()
        return result
    }
}
