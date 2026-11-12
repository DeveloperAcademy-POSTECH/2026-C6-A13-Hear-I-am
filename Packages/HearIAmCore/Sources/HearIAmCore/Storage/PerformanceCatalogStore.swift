import Foundation

/// Serial, atomic metadata transactions. A corrupt catalog is never replaced with an empty one.
public actor PerformanceCatalogStore {
    public let root: URL
    public init(root: URL) {self.root=root}
    private var file: URL {root.appendingPathComponent("performances.json")}
    public func load() throws -> PerformanceCatalog {
        guard FileManager.default.fileExists(atPath:file.path) else {return PerformanceCatalog()}
        let value=try JSONDecoder().decode(PerformanceCatalog.self,from:Data(contentsOf:file))
        try value.validate();return value
    }
    private func commit(_ value: PerformanceCatalog) throws -> PerformanceCatalog {
        var value=value
        value.prepareLegacySynchronization()
        if let revision=value.legacySynchronization?.revision {
            guard revision < UInt64.max else {throw LabError.invalid(L("이전 장소 자료의 정리 상태를 확인해주세요."))}
            value.legacySynchronization?.revision=revision+1
        }
        try value.validate()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        try encoder.encode(value).write(to:file,options:.atomic)
        return value
    }
    public func migrateIfNeeded(scans: [ScanManifest], plans: [PerformancePlan], places: PlaceFolderIndex) throws -> PerformanceCatalog {
        let current=try load()
        if current.migrationCompleted {return current}
        guard current.performances.isEmpty && current.assignments.isEmpty else {throw LabError.invalid(L("기존 공연 보관함의 이전 상태를 확인해주세요."))}
        return try commit(.migrating(scans:scans,plans:plans,places:places))
    }
    private func ready() throws -> PerformanceCatalog {
        let value=try load()
        guard value.migrationCompleted else {throw LabError.invalid(L("공연 목록을 먼저 불러와주세요."))}
        return value
    }
    public func upsert(_ folder: PerformanceFolder) throws -> PerformanceCatalog {
        var value=try ready(), folder=folder
        folder.name=folder.name.trimmingCharacters(in:.whitespacesAndNewlines)
        folder.notes=folder.notes.trimmingCharacters(in:.whitespacesAndNewlines)
        folder.updatedAt=Date()
        if let i=value.performances.firstIndex(where:{$0.id==folder.id}) {
            // Dedicated tag/plan methods own those fields to avoid lost updates from an older form.
            folder.venues=value.performances[i].venues;folder.referencePlanIDs=value.performances[i].referencePlanIDs
            value.performances[i]=folder
        } else {value.performances.append(folder)}
        return try commit(value)
    }
    public func deletePerformance(_ id: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        let scanIDs=Set(value.assignments.keys.filter {value.assignments[$0]?.performanceID==id})
        let venueIDs=Set(value.performances.first {$0.id==id}?.venues.map(\.id) ?? [])
        value.detachLegacyAssignments(scanIDs)
        value.retireLegacyVenues(venueIDs)
        value.performances.removeAll {$0.id==id}
        value.assignments=value.assignments.filter {$0.value.performanceID != id}
        return try commit(value)
    }
    public func upsertVenue(_ tag: PerformanceVenueTag, in performanceID: UUID) throws -> PerformanceCatalog {
        var value=try ready(),tag=tag;tag.name=tag.name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard let i=value.performances.firstIndex(where:{$0.id==performanceID}) else {throw LabError.invalid(L("공연을 찾을 수 없어요."))}
        if let j=value.performances[i].venues.firstIndex(where:{$0.id==tag.id}) {
            let existing=value.performances[i].venues[j]
            if existing.name != tag.name {value.renameLegacyVenue(tag.id,in:performanceID,to:tag.name)}
            value.performances[i].venues[j]=PerformanceVenueTag(id:tag.id,name:tag.name,createdAt:existing.createdAt,updatedAt:Date())
        }
        else {value.performances[i].venues.append(tag)}
        value.performances[i].updatedAt=Date()
        return try commit(value)
    }
    public func deleteVenue(_ id: UUID, in performanceID: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        guard let i=value.performances.firstIndex(where:{$0.id==performanceID}) else {throw LabError.invalid(L("공연을 찾을 수 없어요."))}
        let scanIDs=Set(value.assignments.keys.filter {value.assignments[$0]?.performanceID==performanceID && value.assignments[$0]?.venueID==id})
        value.detachLegacyAssignments(scanIDs)
        value.retireLegacyVenues([id])
        value.performances[i].venues.removeAll {$0.id==id}
        for key in Array(value.assignments.keys) where value.assignments[key]?.performanceID==performanceID && value.assignments[key]?.venueID==id {
            value.assignments[key]?.venueID=nil
        }
        value.performances[i].updatedAt=Date()
        return try commit(value)
    }
    public func assign(_ scanIDs: [UUID], to performanceID: UUID?, venueID: UUID? = nil) throws -> PerformanceCatalog {
        var value=try ready()
        if let performanceID {
            guard let folder=value.performances.first(where:{$0.id==performanceID}),
                  venueID==nil || folder.venues.contains(where:{$0.id==venueID}) else {throw LabError.invalid(L("옮길 공연과 공연·연습 공간을 다시 선택해주세요."))}
            let changed=Set(scanIDs.filter {value.assignments[$0]?.performanceID != performanceID || value.assignments[$0]?.venueID != venueID})
            value.detachLegacyAssignments(changed)
            for id in scanIDs {value.assignments[id] = .init(performanceID:performanceID,venueID:venueID,legacyPath:value.assignments[id]?.legacyPath ?? [])}
        } else {
            guard venueID==nil else {throw LabError.invalid(L("공연을 먼저 선택해주세요."))}
            value.detachLegacyAssignments(Set(scanIDs))
            for id in scanIDs {value.assignments.removeValue(forKey:id)}
        }
        return try commit(value)
    }
    public func removeScanReferences(_ id: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        value.detachLegacyAssignments([id],deletingScans:true)
        value.assignments.removeValue(forKey:id)
        return try commit(value)
    }
    /// Also retries metadata cleanup when an earlier scan-bundle deletion was interrupted.
    public func reconcileScanReferences(validScanIDs: Set<UUID>) throws -> PerformanceCatalog {
        var value=try ready()
        let previous=value
        value.prepareLegacySynchronization()
        let known=Set(value.assignments.keys)
            .union(value.legacyPlaces?.assignments.keys.map {$0} ?? [])
            .union(value.legacyPlaces?.favoriteScans ?? [])
        let missing=known.subtracting(validScanIDs)
        value.detachLegacyAssignments(missing,deletingScans:true)
        for id in missing {value.assignments.removeValue(forKey:id)}
        // Older builds left historical aliases after deleting or moving a venue. A name mismatch
        // is not proof that the original place was renamed: detach it instead of rewriting it.
        for id in known.intersection(validScanIDs) {
            if let places=value.legacyPlaces, let destination=places.destination(for:id),
               let place=places.places.first(where:{$0.id==destination.placeID}),
               let venue=value.venue(for:id),
               PlaceSearch.normalized(venue.name)==PlaceSearch.normalized(place.name) {
                value.assignments[id]?.legacyPath=places.path(for:id)
            } else {
                value.detachLegacyAssignments([id])
            }
        }
        guard value != previous else {return previous}
        return try commit(value)
    }

    /// Adds a scene without replacing existing ones; updating the same ID preserves its position.
    public func addReferencePlan(_ planID: UUID, for performanceID: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        guard let i=value.performances.firstIndex(where:{$0.id==performanceID}) else {throw LabError.invalid(L("공연을 찾을 수 없어요."))}
        if !value.performances[i].referencePlanIDs.contains(planID) {value.performances[i].referencePlanIDs.append(planID)}
        value.performances[i].updatedAt=Date()
        return try commit(value)
    }
    public func removeReferencePlan(_ planID: UUID, from performanceID: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        guard let i=value.performances.firstIndex(where:{$0.id==performanceID}) else {throw LabError.invalid(L("공연을 찾을 수 없어요."))}
        guard value.performances[i].referencePlanIDs.contains(planID) else {return value}
        value.performances[i].referencePlanIDs.removeAll {$0==planID}
        value.performances[i].updatedAt=Date()
        return try commit(value)
    }
    public func removePlanReferences(_ planID: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        for i in value.performances.indices where value.performances[i].referencePlanIDs.contains(planID) {
            value.performances[i].referencePlanIDs.removeAll {$0==planID}
            value.performances[i].updatedAt=Date()
        }
        return try commit(value)
    }
    public func setDefaultPlan(_ planID: UUID?, for performanceID: UUID) throws -> PerformanceCatalog {
        var value=try ready()
        guard let i=value.performances.firstIndex(where:{$0.id==performanceID}) else {throw LabError.invalid(L("공연을 찾을 수 없어요."))}
        value.performances[i].defaultPlanID=planID;value.performances[i].updatedAt=Date()
        return try commit(value)
    }
}
