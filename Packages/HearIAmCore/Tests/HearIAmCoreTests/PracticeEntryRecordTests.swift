import XCTest
@testable import HearIAmCore

/// Completing a direct P1 practice must not claim that preceding chair/stair points were visited.
final class PracticeEntryRecordTests: XCTestCase {
    private func completedPractice(replay: Bool) throws -> GuidanceRecord {
        let chair=try StageObstacle(name:"의자",kind:.platform,vertices:[.init(2.5,1.5),.init(3.5,1.5),.init(3.5,2.5),.init(2.5,2.5)])
        let route=try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2),.init(7,2)],obstacles:[chair],pointHeights:[0,0.4,0,0])
        let footprint=try ScannedFootprint(meshes:[ScannedFootprintTests.rectangle(-4,-4,16,12)],area:PerformancePlan.area)
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true,pausesForPositionIssues:false)
        var run=GuidanceRun(stageID:UUID(),stageName:"의자 앞을 생략한 연습",route:route)
        let date=Date(timeIntervalSince1970:1000),origin=FloorPoint(5,5)
        XCTAssertTrue(try guide.startPractice(position:origin,headingDegrees:0,trackingValid:true,footprint:footprint))
        run.begin(at:date,uptime:10)
        if replay {run.capture(position:origin,heading:0,targetIndex:guide.targetIndex,status:.guiding,uptime:10,force:true)}
        XCTAssertEqual(guide.targetIndex,2)
        for i in 0...4 {
            let time=10.25+Double(i)/4
            _=guide.observe(time:time,position:route.points[2],headingDegrees:0,trackingValid:true)
            if replay {run.capture(position:route.points[2],heading:0,targetIndex:guide.targetIndex,status:.guiding,uptime:time,force:true)}
        }
        XCTAssertEqual(guide.targetIndex,3)
        guide.pause();run.setRunning(false,uptime:11.25)
        XCTAssertTrue(guide.resume(position:route.points[2],trackingValid:true))
        run.setRunning(true,uptime:12)
        for i in 0...4 {
            let time=12+Double(i)/4
            _=guide.observe(time:time,position:route.points[3],headingDegrees:0,trackingValid:true)
            if replay {run.capture(position:route.points[3],heading:0,targetIndex:guide.targetIndex,status:.guiding,uptime:time,force:true)}
        }
        XCTAssertEqual(guide.state,.completed);XCTAssertEqual(guide.route,route)
        run.arrive(guide:guide,at:date.addingTimeInterval(3),uptime:13)
        return try run.record(completionSpoken:true,finishedAt:date.addingTimeInterval(4))
    }

    func testPracticeRecordCountsOnlyP1AndDestinationWithOrWithoutReplay() throws {
        for replay in [false,true] {
            let record=try completedPractice(replay:replay)
            XCTAssertEqual(record.route.pointNames,["출발","의자1","P1","도착"])
            XCTAssertEqual(record.firstGuidedPointIndex,2)
            XCTAssertEqual(record.practiceOrigin,.init(5,5))
            XCTAssertEqual(record.guidancePath,[.init(5,5),.init(5,2),.init(7,2)])
            XCTAssertEqual(record.guidancePathHeights,[0,0,0])
            XCTAssertEqual(record.guidanceRouteLength,5,accuracy:0.001)
            XCTAssertEqual(record.reachedPointCount,2)
            XCTAssertEqual(record.routeLength,6,accuracy:0.001,"The saved standard route remains unchanged")
            XCTAssertEqual(record.activeSeconds,2.25,accuracy:0.001)
            let restored=try JSONDecoder().decode(GuidanceRecord.self,from:JSONEncoder().encode(record))
            XCTAssertEqual(restored,record);XCTAssertEqual(restored.reachedPointCount,2)
        }
    }

    func testSavedReplayRetainsActualFirstTargetAndCorrectSummaryCount() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let record=try completedPractice(replay:true)
        let store=GuidanceRecordStore(root:root)
        try await store.save(record)
        let records=try await GuidanceRecordStore(root:root).list()
        let restored=try XCTUnwrap(records.first)
        XCTAssertEqual(restored.reachedPointCount,2,"List, detail and replay summary all use this count")
        XCTAssertEqual(restored.replay?.samples.first?.targetIndex,2)
        XCTAssertFalse(try XCTUnwrap(restored.replay).samples.contains {$0.targetIndex == 1})
        XCTAssertEqual(restored.replay?.pose(at:0)?.targetIndex,2)
        XCTAssertEqual(restored.replay?.pose(at:3)?.targetIndex,3)
        XCTAssertEqual(restored.replay?.pose(at:3)?.position,restored.route.points[3])
        XCTAssertEqual(restored.guidancePath,[.init(5,5),.init(5,2),.init(7,2)])
        XCTAssertFalse(restored.guidancePath.contains(restored.route.points[1]))
        let analysis=GuidanceReplayAnalysis(replay:try XCTUnwrap(restored.replay),route:restored.route,guidancePath:restored.guidancePath)
        XCTAssertEqual(analysis.maximumDeviation,0,accuracy:0.001)
        XCTAssertTrue(analysis.events.contains {$0.kind == .arrival(2)})
        XCTAssertFalse(analysis.events.contains {$0.kind == .arrival(1)})
    }

    func testLegacyRecordsWithoutEntryMetadataKeepFullRouteCount() throws {
        for replay in [false,true] {
            let record=try completedPractice(replay:replay)
            var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any])
            json.removeValue(forKey:"firstGuidedPointIndex")
            json.removeValue(forKey:"practiceOrigin")
            let legacy=try JSONDecoder().decode(GuidanceRecord.self,from:JSONSerialization.data(withJSONObject:json))
            try legacy.validate()
            XCTAssertNil(legacy.firstGuidedPointIndex);XCTAssertNil(legacy.practiceOrigin)
            XCTAssertEqual(legacy.guidancePath,legacy.route.points)
            XCTAssertEqual(legacy.guidanceRouteLength,legacy.routeLength)
            XCTAssertEqual(legacy.reachedPointCount,3)
            XCTAssertEqual(legacy.version,replay ? 2 : 1)
        }
    }

    func testPracticeDeviationUsesItsEntryAndDoesNotTreatSkippedSegmentAsValid() throws {
        let record=try completedPractice(replay:true)
        let p=FloorPoint(5,4),skipped=record.route.points[1]
        XCTAssertEqual(GuidanceReplayAnalysis.deviation(p,points:record.guidancePath),0,accuracy:0.001)
        XCTAssertEqual(GuidanceReplayAnalysis.deviation(p,route:record.route),2,accuracy:0.001)
        XCTAssertEqual(GuidanceReplayAnalysis.deviation(skipped,points:record.guidancePath),2,accuracy:0.001)
    }

    func testInvalidEntryMetadataAndConflictingRetryAreRejected() async throws {
        let record=try completedPractice(replay:true)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any])
        for invalid in [0,-1,record.route.points.count] {
            json["firstGuidedPointIndex"]=invalid
            let invalidRecord=try JSONDecoder().decode(GuidanceRecord.self,from:JSONSerialization.data(withJSONObject:json))
            XCTAssertThrowsError(try invalidRecord.validate())
        }
        json["firstGuidedPointIndex"]=2
        json.removeValue(forKey:"practiceOrigin")
        let incomplete=try JSONDecoder().decode(GuidanceRecord.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertThrowsError(try incomplete.validate())
        json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any])
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=GuidanceRecordStore(root:root)
        try await store.save(record)
        json["firstGuidedPointIndex"]=1
        let conflicting=try JSONDecoder().decode(GuidanceRecord.self,from:JSONSerialization.data(withJSONObject:json))
        do {_=try await store.save(conflicting);XCTFail("Retry cannot change which points were visited")} catch {}
        let stored=try await store.list();XCTAssertEqual(stored.first,record)
    }
}
