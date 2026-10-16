import XCTest
@testable import HearIAmCore

final class GuidanceRecordTests: XCTestCase {
    private func completedRun() throws -> GuidanceRun {
        let route=try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2)],obstacles:[],allowsOutsideEndpoints:true)
        var run=GuidanceRun(stageID:UUID(),stageName:"C6 공연장",route:route)
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:route.points[0],headingDegrees:0,trackingValid:true))
        run.begin(at:Date(timeIntervalSince1970:1000),uptime:10)
        run.setRunning(false,uptime:20)
        run.setRunning(false,uptime:25) // Repeated pause cannot inflate duration.
        run.setRunning(true,uptime:40)
        run.setRunning(true,uptime:41)
        for point in 1...2 {
            for frame in 0...6 {
                _=guide.observe(time:Double(point)*1.4+Double(frame)*0.2,position:route.points[point],headingDegrees:0,trackingValid:true)
            }
        }
        XCTAssertEqual(guide.state,.completed)
        run.arrive(guide:guide,at:Date(timeIntervalSince1970:1040),uptime:50)
        run.setRunning(true,uptime:100) // Completion is immutable.
        return run
    }
    func testCompletedRecordExcludesPausesAndKeepsRouteSnapshot() throws {
        let record=try completedRun().record(completionSpoken:true,finishedAt:Date(timeIntervalSince1970:1050))
        XCTAssertEqual(record.activeSeconds,20)
        XCTAssertEqual(record.reachedPointCount,2)
        XCTAssertEqual(record.routeLength,4,accuracy:0.0001)
        XCTAssertEqual(record.stageName,"C6 공연장")
        XCTAssertEqual(try JSONDecoder().decode(GuidanceRecord.self,from:JSONEncoder().encode(record)),record)
    }
    func testAbortAndUnfinishedFinalSpeechCannotCreateRecord() throws {
        let route=try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2)],obstacles:[],allowsOutsideEndpoints:true)
        var run=GuidanceRun(stageID:UUID(),stageName:"중간 종료",route:route)
        run.begin(at:Date(),uptime:1)
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:route.points[0],headingDegrees:0,trackingValid:true))
        guide.pause();run.arrive(guide:guide,at:Date(),uptime:5)
        XCTAssertThrowsError(try run.record(completionSpoken:true,finishedAt:Date()))
        XCTAssertThrowsError(try completedRun().record(completionSpoken:false,finishedAt:Date()))
    }
    func testAtomicPersistenceRetryDeduplicationAndNewestFirst() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=GuidanceRecordStore(root:root)
        let run=try completedRun()
        let first=try run.record(completionSpoken:true,finishedAt:Date(timeIntervalSince1970:1050))
        try await store.save(first)
        let retry=try run.record(completionSpoken:true,finishedAt:Date(timeIntervalSince1970:1090))
        let saved=try await store.save(retry)
        XCTAssertEqual(saved,first)
        let second=try completedRun().record(completionSpoken:true,finishedAt:Date(timeIntervalSince1970:1100))
        try await store.save(second)
        let reloaded=try await GuidanceRecordStore(root:root).list()
        XCTAssertEqual(reloaded.map(\.id),[second.id,first.id])
    }
    func testFailedSaveCanRetryWithoutLosingCompletion() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        try Data("not a directory".utf8).write(to:root)
        let store=GuidanceRecordStore(root:root)
        let record=try completedRun().record(completionSpoken:true,finishedAt:Date())
        do {try await store.save(record);XCTFail("Must surface write failure")} catch {}
        try FileManager.default.removeItem(at:root)
        try await store.save(record)
        let saved=try await store.list();XCTAssertEqual(saved,[record])
    }
    func testCorruptRecordIsReported() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=GuidanceRecordStore(root:root)
        let record=try completedRun().record(completionSpoken:true,finishedAt:Date())
        try await store.save(record)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any])
        json["activeSeconds"] = -1
        try JSONSerialization.data(withJSONObject:json).write(to:root.appendingPathComponent(record.id.uuidString+".json"))
        do {_=try await store.list();XCTFail("Must reject invalid duration")} catch {}
    }
}
