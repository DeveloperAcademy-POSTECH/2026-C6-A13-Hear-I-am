import XCTest
@testable import HearIAmCore

final class StageShareTests: XCTestCase {
    private var directories=[URL]()
    override func tearDown() { for url in directories { try? FileManager.default.removeItem(at:url) } }
    private func folder() -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("stage-share-"+UUID().uuidString,isDirectory:true)
        directories.append(url); return url
    }
    private func scratchFile() -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("stage-share-"+UUID().uuidString+".heariam")
        directories.append(url); return url
    }

    /// A stage with two checkpoints, a mesh large enough to compress and one photo.
    private func saveStage(_ store: ScanStore, name: String, photoBytes: Data = Data(repeating:7,count:900)) async throws -> ScanManifest {
        let area=PerformancePlan.area
        let route=try StageRoute(area:area,points:[.init(2,2),.init(4,2),.init(6,2)],obstacles:[])
        let vertices=(0..<300).map {Point3(Double($0%10)*0.1,0,Double($0/10)*0.1)}
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:vertices,indices:[0,1,2])
        let photosDir=folder(); try FileManager.default.createDirectory(at:photosDir,withIntermediateDirectories:true)
        let image=photosDir.appendingPathComponent("a.jpg"), thumb=photosDir.appendingPathComponent("b.jpg")
        try photoBytes.write(to:image); try Data(repeating:3,count:100).write(to:thumb)
        let photo=ScanPhoto(capturedAt:Date(),frameTimestamp:1,cameraTransform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],pixelWidth:10,pixelHeight:10,
                            imageHash:ScanStore.hash(photoBytes),thumbnailHash:ScanStore.hash(Data(repeating:3,count:100)))
        return try await store.save(id:UUID(),name:name,frame:try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1))),
                                    checkpoint:area.world(.init(3,4)),worldMap:Data((0..<5000).map {_ in UInt8.random(in:0...255)}),meshes:[mesh],device:"test",appVersion:"test",
                                    route:route,photos:[.init(photo:photo,imageURL:image,thumbnailURL:thumb)],secondCheckpoint:area.world(.init(7,4)))
    }
    private func plan() throws -> PerformancePlan {
        var value=PerformancePlan(); value.name="1번 씬"; value.isReferenceOnly=true
        try value.append(.init(1,1)); try value.append(.init(4,3)); try value.finishRoute()
        return value
    }
    private func migratedCatalog(_ root: URL) async throws -> PerformanceCatalogStore {
        let store=PerformanceCatalogStore(root:root)
        _ = try await store.migrateIfNeeded(scans:[],plans:[],places:PlaceFolderIndex())
        return store
    }
    /// Sender: a performance with two spaces, three stages and a route, written to a file.
    private func sharedPerformance() async throws -> (url: URL, index: StageShareIndex, stages: [ScanManifest], plan: PerformancePlan) {
        let root=folder(), scans=ScanStore(root:root.appendingPathComponent("Scans"))
        let a=try await saveStage(scans,name:"1번 씬"), b=try await saveStage(scans,name:"2번 씬"), c=try await saveStage(scans,name:"오프닝")
        let hall=StageShareIndex.Venue(id:UUID(),name:"효자 아트홀"), center=StageShareIndex.Venue(id:UUID(),name:"예술의 전당")
        let route=try plan(), url=root.appendingPathComponent("Lion King.heariam")
        let index=try StageShare.write(kind:.performance,performanceName:"Lion King",venues:[hall,center],
                                       scenes:[.init(id:a.id,name:a.name,venueID:hall.id),.init(id:b.id,name:b.name,venueID:hall.id),.init(id:c.id,name:c.name,venueID:nil)],
                                       plans:[route],appVersion:"1.0.3",scansRoot:scans.root,to:url)
        return (url,index,[a,b,c],route)
    }

    func testPerformanceRoundTripsIntoNewPerformanceWithItsSpacesAndRoutes() async throws {
        let shared=try await sharedPerformance()
        let file=try StageShareFile(url:shared.url)
        XCTAssertEqual(file.index,shared.index)
        XCTAssertGreaterThan(file.bytes(of:shared.stages[0].id),0)

        let root=folder(), scans=ScanStore(root:root.appendingPathComponent("Scans"))
        let plans=PerformancePlanStore(root:root.appendingPathComponent("Plans")), catalog=try await migratedCatalog(root.appendingPathComponent("Catalog"))
        var choices=StageShareChoices.suggested(for:file.index,catalog:try await catalog.load())
        XCTAssertEqual(choices.performance,.new("Lion King"))
        XCTAssertEqual(choices.venues[nil],.new("받은 장면"))
        choices.sceneIDs.remove(shared.stages[1].id)

        let result=try await StageShareInstaller.install(file,choices:choices,scans:scans,plans:plans,catalog:catalog)
        XCTAssertEqual(Set(result.installed),[shared.stages[0].id,shared.stages[2].id])
        XCTAssertEqual(result.planCount,1)
        let saved=try await scans.list()
        XCTAssertEqual(Set(saved.map(\.id)),Set(result.installed), "a stage that was not chosen is not saved")
        let loaded=try await scans.load(shared.stages[0].id)
        XCTAssertTrue(loaded.manifest.supportsAlignment)
        let photo=try await scans.photoData(scanID:loaded.manifest.id,photoID:loaded.manifest.photos[0].id,thumbnail:false)
        XCTAssertEqual(photo,Data(repeating:7,count:900))

        let value=try await catalog.load(), performance=try XCTUnwrap(value.performances.first {$0.id==result.performanceID})
        XCTAssertEqual(performance.name,"Lion King")
        XCTAssertEqual(Set(performance.venues.map(\.name)),["효자 아트홀","받은 장면"])
        XCTAssertEqual(value.venue(for:shared.stages[0].id)?.name,"효자 아트홀")
        XCTAssertEqual(value.venue(for:shared.stages[2].id)?.name,"받은 장면")
        let savedPlans=try await plans.list()
        XCTAssertEqual(savedPlans.count,1)
        XCTAssertNotEqual(savedPlans[0].id,shared.plan.id, "a received route gets its own ID")
        XCTAssertEqual(performance.referencePlanIDs,[savedPlans[0].id])

        let hidden=try FileManager.default.contentsOfDirectory(atPath:scans.root.path).filter {$0.hasPrefix(".")}
        XCTAssertEqual(hidden,[], "nothing from the import is left behind")
    }

    func testExistingPerformanceReusesSameNamedSpaceAndSkipsOrReplacesExistingStage() async throws {
        let shared=try await sharedPerformance()
        let file=try StageShareFile(url:shared.url)
        let root=folder(), scans=ScanStore(root:root.appendingPathComponent("Scans"))
        let plans=PerformancePlanStore(root:root.appendingPathComponent("Plans")), catalog=try await migratedCatalog(root.appendingPathComponent("Catalog"))
        let mine=PerformanceFolder(name:"소말리아 해적선"), hall=PerformanceVenueTag(name:"효자  아트홀")
        _ = try await catalog.upsert(mine); _ = try await catalog.upsertVenue(hall,in:mine.id)

        var choices=StageShareChoices(performance:.existing(mine.id),venues:[:],sceneIDs:[shared.stages[0].id],includePlans:false)
        choices.suggestVenues(for:file.index,catalog:try await catalog.load())
        XCTAssertEqual(choices.venues[file.index.scenes[0].venueID],.existing(hall.id))
        let first=try await StageShareInstaller.install(file,choices:choices,scans:scans,plans:plans,catalog:catalog)
        XCTAssertEqual(first.installed,[shared.stages[0].id])

        let renamed=try await scans.rename(shared.stages[0].id,to:"내가 바꾼 이름")
        let again=try await StageShareInstaller.install(file,choices:choices,scans:scans,plans:plans,catalog:catalog)
        XCTAssertEqual(again.skipped,[shared.stages[0].id])
        let kept=try await scans.list().first
        XCTAssertEqual(kept?.name,renamed.name)

        choices.replacing=[shared.stages[0].id]
        let replaced=try await StageShareInstaller.install(file,choices:choices,scans:scans,plans:plans,catalog:catalog)
        XCTAssertEqual(replaced.installed,[shared.stages[0].id])
        let now=try await scans.list()
        XCTAssertEqual(now.map(\.name),["1번 씬"])
        let catalogNow=try await catalog.load()
        XCTAssertEqual(catalogNow.performances.first {$0.id==mine.id}?.venues.count,1)
        let savedPlans=try await plans.list()
        XCTAssertEqual(savedPlans.count,0)
    }

    func testSingleSceneFileHoldsOneStageAndNoRoutes() async throws {
        let root=folder(), scans=ScanStore(root:root.appendingPathComponent("Scans"))
        let stage=try await saveStage(scans,name:"1번 씬"), venue=StageShareIndex.Venue(id:UUID(),name:"효자 아트홀")
        let url=root.appendingPathComponent(StageShare.fileName(for:"1번 씬"))
        XCTAssertEqual(url.lastPathComponent,"1번 씬.heariam")
        try StageShare.write(kind:.scene,performanceName:"Lion King",venues:[venue],scenes:[.init(id:stage.id,name:stage.name,venueID:venue.id)],
                             plans:[],appVersion:"1.0.3",scansRoot:scans.root,to:url)
        let file=try StageShareFile(url:url)
        XCTAssertEqual(file.index.kind,.scene); XCTAssertEqual(file.index.scenes.count,1); XCTAssertEqual(try file.plans().count,0)
        XCTAssertThrowsError(try StageShare.write(kind:.scene,performanceName:"Lion King",venues:[venue],
            scenes:[.init(id:stage.id,name:stage.name,venueID:venue.id),.init(id:UUID(),name:"다른",venueID:venue.id)],
            plans:[],appVersion:"1",scansRoot:scans.root,to:root.appendingPathComponent("x.heariam")))
    }

    func testOneCheckpointStageIsNotShared() async throws {
        let root=folder(), scans=ScanStore(root:root.appendingPathComponent("Scans")), area=PerformancePlan.area
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[Point3(0,0,0),Point3(1,0,0),Point3(0,0,1)],indices:[0,1,2])
        let old=try await scans.save(id:UUID(),name:"이전 장면",frame:try StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1))),
                                     checkpoint:area.world(.init(3,4)),worldMap:Data([1,2,3]),meshes:[mesh],device:"t",appVersion:"t")
        XCTAssertFalse(StageShare.isShareable(old))
        XCTAssertThrowsError(try StageShare.write(kind:.scene,performanceName:"공연",venues:[],scenes:[.init(id:old.id,name:old.name,venueID:nil)],
                                                  plans:[],appVersion:"1",scansRoot:scans.root,to:root.appendingPathComponent("old.heariam")))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("old.heariam").path), "a failed file is removed")
    }

    func testDamagedFilesAreRefusedBeforeAnythingIsSaved() async throws {
        let shared=try await sharedPerformance()
        var bytes=try Data(contentsOf:shared.url)

        // Not a share file at all.
        let junk=scratchFile(); try Data("hello".utf8).write(to:junk)
        XCTAssertThrowsError(try StageShareFile(url:junk))

        // Cut short.
        let short=scratchFile(); try bytes.prefix(bytes.count/2).write(to:short)
        XCTAssertThrowsError(try StageShareFile(url:short))

        // A changed byte in the world map is caught by its hash when the stage is checked.
        let file=try StageShareFile(url:shared.url)
        let mapPath="scenes/\(shared.stages[0].id.uuidString)/worldmap.bin"
        let reader=try StageShareArchive.Reader(url:shared.url), entry=try XCTUnwrap(reader.entries[mapPath])
        XCTAssertFalse(entry.compressed)
        bytes[Int(entry.offset)] ^= 0xFF
        let tampered=scratchFile(); try bytes.write(to:tampered)
        let opened=try StageShareFile(url:tampered)
        XCTAssertEqual(opened.index,file.index)
        let root=folder(), scans=ScanStore(root:root.appendingPathComponent("Scans"))
        let catalog=try await migratedCatalog(root.appendingPathComponent("Catalog"))
        let choices=StageShareChoices.suggested(for:opened.index,catalog:try await catalog.load())
        do {
            _ = try await StageShareInstaller.install(opened,choices:choices,scans:scans,plans:PerformancePlanStore(root:root.appendingPathComponent("Plans")),catalog:catalog)
            XCTFail("a damaged stage must not be saved")
        } catch {}
        let saved=try await scans.list()
        XCTAssertEqual(saved.count,0)
        let hidden=(try? FileManager.default.contentsOfDirectory(atPath:scans.root.path)) ?? []
        XCTAssertEqual(hidden,[])
    }

    func testArchiveRejectsPathsOutsideTheStageShapes() throws {
        for path in ["../evil","/abs","scenes/x/manifest.json","scenes/\(UUID().uuidString)/../../a","scenes/\(UUID().uuidString)/photos/a.png",
                     "plans/abc.json","share.json/x","Scenes/\(UUID().uuidString)/mesh.json"] {
            XCTAssertFalse(StageShareArchive.isAllowed(path),path)
        }
        let id=UUID().uuidString
        for path in ["share.json","plans/\(id).json","scenes/\(id)/mesh.json","scenes/\(id)/photos/\(id).jpg","scenes/\(id)/photos/\(id)-thumb.jpg"] {
            XCTAssertTrue(StageShareArchive.isAllowed(path),path)
        }
        let url=scratchFile()
        let writer=try StageShareArchive.Writer(url:url)
        XCTAssertThrowsError(try writer.add(Data([1]),at:"../evil"))
    }

    func testDecompressionStopsAtDeclaredSize() throws {
        let data=Data(repeating:0,count:100_000), packed=try XCTUnwrap(StageShareArchive.compress(data))
        XCTAssertLessThan(packed.count,data.count)
        XCTAssertEqual(try StageShareArchive.decompress(packed,rawSize:data.count),data)
        XCTAssertThrowsError(try StageShareArchive.decompress(packed,rawSize:1_000), "a stream larger than it says is refused")
    }

    func testInterruptedReplacementIsPutBackAndImportLeftoversRemoved() async throws {
        let root=folder(), scans=ScanStore(root:root)
        let stage=try await saveStage(scans,name:"1번 씬")
        let fm=FileManager.default
        try fm.moveItem(at:root.appendingPathComponent(stage.id.uuidString),to:root.appendingPathComponent(".replacing-"+stage.id.uuidString))
        try fm.createDirectory(at:root.appendingPathComponent(".importing-x/y"),withIntermediateDirectories:true)
        try await scans.recoverInterruptedImports()
        let listed=try await scans.list()
        XCTAssertEqual(listed.map(\.id),[stage.id])
        XCTAssertEqual(try fm.contentsOfDirectory(atPath:root.path).filter {$0.hasPrefix(".")},[])
    }

    func testAvailableNameNumbersTakenNames() {
        XCTAssertEqual(StageShare.availableName("Lion King",taken:[]),"Lion King")
        XCTAssertEqual(StageShare.availableName("Lion King",taken:["lion  king","Lion King 2"]),"Lion King 3")
    }
}
