import Foundation

/// A space folder can exist before its first scan. The persisted tag ID remains unchanged.
public struct PerformanceVenueTag: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public var updatedAt: Date
    fileprivate static let legacyDate = Date(timeIntervalSince1970: 0)

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), updatedAt: Date? = nil) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
    enum CodingKeys: String, CodingKey { case id, name, createdAt, updatedAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Self.legacyDate
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

public struct PerformanceFolder: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var notes: String
    /// Ordered reference scenes only; no relationship to a scan's waypoint count or coordinates.
    public var referencePlanIDs: [UUID]
    public var venues: [PerformanceVenueTag]
    public let createdAt: Date
    public var updatedAt: Date

    /// Compatibility for older callers. Selecting a default never discards the other scenes.
    public var defaultPlanID: UUID? {
        get { referencePlanIDs.first }
        set {
            if let newValue { referencePlanIDs = [newValue] + referencePlanIDs.filter { $0 != newValue } }
            else if !referencePlanIDs.isEmpty { referencePlanIDs.removeFirst() }
        }
    }
    public init(id: UUID = UUID(), name: String, notes: String = "", defaultPlanID: UUID? = nil,
                venues: [PerformanceVenueTag] = [], createdAt: Date = Date(), referencePlanIDs: [UUID] = []) {
        self.id = id; self.name = name; self.notes = notes
        self.referencePlanIDs = referencePlanIDs
        if let defaultPlanID, !self.referencePlanIDs.contains(defaultPlanID) { self.referencePlanIDs.insert(defaultPlanID, at: 0) }
        self.venues = venues; self.createdAt = createdAt; self.updatedAt = createdAt
    }
    enum CodingKeys: String, CodingKey { case id, name, notes, defaultPlanID, referencePlanIDs, venues, createdAt, updatedAt }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        referencePlanIDs = try values.decodeIfPresent([UUID].self, forKey: .referencePlanIDs) ?? []
        if let oldID = try values.decodeIfPresent(UUID.self, forKey: .defaultPlanID), !referencePlanIDs.contains(oldID) {
            referencePlanIDs.insert(oldID, at: 0)
        }
        venues = try values.decodeIfPresent([PerformanceVenueTag].self, forKey: .venues) ?? []
        // Older venue tags had no dates. Inherit the owning folder's known date deterministically.
        venues = venues.map { venue in
            guard venue.createdAt == PerformanceVenueTag.legacyDate else { return venue }
            return PerformanceVenueTag(id: venue.id, name: venue.name, createdAt: createdAt, updatedAt: updatedAt)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(name, forKey: .name)
        try values.encode(notes, forKey: .notes); try values.encode(referencePlanIDs, forKey: .referencePlanIDs)
        try values.encodeIfPresent(defaultPlanID, forKey: .defaultPlanID)
        try values.encode(venues, forKey: .venues); try values.encode(createdAt, forKey: .createdAt)
        try values.encode(updatedAt, forKey: .updatedAt)
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

/// IDs retained across source-file cleanup retries. No scan contents are stored here.
public struct LegacyPlaceSynchronization: Codable, Equatable, Sendable {
    public var id: UUID = UUID()
    public var revision: UInt64 = 0
    public var managedPlaceIDs: Set<UUID> = []
    public var managedScanIDs: Set<UUID> = []
    public var renamedPlaceNames: [UUID: String] = [:]
    public var venuePlaceIDs: [UUID: Set<UUID>] = [:]
    public init() {}
}

/// Classification only. Deleting folders or tags never deletes a scan, map, plan or record.
public struct PerformanceCatalog: Codable, Equatable, Sendable {
    public var version = 1
    public var migrationCompleted = false
    public var performances: [PerformanceFolder] = []
    public var assignments: [UUID: PerformanceAssignment] = [:]
    /// Preserve addresses, photos, empty subfolders and favorites that do not fit the new hierarchy.
    public var legacyPlaces: PlaceFolderIndex?
    /// Optional for catalogs saved before #137; initialized before the next metadata transaction.
    public var legacySynchronization: LegacyPlaceSynchronization?
    public init() {}
    public func folder(for scanID: UUID) -> PerformanceFolder? {
        guard let assignment=assignments[scanID] else {return nil}
        return performances.first {$0.id==assignment.performanceID}
    }
    public func venue(for scanID: UUID) -> PerformanceVenueTag? {
        guard let assignment=assignments[scanID], let id=assignment.venueID else {return nil}
        return folder(for:scanID)?.venues.first {$0.id==id}
    }
    /// A chosen performance exposes only its scenes. No selection keeps legacy independent plans reachable.
    public func referencePlans(among plans: [PerformancePlan], for performanceID: UUID?) -> [PerformancePlan] {
        guard let performanceID else {return plans}
        guard let folder=performances.first(where:{$0.id==performanceID}) else {return []}
        return folder.referencePlanIDs.compactMap {id in plans.first {$0.id==id}}
    }
    public func validate() throws {
        guard version==1 else {throw LabError.invalid(L("지원하지 않는 공연 보관함 버전입니다."))}
        guard Set(performances.map(\.id)).count==performances.count else {throw LabError.invalid(L("공연 식별자가 중복됩니다."))}
        try Self.validateNames(performances.map(\.name), label:L("공연"))
        for folder in performances {
            guard Set(folder.referencePlanIDs).count == folder.referencePlanIDs.count else {throw LabError.invalid(L("씬 식별자가 중복됩니다."))}
            guard folder.notes.count<=2000 else {throw LabError.invalid(L("공연 설명은 2000자 이내로 입력해주세요."))}
            guard Set(folder.venues.map(\.id)).count==folder.venues.count else {throw LabError.invalid(L("공연·연습 공간 식별자가 중복됩니다."))}
            try Self.validateNames(folder.venues.map(\.name), label:L("공연·연습 공간"))
        }
        for value in assignments.values {
            guard let folder=performances.first(where:{$0.id==value.performanceID}),
                  value.venueID==nil || folder.venues.contains(where:{$0.id==value.venueID}) else {
                throw LabError.invalid(L("무대의 공연 또는 공연·연습 공간을 찾을 수 없어요."))
            }
        }
        try legacyPlaces?.validate()
        if let synchronization=legacySynchronization {
            guard let legacyPlaces,
                  Set(legacyPlaces.places.map(\.id)).isSubset(of:synchronization.managedPlaceIDs),
                  Set(legacyPlaces.assignments.keys).union(legacyPlaces.favoriteScans).isSubset(of:synchronization.managedScanIDs),
                  synchronization.venuePlaceIDs.values.allSatisfy({$0.isSubset(of:synchronization.managedPlaceIDs)}),
                  Set(synchronization.renamedPlaceNames.keys).isSubset(of:synchronization.managedPlaceIDs) else {
                throw LabError.invalid(L("이전 장소 자료의 정리 상태를 확인해주세요."))
            }
        }
    }
    /// Preserve every imported ID, including empty places. Only explicit operations retire a place.
    mutating func prepareLegacySynchronization() {
        guard let places=legacyPlaces else {return}
        if legacySynchronization == nil {
            var state=LegacyPlaceSynchronization()
            // Reimporting an archive after the catalog was removed must advance its existing
            // synchronization stream, not create an incompatible second identity.
            if let id=places.performanceSynchronizationID {
                state.id=id;state.revision=places.performanceSynchronizationRevision ?? 0
            }
            state.managedPlaceIDs=Set(places.places.map(\.id))
            state.managedScanIDs=Set(places.assignments.keys).union(places.favoriteScans)
            for scanID in assignments.keys {
                if let venue=venue(for:scanID), let placeID=places.destination(for:scanID)?.placeID,
                   let place=places.places.first(where:{$0.id==placeID}),
                   PlaceSearch.normalized(venue.name)==PlaceSearch.normalized(place.name) {
                    state.venuePlaceIDs[venue.id,default:[]].insert(placeID)
                }
            }
            legacySynchronization=state
        }
    }

    mutating func detachLegacyAssignments(_ scanIDs: Set<UUID>, deletingScans: Bool = false) {
        prepareLegacySynchronization()
        for id in scanIDs {
            assignments[id]?.legacyPath=[]
            legacyPlaces?.assignments.removeValue(forKey:id)
            if deletingScans {legacyPlaces?.favoriteScans.remove(id)}
        }
    }

    /// Deleting a classification does not delete archived place data or photographs.
    mutating func retireLegacyVenues(_ venueIDs: Set<UUID>) {
        prepareLegacySynchronization()
        for id in venueIDs {legacySynchronization?.venuePlaceIDs.removeValue(forKey:id)}
    }

    mutating func renameLegacyVenue(_ venueID: UUID, in performanceID: UUID, to name: String) {
        prepareLegacySynchronization()
        guard var state=legacySynchronization, var places=legacyPlaces else {
            for id in assignments.keys where assignments[id]?.performanceID==performanceID && assignments[id]?.venueID==venueID {
                assignments[id]?.legacyPath=[]
            }
            return
        }
        let scanIDs=Set(assignments.keys.filter {assignments[$0]?.performanceID==performanceID && assignments[$0]?.venueID==venueID})
        let linked=state.venuePlaceIDs[venueID] ?? []
        let otherOwners=state.venuePlaceIDs.filter {$0.key != venueID}.values.reduce(into:Set<UUID>()) {$0.formUnion($1)}
            .union(places.assignments.filter {!scanIDs.contains($0.key)}.values.map(\.placeID))
        let shared=linked.intersection(otherOwners)
        // Renaming one V3 space must not rename a source still used by another performance.
        for i in places.places.indices where linked.contains(places.places[i].id) && !shared.contains(places.places[i].id) {
            places.places[i].name=name
            state.renamedPlaceNames[places.places[i].id]=name
        }
        for id in scanIDs {
            if let placeID=places.assignments[id]?.placeID, shared.contains(placeID) {
                places.assignments.removeValue(forKey:id)
            }
            assignments[id]?.legacyPath=places.destination(for:id)==nil ? [] : places.path(for:id)
        }
        state.venuePlaceIDs[venueID]=linked.subtracting(shared)
        legacyPlaces=places;legacySynchronization=state
    }

    static func validateNames(_ names: [String], label: String) throws {
        guard names.allSatisfy({!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.count<=80}) else {
            throw LabError.invalid(L("%@ 이름은 1~80자로 입력해주세요.", label))
        }
        guard Set(names.map(PlaceSearch.normalized)).count==names.count else {
            throw LabError.invalid(L("같은 이름이 이미 있어요. 다른 %@ 이름을 입력해주세요.", label))
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
        result.prepareLegacySynchronization()
        try result.validate()
        return result
    }
}
