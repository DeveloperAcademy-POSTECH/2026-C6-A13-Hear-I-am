import XCTest
@testable import HearIAmCore

final class GuidanceReplayTests: XCTestCase {
    func route() throws -> StageRoute {
        try StageRoute(area:PerformancePlan.area,points:[.init(1,2),.init(3,2),.init(5,2)],obstacles:[],allowsOutsideEndpoints:true)
    }
    func sample(_ t: Double,_ x: Double?,_ y: Double=2,_ heading: Double=0,_ target: Int=1,_ status: GuidanceReplayStatus = .guiding) -> GuidanceReplaySample {
        .init(time:t,position:x.map {FloorPoint($0,y)},heading:x == nil ? nil : heading,targetIndex:target,status:x == nil ? .untracked : status)
    }
    func record(_ replay: GuidanceReplay?,id: UUID = UUID()) throws -> GuidanceRecord {
        GuidanceRecord(version:replay == nil ? 1:2,id:id,stageID:UUID(),stageName:"검증 무대",route:try route(),
            startedAt:Date(timeIntervalSince1970:1000),completedAt:Date(timeIntervalSince1970:1010),
            finishedAt:Date(timeIntervalSince1970:1011),activeSeconds:8,replay:replay)
    }
    func testInterpolationAndShortestHeadingAcross180() throws {
        let replay=GuidanceReplay(duration:0.2,samples:[sample(0,1,2,170),sample(0.2,1.2,2,-170)])
        let middle=try XCTUnwrap(replay.pose(at:0.1))
        XCTAssertEqual(middle.position!.x,1.1,accuracy:1e-6)
        XCTAssertEqual(abs(middle.heading!),180,accuracy:1e-6)
        XCTAssertEqual(replay.pose(at:0.2)?.position?.x,1.2)
        XCTAssertNil(replay.pose(at:-1));XCTAssertNil(replay.pose(at:.nan));XCTAssertNil(replay.pose(at:5))
    }
    func testMissingTrackingGapsAndJumpsNeverInterpolateOrAddDistance() throws {
        let samples=[sample(0,1),sample(0.2,1.1),sample(0.4,nil),sample(3,4),sample(3.2,4.1),sample(3.4,20)]
        let replay=GuidanceReplay(duration:3.4,samples:samples)
        XCTAssertNil(replay.pose(at:0.3));XCTAssertNil(replay.pose(at:1));XCTAssertNil(replay.pose(at:3.3))
        let analysis=GuidanceReplayAnalysis(replay:replay,route:try route())
        XCTAssertEqual(analysis.distance,0.2,accuracy:1e-6)
        XCTAssertEqual(analysis.missingSeconds,3,accuracy:1e-6)
    }
    func testDeviationUsesNearestStandardSegmentAndEventsKeepWaypointTimes() throws {
        let replay=GuidanceReplay(duration:0.6,samples:[sample(0,1),sample(0.2,1.1,2.3),sample(0.4,1.2,2.1,0,2),sample(0.6,1.3,2.1,0,2,.paused)])
        let analysis=GuidanceReplayAnalysis(replay:replay,route:try route())
        XCTAssertEqual(analysis.maximumDeviation,0.3,accuracy:1e-6)
        XCTAssertTrue(analysis.events.contains {$0.kind == .arrival(1) && $0.time==0.4})
        XCTAssertTrue(analysis.events.contains {$0.kind == .status(.paused)})
    }
    func testLegacyRecordWithoutReplayDecodes() throws {
        let original=try record(nil)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        json.removeValue(forKey:"replay")
        let legacy=try JSONDecoder().decode(GuidanceRecord.self,from:JSONSerialization.data(withJSONObject:json))
        try legacy.validate();XCTAssertNil(legacy.replay);XCTAssertEqual(legacy,original)
    }
    func testReplayPersistenceAndChangedTraceRejectedOnRetry() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=GuidanceRecordStore(root:root)
        let r=try record(.init(duration:0.2,samples:[sample(0,1),sample(0.2,1.1)]))
        try await store.save(r)
        let loaded=try await store.list();XCTAssertEqual(loaded,[r])
        let changed=GuidanceRecord(version:2,id:r.id,stageID:r.stageID,stageName:r.stageName,route:r.route,
            startedAt:r.startedAt,completedAt:r.completedAt,finishedAt:r.finishedAt,activeSeconds:r.activeSeconds,
            replay:.init(duration:0.2,samples:[sample(0,1),sample(0.2,1.2)]))
        do {try await store.save(changed);XCTFail("A different trajectory must not be silently discarded")} catch {}
    }
    func testRunCapturesPausedMovementButKeepsActiveTimeUnchanged() throws {
        let route=try route();var run=GuidanceRun(stageID:UUID(),stageName:"검증",route:route)
        run.capture(position:.init(1,2),heading:0,targetIndex:1,status:.guiding,uptime:9)
        run.begin(at:Date(timeIntervalSince1970:1000),uptime:10)
        run.capture(position:.init(1,2),heading:0,targetIndex:1,status:.guiding,uptime:10.0001,force:true)
        for i in 1...10 {run.capture(position:.init(1+Double(i)*0.02,2),heading:0,targetIndex:1,status:.guiding,uptime:10+Double(i)*0.02)}
        run.setRunning(false,uptime:11)
        run.capture(position:.init(2,2),heading:0,targetIndex:1,status:.paused,uptime:11,force:true)
        run.capture(position:nil,heading:nil,targetIndex:1,status:.untracked,uptime:12,force:true)
        run.setRunning(true,uptime:14)
        run.capture(position:.init(3,2),heading:0,targetIndex:2,status:.guiding,uptime:14,force:true)
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        XCTAssertTrue(guide.start(position:route.points[0],headingDegrees:0,trackingValid:true))
        for target in 1...2 {for frame in 0...6 {_=guide.observe(time:Double(target)*1.4+Double(frame)*0.2,position:route.points[target],headingDegrees:0,trackingValid:true)}}
        run.capture(position:.init(5,2),heading:0,targetIndex:2,status:.guiding,uptime:16,force:true)
        run.arrive(guide:guide,at:Date(timeIntervalSince1970:1006),uptime:16)
        run.capture(position:.init(9,2),heading:0,targetIndex:2,status:.guiding,uptime:17)
        let record=try run.record(completionSpoken:true,finishedAt:Date(timeIntervalSince1970:1007))
        XCTAssertEqual(record.activeSeconds,3);XCTAssertEqual(record.replay?.duration,6)
        XCTAssertNotNil(record.replay?.pose(at:0),"Synchronous departure pose is visible before playing")
        XCTAssertEqual(record.replay?.samples.last?.position?.x,5)
        XCTAssertEqual(record.replay?.samples.filter {$0.time<1}.count,2)
        XCTAssertTrue(record.replay!.samples.contains {$0.status == .untracked})
    }
    func testInvalidAndOutOfOrderSamplesRejected() throws {
        for samples in [[sample(0,1),sample(0,2)],[sample(1,1),sample(0.2,2)],[sample(0,1),sample(.nan,1)],
                        [sample(0,1,2,0,20)], [sample(0,1000)]] {
            XCTAssertThrowsError(try GuidanceReplay(duration:2,samples:samples).validate(pointCount:3))
        }
    }
    func testCaptureIsBoundedAndDoesNotInventMotionAfterLimit() throws {
        let route=try route();var run=GuidanceRun(stageID:UUID(),stageName:"긴 기록",route:route)
        run.begin(at:Date(),uptime:0)
        for i in 0...GuidanceReplay.maximumSamples {run.capture(position:.init(1,2),heading:0,targetIndex:1,status:.guiding,uptime:Double(i)*0.2,force:true)}
        var guide=RouteGuide(route:route,settings:GuideSettings(),usesRouteCorridor:true)
        _=guide.start(position:route.points[0],headingDegrees:0,trackingValid:true)
        for target in 1...2 {for frame in 0...6 {_=guide.observe(time:Double(target)*1.4+Double(frame)*0.2,position:route.points[target],headingDegrees:0,trackingValid:true)}}
        run.arrive(guide:guide,at:Date(),uptime:20_000)
        let result=try XCTUnwrap(run.record(completionSpoken:true,finishedAt:Date()).replay)
        XCTAssertEqual(result.samples.count,GuidanceReplay.maximumSamples);XCTAssertTrue(result.truncated)
        XCTAssertNil(result.pose(at:19_000))
    }
}
