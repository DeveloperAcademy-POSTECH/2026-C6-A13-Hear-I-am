import Foundation
import SwiftUI
import HearIAmCore

@MainActor final class StageLibrary: ObservableObject {
    @Published private(set) var records: [ScanManifest] = []
    @Published private(set) var guidanceRecords: [GuidanceRecord] = []
    @Published private(set) var recordError: String?
    @Published private(set) var plans: [PerformancePlan] = []
    @Published private(set) var pins = LibraryPins()
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var venues: [SpaceVenue] = []
    @Published var baseScans: [ScanManifest] = []
    @Published var spacePreferences = SpaceLibraryPreferences()
    var spacePreferencesReadable = true
    let spacePreferencesURL: URL
    let scans: ScanStore
    let planStore: PerformancePlanStore
    let guidanceRecordsStore: GuidanceRecordStore
    private let pinURL: URL
    var groups: (pinned: [ScanManifest], recent: [ScanManifest]) { pins.groups(records) }
    init() {
        let docs=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        scans=ScanStore(root:docs.appendingPathComponent("Scans",isDirectory:true))
        planStore=PerformancePlanStore(root:docs.appendingPathComponent("PerformancePlans",isDirectory:true))
        guidanceRecordsStore=GuidanceRecordStore(root:docs.appendingPathComponent("GuidanceRecords",isDirectory:true))
        pinURL=docs.appendingPathComponent("stage-pins.json")
        spacePreferencesURL=docs.appendingPathComponent("space-library.json")
        loadSpaces()
        if FileManager.default.fileExists(atPath:pinURL.path) {
            do {pins=try JSONDecoder().decode(LibraryPins.self,from:Data(contentsOf:pinURL))}
            catch {self.error="고정한 무대 정보를 읽지 못했습니다: \(error.localizedDescription)"}
        }
    }
    func refresh() async {
        loading=true; defer {loading=false}
        do {let all=try await scans.list(); records=all.filter {$0.space?.purpose != .base}; baseScans=all.filter {$0.space?.purpose == .base}} catch {self.error="무대 목록: \(error.localizedDescription)"}
        do {plans=try await planStore.list()} catch {self.error="공연 사전 저장: \(error.localizedDescription)"}
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
        try JSONEncoder().encode(pins).write(to:pinURL,options:.atomic)
    }
    func deletePlan(_ id: UUID) async throws {
        try await planStore.delete(id)
        plans.removeAll {$0.id == id}
    }
    func savePlan(_ value: PerformancePlan) async throws {
        var plan=value; plan.updatedAt=Date(); plan.name=plan.name.trimmingCharacters(in:.whitespacesAndNewlines)
        try await planStore.save(plan); plans=try await planStore.list()
    }
}
