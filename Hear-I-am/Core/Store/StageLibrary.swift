import Foundation
import SwiftUI
import HearIAmCore

@MainActor final class StageLibrary: ObservableObject {
    @Published private(set) var catalog=PerformanceCatalog()
    @Published private(set) var records: [ScanManifest] = []
    @Published private(set) var guidanceRecords: [GuidanceRecord] = []
    @Published private(set) var recordError: String?
    @Published private(set) var plans: [PerformancePlan] = []
    @Published private(set) var pins = LibraryPins()
    @Published private(set) var loading = false
    @Published var error: String?
    let catalogStore: PerformanceCatalogStore
    private let legacyPlacesStore: PlaceFolderStore
    let scans: ScanStore
    let planStore: PerformancePlanStore
    let guidanceRecordsStore: GuidanceRecordStore
    private let pinURL: URL
    private var refreshTask: Task<Void, Never>?
    var groups: (pinned: [ScanManifest], recent: [ScanManifest]) { pins.groups(records) }
    init(root: URL? = nil) {
        let docs=root ?? FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        catalogStore=PerformanceCatalogStore(root:docs.appendingPathComponent("Performances",isDirectory:true))
        legacyPlacesStore=PlaceFolderStore(root:docs.appendingPathComponent("PlaceFolders",isDirectory:true))
        scans=ScanStore(root:docs.appendingPathComponent("Scans",isDirectory:true))
        planStore=PerformancePlanStore(root:docs.appendingPathComponent("PerformancePlans",isDirectory:true))
        guidanceRecordsStore=GuidanceRecordStore(root:docs.appendingPathComponent("GuidanceRecords",isDirectory:true))
        pinURL=docs.appendingPathComponent("stage-pins.json")
        if FileManager.default.fileExists(atPath:pinURL.path) {
            do {pins=try JSONDecoder().decode(LibraryPins.self,from:Data(contentsOf:pinURL))}
            catch {self.error="고정한 무대 정보를 읽지 못했습니다: \(error.localizedDescription)"}
        }
    }
    func refresh() async {
        if let refreshTask {await refreshTask.value;return}
        let task=Task { @MainActor in await self.loadLibrary() }
        refreshTask=task
        await task.value
        refreshTask=nil
    }
    private func loadLibrary() async {
        loading=true; defer {loading=false}
        do {
            // Do not commit a partial migration when either source cannot be read.
            let loadedScans=try await scans.list()
            let loadedPlans=try await planStore.list()
            records=loadedScans;plans=loadedPlans
            let existing=try await catalogStore.load()
            if existing.migrationCompleted {catalog=existing}
            else {
                let places=try await legacyPlacesStore.load()
                catalog=try await catalogStore.migrateIfNeeded(scans:loadedScans,plans:loadedPlans,places:places)
            }
            // Only a successful complete scan listing can release references to removed bundles.
            catalog=try await catalogStore.reconcileScanReferences(validScanIDs:Set(loadedScans.map(\.id)))
            try await synchronizeLegacyPlaces()
        } catch {self.error="공연 목록을 불러오지 못했어요. 기존 자료는 유지됩니다. \(error.localizedDescription)"}
    }
    /// The catalog is authoritative after migration. A failed source sync is retried on refresh;
    /// the source's persisted revision guard prevents an older snapshot from undoing newer edits.
    private func synchronizeLegacyPlaces() async throws {
        let latest=try await catalogStore.load()
        catalog=latest
        _ = try await legacyPlacesStore.reconcileLegacySnapshot(latest)
    }
    func refreshGuidanceRecords() async {
        do {guidanceRecords=try await guidanceRecordsStore.list();recordError=nil}
        catch {recordError="안내 기록을 읽지 못했어요: \(error.localizedDescription)"}
    }
    func saveGuidanceRecord(_ record: GuidanceRecord) async throws {
        let saved=try await guidanceRecordsStore.save(record)
        guidanceRecords.removeAll {$0.id == saved.id}
        guidanceRecords.append(saved);guidanceRecords.sort {$0.finishedAt > $1.finishedAt}
    }
    func togglePin(_ id: UUID) {
        var updated=pins; updated.toggle(id)
        do {try JSONEncoder().encode(updated).write(to:pinURL,options:.atomic); pins=updated}
        catch {self.error="고정 상태를 저장하지 못했습니다: \(error.localizedDescription)"}
    }
    func renameStage(_ id: UUID, to name: String) async throws {
        let updated=try await scans.rename(id,to:name)
        if let index=records.firstIndex(where:{$0.id==id}) {records[index]=updated}
    }
    func deleteStage(_ id: UUID) async throws {
        try await scans.delete(id)
        records.removeAll {$0.id == id}
        pins.remove(id)
        // A later pin write failure must not leave a deleted stage in the legacy catalog.
        catalog=try await catalogStore.removeScanReferences(id)
        try await synchronizeLegacyPlaces()
        try JSONEncoder().encode(pins).write(to:pinURL,options:.atomic)
    }
    func deletePlan(_ id: UUID) async throws {
        let previous=plans.first {$0.id==id}
        try await planStore.delete(id)
        do {catalog=try await catalogStore.removePlanReferences(id)}
        catch {
            if let previous {try? await planStore.save(previous)}
            throw error
        }
        plans.removeAll {$0.id == id}
    }
    func savePlan(_ value: PerformancePlan) async throws {
        var plan=value; plan.updatedAt=Date(); plan.name=plan.name.trimmingCharacters(in:.whitespacesAndNewlines)
        try await planStore.save(plan); plans=try await planStore.list()
    }
}

// MARK: - Performance folders and venue classification
extension StageLibrary {
    var performanceFolders: [PerformanceFolder] {catalog.performances.sorted {$0.updatedAt>$1.updatedAt}}
    var unassignedScans: [ScanManifest] {records.filter {catalog.folder(for:$0.id)==nil}}
    func scans(in performanceID: UUID, venueID: UUID? = nil, includeAllVenues: Bool = true) -> [ScanManifest] {
        records.filter {
            guard let assignment=catalog.assignments[$0.id],assignment.performanceID==performanceID else {return false}
            return includeAllVenues || assignment.venueID==venueID
        }.sorted {$0.date>$1.date}
    }
    var voiceStageContexts: [UUID: [String]] {
        Dictionary(uniqueKeysWithValues:records.compactMap {record in
            guard let folder=catalog.folder(for:record.id) else {return nil}
            let names=[folder.name]+(catalog.venue(for:record.id).map {[$0.name]} ?? [])+(catalog.assignments[record.id]?.legacyPath ?? [])
            return (record.id,Array(Set(names)))
        })
    }
    @discardableResult func createPerformance(name: String, notes: String = "") async throws -> PerformanceFolder {
        let folder=PerformanceFolder(name:name,notes:notes)
        catalog=try await catalogStore.upsert(folder)
        return catalog.performances.first {$0.id==folder.id}!
    }
    func updatePerformance(id: UUID, name: String, notes: String) async throws {
        guard var folder=catalog.performances.first(where:{$0.id==id}) else {throw LabError.invalid("공연을 찾을 수 없어요.")}
        folder.name=name;folder.notes=notes;catalog=try await catalogStore.upsert(folder)
        try await synchronizeLegacyPlaces()
    }
    func deletePerformance(_ id: UUID) async throws {
        catalog=try await catalogStore.deletePerformance(id)
        try await synchronizeLegacyPlaces()
    }
    @discardableResult func createVenue(name: String, in performanceID: UUID) async throws -> PerformanceVenueTag {
        let tag=PerformanceVenueTag(name:name)
        catalog=try await catalogStore.upsertVenue(tag,in:performanceID)
        return catalog.performances.first {$0.id==performanceID}!.venues.first {$0.id==tag.id}!
    }
    func renameVenue(_ id: UUID, in performanceID: UUID, to name: String) async throws {
        guard catalog.performances.first(where:{$0.id==performanceID})?.venues.contains(where:{$0.id==id})==true else {throw LabError.invalid("공연·연습 공간을 찾을 수 없어요.")}
        catalog=try await catalogStore.upsertVenue(.init(id:id,name:name),in:performanceID)
        try await synchronizeLegacyPlaces()
    }
    func deleteVenue(_ id: UUID, in performanceID: UUID) async throws {
        catalog=try await catalogStore.deleteVenue(id,in:performanceID)
        try await synchronizeLegacyPlaces()
    }
    func assignScans(_ scanIDs: [UUID], to performanceID: UUID?, venueID: UUID? = nil) async throws {
        guard Set(scanIDs).isSubset(of:Set(records.map(\.id))) else {throw LabError.invalid("저장한 무대를 다시 불러와주세요.")}
        catalog=try await catalogStore.assign(scanIDs,to:performanceID,venueID:venueID)
        try await synchronizeLegacyPlaces()
    }
    func referencePlans(for performanceID: UUID?) -> [PerformancePlan] {
        catalog.referencePlans(among:plans,for:performanceID)
    }
    func referencePlan(for performanceID: UUID) -> PerformancePlan {
        if let plan=referencePlans(for:performanceID).first {return plan}
        var plan=PerformancePlan();plan.name="1번 씬";plan.isReferenceOnly=true;return plan
    }
    func savePerformancePlan(_ value: PerformancePlan, for performanceID: UUID) async throws {
        guard catalog.performances.contains(where:{$0.id==performanceID}) else {throw LabError.invalid("공연을 찾을 수 없어요.")}
        let previous=plans.first {$0.id==value.id}
        var plan=value;plan.updatedAt=Date();plan.name=plan.name.trimmingCharacters(in:.whitespacesAndNewlines)
        plan.isReferenceOnly=true
        try await planStore.save(plan)
        do {catalog=try await catalogStore.addReferencePlan(plan.id,for:performanceID)}
        catch {
            // Keep the preceding plan if the metadata transaction fails.
            if let previous {try? await planStore.save(previous)} else {try? await planStore.delete(plan.id)}
            throw error
        }
        plans.removeAll {$0.id==plan.id};plans.append(plan);plans.sort {$0.updatedAt>$1.updatedAt}
    }
    func removePerformancePlan(id: UUID, from performanceID: UUID) async throws {
        guard let folder=catalog.performances.first(where:{$0.id==performanceID}) else {
            throw LabError.invalid("공연을 찾을 수 없어요.")
        }
        // A multi-scene save can be retried after an earlier deletion already succeeded.
        // Never delete an independent plan that is not linked to this performance.
        guard folder.referencePlanIDs.contains(id) else {return}
        let shared=catalog.performances.contains {$0.id != performanceID && $0.referencePlanIDs.contains(id)}
        let previous=plans.first {$0.id==id}
        // A shared legacy plan remains available to its other performance folders.
        if !shared {try await planStore.delete(id)}
        do {catalog=try await catalogStore.removeReferencePlan(id,from:performanceID)}
        catch {
            if !shared,let previous {try? await planStore.save(previous)}
            throw error
        }
        if !shared {plans.removeAll {$0.id==id}}
    }
}
