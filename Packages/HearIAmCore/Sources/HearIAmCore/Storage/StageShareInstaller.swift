import Foundation

/// Where the receiver puts what they chose from a shared file.
public struct StageShareChoices: Equatable, Sendable {
    public enum Performance: Equatable, Sendable { case existing(UUID), new(String) }
    public enum Venue: Equatable, Sendable { case existing(UUID), new(String) }
    public var performance: Performance
    /// Where each shared space goes. The nil key holds stages the sender kept without a space; since #181 every
    /// stage here has a space, so those need one too.
    public var venues: [UUID?: Venue]
    public var sceneIDs: Set<UUID>
    public var includePlans: Bool
    /// Stages already on this phone that may be replaced. Any other stage already here is skipped.
    public var replacing: Set<UUID>
    public init(performance: Performance, venues: [UUID?: Venue], sceneIDs: Set<UUID>, includePlans: Bool, replacing: Set<UUID> = []) {
        self.performance=performance; self.venues=venues; self.sceneIDs=sceneIDs; self.includePlans=includePlans; self.replacing=replacing
    }

    /// A new performance under the sender's name (numbered when taken), each space under its own name, everything chosen.
    public static func suggested(for index: StageShareIndex, catalog: PerformanceCatalog) -> StageShareChoices {
        let name=StageShare.availableName(index.performanceName,taken:catalog.performances.map(\.name))
        var choices=StageShareChoices(performance:.new(name),venues:[:],sceneIDs:Set(index.scenes.map(\.id)),includePlans:!index.planIDs.isEmpty)
        choices.suggestVenues(for:index,catalog:catalog)
        return choices
    }
    /// In an existing performance a space of the same name is reused; otherwise each space is made new.
    public mutating func suggestVenues(for index: StageShareIndex, catalog: PerformanceCatalog) {
        var existing=[PerformanceVenueTag]()
        if case let .existing(id)=performance { existing=catalog.performances.first {$0.id==id}?.venues ?? [] }
        venues=[:]
        for key in Set(index.scenes.map(\.venueID)) {
            let name=key.flatMap {id in index.venues.first {$0.id==id}?.name} ?? L("받은 장면")
            if let same=existing.first(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(name)}) { venues[key] = .existing(same.id) }
            else { venues[key] = .new(name) }
        }
    }
}

public struct StageShareResult: Equatable, Sendable {
    public let performanceID: UUID
    public let installed: [UUID]
    public let skipped: [UUID]
    public let planCount: Int
}

extension StageShare {
    /// `name`, or `name 2`, `name 3`… when a performance already uses it.
    public static func availableName(_ name: String, taken: [String]) -> String {
        let base=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(76))
        let used=Set(taken.map(PlaceSearch.normalized))
        if !used.contains(PlaceSearch.normalized(base)) { return base }
        var number=2
        while used.contains(PlaceSearch.normalized("\(base) \(number)")) { number+=1 }
        return "\(base) \(number)"
    }
}

extension ScanStore {
    public func contains(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath:root.appendingPathComponent(id.uuidString,isDirectory:true).path)
    }
    /// Moves a staged, already checked stage into place. A replaced stage is kept aside until the new one is in,
    /// so a failure puts it back.
    func install(from staged: URL, replacing: Bool) throws -> ScanManifest {
        let fm=FileManager.default
        let manifest=try JSONDecoder().decode(ScanManifest.self,from:Data(contentsOf:staged.appendingPathComponent("manifest.json")))
        guard staged.lastPathComponent==manifest.id.uuidString else { throw StageShareArchive.invalid() }
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let dest=root.appendingPathComponent(manifest.id.uuidString,isDirectory:true)
        if fm.fileExists(atPath:dest.path) {
            guard replacing else { throw LabError.invalid(L("같은 장면이 이미 있어요.")) }
            let old=root.appendingPathComponent(".replacing-"+manifest.id.uuidString,isDirectory:true)
            if fm.fileExists(atPath:old.path) { try fm.removeItem(at:old) }
            try fm.moveItem(at:dest,to:old)
            do { try fm.moveItem(at:staged,to:dest) }
            catch { try? fm.moveItem(at:old,to:dest); throw error }
            try? fm.removeItem(at:old)
        } else {
            try fm.moveItem(at:staged,to:dest)
        }
        return try load(manifest.id).manifest
    }
    /// Run once at launch: removes an import that stopped part way and puts back a stage whose replacement stopped
    /// before the new one was in place.
    public func recoverInterruptedImports() throws {
        let fm=FileManager.default
        guard fm.fileExists(atPath:root.path) else { return }
        for url in try fm.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) {
            let name=url.lastPathComponent
            if name.hasPrefix(".importing-") { try fm.removeItem(at:url) }
            else if name.hasPrefix(".replacing-"), let id=UUID(uuidString:String(name.dropFirst(".replacing-".count))) {
                let dest=root.appendingPathComponent(id.uuidString,isDirectory:true)
                if fm.fileExists(atPath:dest.path) { try fm.removeItem(at:url) } else { try fm.moveItem(at:url,to:dest) }
            }
        }
    }
}

public enum StageShareInstaller {
    /// Saves the chosen stages and routes where the receiver chose. Each stage is checked in a hidden folder beside
    /// the saved stages and moved in only when it passes; the hidden folder is removed whatever happens.
    public static func install(_ file: StageShareFile, choices: StageShareChoices, scans: ScanStore,
                               plans: PerformancePlanStore, catalog: PerformanceCatalogStore) async throws -> StageShareResult {
        let index=file.index
        let chosen=index.scenes.filter {choices.sceneIDs.contains($0.id)}
        guard !chosen.isEmpty, chosen.count==choices.sceneIDs.count else { throw LabError.invalid(L("저장할 장면을 골라주세요.")) }
        guard chosen.allSatisfy({choices.venues[$0.venueID] != nil}) else { throw LabError.invalid(L("장면을 저장할 공간을 골라주세요.")) }
        // Read the routes first so a broken one stops the import before anything is saved.
        let sharedPlans=choices.includePlans && index.kind == .performance ? try file.plans() : []

        var current=try await catalog.load()
        let performanceID: UUID
        switch choices.performance {
        case .existing(let id):
            guard current.performances.contains(where:{$0.id==id}) else { throw LabError.invalid(L("공연을 찾을 수 없어요.")) }
            performanceID=id
        case .new(let name):
            let folder=PerformanceFolder(name:name)
            current=try await catalog.upsert(folder)
            performanceID=folder.id
        }

        var venueIDs=[UUID?: UUID]()
        let keys=index.venues.map {Optional($0.id)}+[nil]
        for key in keys where chosen.contains(where:{$0.venueID==key}) {
            let existing=current.performances.first {$0.id==performanceID}?.venues ?? []
            switch choices.venues[key]! {
            case .existing(let id):
                guard existing.contains(where:{$0.id==id}) else { throw LabError.invalid(L("공연·연습 공간을 찾을 수 없어요.")) }
                venueIDs[key]=id
            case .new(let name):
                let trimmed=name.trimmingCharacters(in:.whitespacesAndNewlines)
                if let same=existing.first(where:{PlaceSearch.normalized($0.name)==PlaceSearch.normalized(trimmed)}) { venueIDs[key]=same.id }
                else {
                    let tag=PerformanceVenueTag(name:trimmed)
                    current=try await catalog.upsertVenue(tag,in:performanceID)
                    venueIDs[key]=tag.id
                }
            }
        }

        let fm=FileManager.default
        let staging=scans.root.appendingPathComponent(".importing-"+UUID().uuidString,isDirectory:true)
        defer { try? fm.removeItem(at:staging) }
        var installed=[UUID](), skipped=[UUID]()
        for scene in chosen {
            let exists=await scans.contains(scene.id)
            if exists && !choices.replacing.contains(scene.id) { skipped.append(scene.id); continue }
            _ = try await file.stageScene(scene.id,in:staging)
            _ = try await scans.install(from:staging.appendingPathComponent(scene.id.uuidString,isDirectory:true),replacing:exists)
            current=try await catalog.assign([scene.id],to:performanceID,venueID:venueIDs[scene.venueID])
            installed.append(scene.id)
        }

        // Routes get new IDs: the sender's IDs could match a route already here.
        for var plan in sharedPlans {
            plan.id=UUID(); plan.isReferenceOnly=true; plan.updatedAt=Date()
            try await plans.save(plan)
            current=try await catalog.addReferencePlan(plan.id,for:performanceID)
        }
        return StageShareResult(performanceID:performanceID,installed:installed,skipped:skipped,planCount:sharedPlans.count)
    }
}
