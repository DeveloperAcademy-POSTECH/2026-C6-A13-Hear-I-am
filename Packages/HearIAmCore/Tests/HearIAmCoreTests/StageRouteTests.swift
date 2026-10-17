import XCTest
@testable import HearIAmCore

final class StageRouteTests: XCTestCase {
    func area() throws -> StageArea {
        try StageArea(corners:[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)])
    }
    func testFrontEdgeGuideIsPerpendicularAndPointsBackstage() throws {
        let guide=try FrontEdgeGuide(frontLeft:Point3(6,0,0),frontRight:Point3(0,0,0))
        XCTAssertEqual(guide.leftEnd.x,6,accuracy:1e-8)
        XCTAssertEqual(guide.rightEnd.x,0,accuracy:1e-8)
        XCTAssertEqual(guide.leftEnd.z,guide.length,accuracy:1e-8)
        XCTAssertEqual(guide.rightEnd.z,guide.length,accuracy:1e-8)
        let frontX=guide.rightStart.x-guide.leftStart.x
        let frontZ=guide.rightStart.z-guide.leftStart.z
        let inwardX=guide.leftEnd.x-guide.leftStart.x
        let inwardZ=guide.leftEnd.z-guide.leftStart.z
        XCTAssertEqual(frontX*inwardX+frontZ*inwardZ,0,accuracy:1e-8)
        let rotated=try FrontEdgeGuide(frontLeft:Point3(2,1,3),frontRight:Point3(2,1,7))
        XCTAssertGreaterThan(rotated.leftEnd.x,rotated.leftStart.x)
        XCTAssertEqual(rotated.leftEnd.z,3,accuracy:1e-8)
        let wide=try FrontEdgeGuide(frontLeft:Point3(20,0,0),frontRight:Point3(0,0,0))
        XCTAssertEqual(wide.length,12)
    }
    func testFrontEdgeGuideRejectsUnusableFirstEdge() {
        XCTAssertThrowsError(try FrontEdgeGuide(frontLeft:Point3(0,0,0),frontRight:Point3(0.1,0,0)))
        XCTAssertThrowsError(try FrontEdgeGuide(frontLeft:Point3(0,0,0),frontRight:Point3(2,0.3,0)))
    }
    func testCornerFrameRoundTripAndFront() throws {
        let a=try area()
        XCTAssertEqual(a.floor(a.world(FloorPoint(2,4))).distance(to:FloorPoint(2,4)),0,accuracy:1e-8)
        XCTAssertEqual(a.stageFront,FloorPoint(0,-1))
        XCTAssertTrue(a.contains(FloorPoint(0.3,0.3),margin:0.3))
        XCTAssertFalse(a.contains(FloorPoint(0.29,0.3),margin:0.3))
        let rotated=try StageArea(corners:[Point3(2,1,3),Point3(2,1,7),Point3(6,1,7),Point3(6,1,3)])
        XCTAssertEqual(rotated.floor(rotated.world(FloorPoint(1,2))).distance(to:FloorPoint(1,2)),0,accuracy:1e-8)
        XCTAssertEqual(rotated.width,4,accuracy:1e-8)
        XCTAssertEqual(rotated.depth,4,accuracy:1e-8)
    }
    func testWorldCameraDirectionMatchesStageRoute() throws {
        let a=try area()
        let frame=try StageFrame(origin:a.world(FloorPoint(0,0)),front:a.world(FloorPoint(0,-1)))
        let p=a.world(FloorPoint(3,3))
        let rightInWorld=Point3(p.x+1,p.y,p.z)
        XCTAssertEqual(a.floor(rightInWorld),FloorPoint(2,3))
        let heading=try XCTUnwrap(frame.heading(cameraForward:Point3(1,0,0)))
        XCTAssertEqual(heading,90,accuracy:1e-8)
        var guide=RouteGuide(route:try StageRoute(area:a,points:[FloorPoint(3,3),FloorPoint(2,3)],obstacles:[]),settings:GuideSettings())
        XCTAssertTrue(guide.start(position:FloorPoint(3,3),headingDegrees:0,trackingValid:true))
        XCTAssertTrue((guide.observe(time:1,position:FloorPoint(3,3),headingDegrees:0,trackingValid:true).announcement ?? "").hasPrefix("오른쪽,"))
    }
    func testBadCornerOrderPlaneAndRectangleRejected() throws {
        XCTAssertThrowsError(try StageArea(corners:[Point3(0,0,0),Point3(6,0,0),Point3(0,0,6),Point3(6,0,6)]))
        XCTAssertThrowsError(try StageArea(corners:[Point3(0,0,0),Point3(6,0,0),Point3(6,0.3,6),Point3(0,0,6)]))
        XCTAssertThrowsError(try StageArea(corners:[Point3(0,0,0),Point3(6,0,0),Point3(5,0,6),Point3(0,0,6)]))
    }
    func testObstacleIntersectionClearanceAndRouteOrder() throws {
        let a=try area()
        let o=try StageObstacle(name:"상자",kind:.box,vertices:[FloorPoint(2,2),FloorPoint(4,2),FloorPoint(4,4),FloorPoint(2,4)])
        let crossing=try StageRoute(area:a,points:[FloorPoint(1,3),FloorPoint(5,3)],obstacles:[o])
        XCTAssertFalse(crossing.conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        let touching=try StageRoute(area:a,points:[FloorPoint(1,1.65),FloorPoint(5,1.65)],obstacles:[o])
        XCTAssertFalse(touching.conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        let clear=try StageRoute(area:a,points:[FloorPoint(1,1),FloorPoint(5,1),FloorPoint(5,5)],obstacles:[o])
        XCTAssertTrue(clear.conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        let passable=try StageObstacle(name:"표식",kind:.other,passage:.passable,vertices:o.vertices)
        let allowed=try StageRoute(area:a,points:[FloorPoint(1,3),FloorPoint(5,3)],obstacles:[passable])
        XCTAssertTrue(allowed.conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        XCTAssertEqual(clear.points.count,3)
        let nearEdge=try StageRoute(area:a,points:[FloorPoint(0.2,1),FloorPoint(1,1)],obstacles:[])
        XCTAssertFalse(nearEdge.conflicts(boundaryMargin:0.3,obstacleClearance:0.35).isEmpty)
        XCTAssertThrowsError(try StageRoute(area:a,points:Array(repeating:FloorPoint(1,1),count:7),obstacles:[]))
    }
    func testSelfIntersectingObstacleRejected() {
        XCTAssertThrowsError(try StageObstacle(name:"X",kind:.other,vertices:[FloorPoint(1,1),FloorPoint(3,3),FloorPoint(1,3),FloorPoint(3,1)]))
    }
    func testVersionTwoArchivePreservesRouteAndSettings() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let a=try area()
        let r=try StageRoute(area:a,points:[FloorPoint(1,1),FloorPoint(5,1)],obstacles:[])
        var settings=GuideSettings(); settings.arrivalRadius=0.4
        let mesh=MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[Point3(0,0,0),Point3(1,0,0),Point3(0,0,1)],indices:[0,1,2])
        let store=ScanStore(root:root)
        let manifest=try await store.save(id:UUID(),name:"stage",frame:StageFrame(origin:a.world(FloorPoint(0,0)),front:a.world(FloorPoint(0,-1))),checkpoint:a.world(FloorPoint(1,1)),worldMap:Data("map".utf8),meshes:[mesh],device:"test",appVersion:"test",route:r,settings:settings)
        let loaded=try await store.load(manifest.id)
        XCTAssertEqual(loaded.manifest.version,2)
        XCTAssertEqual(loaded.manifest.route,r)
        XCTAssertEqual(loaded.manifest.settings.arrivalRadius,0.4)
        let invalid=ScanManifest(id:UUID(),name:"bad",frame:try StageFrame(origin:a.world(FloorPoint(0,0)),front:a.world(FloorPoint(0,-1))),checkpoint:a.corners[2],worldMapHash:"x",meshHash:"y",meshCount:1,vertexCount:3,device:"test",appVersion:"test",route:r,settings:settings)
        XCTAssertThrowsError(try invalid.validate())
    }
}

final class RouteGuideTests: XCTestCase {
    func route(_ points: [FloorPoint]) throws -> StageRoute {
        let a=try StageArea(corners:[Point3(8,0,0),Point3(0,0,0),Point3(0,0,8),Point3(8,0,8)])
        return try StageRoute(area:a,points:points,obstacles:[])
    }
    func testStartRequiresP0HeadingAndTracking() throws {
        let r=try route([FloorPoint(3,3),FloorPoint(3,2)])
        var g=RouteGuide(route:r,settings:GuideSettings())
        XCTAssertFalse(g.start(position:FloorPoint(4,3),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.start(position:FloorPoint(3,3),headingDegrees:30,trackingValid:true))
        XCTAssertFalse(g.start(position:FloorPoint(3,3),headingDegrees:0,trackingValid:false))
        XCTAssertTrue(g.start(position:FloorPoint(3,3),headingDegrees:0,trackingValid:true))
    }
    func testAllEightBodyRelativeDirections() throws {
        let targets=[FloorPoint(3,2),FloorPoint(2,2),FloorPoint(2,3),FloorPoint(2,4),FloorPoint(3,4),FloorPoint(4,4),FloorPoint(4,3),FloorPoint(4,2)]
        let names=["앞,","오른쪽 앞,","오른쪽,","오른쪽 뒤,","뒤,","왼쪽 뒤,","왼쪽,","왼쪽 앞,"]
        for i in targets.indices {
            var g=RouteGuide(route:try route([FloorPoint(3,3),targets[i]]),settings:GuideSettings())
            XCTAssertTrue(g.start(position:FloorPoint(3,3),headingDegrees:0,trackingValid:true))
            let text=g.observe(time:1,position:FloorPoint(3,3),headingDegrees:0,trackingValid:true).announcement ?? ""
            XCTAssertTrue(text.hasPrefix(names[i]),"sector \(i): \(text)")
        }
        var sidestep=RouteGuide(route:try route([FloorPoint(3,3),FloorPoint(3,2)]),settings:GuideSettings())
        XCTAssertTrue(sidestep.start(position:FloorPoint(3,3),headingDegrees:0,trackingValid:true))
        XCTAssertTrue((sidestep.observe(time:1,position:FloorPoint(3,3),headingDegrees:90,trackingValid:true).announcement ?? "").hasPrefix("왼쪽,"))
    }
    func testHysteresisAndRateLimit() throws {
        var settings=GuideSettings(); settings.repeatInterval=0.1
        var g=RouteGuide(route:try route([FloorPoint(3,3),FloorPoint(3,2)]),settings:settings)
        XCTAssertTrue(g.start(position:FloorPoint(3,3),headingDegrees:0,trackingValid:true))
        XCTAssertTrue((g.observe(time:1,position:FloorPoint(3,3),headingDegrees:-20,trackingValid:true).announcement ?? "").hasPrefix("앞,"))
        XCTAssertNil(g.observe(time:1.05,position:FloorPoint(3,3),headingDegrees:-25,trackingValid:true).announcement)
        XCTAssertTrue((g.observe(time:1.2,position:FloorPoint(3,3),headingDegrees:-25,trackingValid:true).announcement ?? "").hasPrefix("앞,"))
        XCTAssertTrue((g.observe(time:1.4,position:FloorPoint(3,3),headingDegrees:-31,trackingValid:true).announcement ?? "").hasPrefix("오른쪽 앞,"))
    }
    func testArrivalSpeaksNumberAndContinuesToNextTarget() throws {
        var settings=GuideSettings(); settings.arrivalDwell=0.4; settings.repeatInterval=1.0
        var g=RouteGuide(route:try route([FloorPoint(1,1),FloorPoint(2,1),FloorPoint(3,1)]),settings:settings)
        XCTAssertTrue(g.start(position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        _=g.observe(time:0,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true)
        XCTAssertNil(g.observe(time:0.2,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true).announcement)
        let first=g.observe(time:0.41,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(first.announcement,"1번째 지점 도착. 다음 p2, 왼쪽, 1.0미터.")
        XCTAssertEqual(g.state,.guiding)
        XCTAssertEqual(g.targetIndex,2)
        for t in [0.6,0.9,1.2] {
            XCTAssertNil(g.observe(time:t,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true).announcement)
        }
        XCTAssertNotNil(g.observe(time:1.5,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true).announcement)
        _=g.observe(time:1.6,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        _=g.observe(time:1.9,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        let last=g.observe(time:2.01,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(last.announcement,GuidanceCopy.completed)
        XCTAssertEqual(g.state,.completed)
    }
    func testFiveDestinationsNeverStopAtSecondPoint() throws {
        let points=(1...6).map { FloorPoint(Double($0),1) }
        var g=RouteGuide(route:try route(points),settings:GuideSettings())
        XCTAssertTrue(g.start(position:points[0],headingDegrees:0,trackingValid:true))
        var time=0.0
        for target in 1...5 {
            var arrival: String?
            for _ in 0..<5 {
                let update=g.observe(time:time,position:points[target],headingDegrees:0,trackingValid:true)
                if update.announcement?.contains("번째 지점 도착") == true || update.announcement == GuidanceCopy.completed { arrival=update.announcement }
                time += 0.25
            }
            XCTAssertNotNil(arrival)
            if target == 5 { XCTAssertEqual(arrival,GuidanceCopy.completed) }
            else { XCTAssertTrue(arrival?.hasPrefix("\(target)번째 지점 도착.") == true) }
            XCTAssertEqual(g.targetIndex,target == 5 ? 5 : target+1)
            XCTAssertEqual(g.state,target == 5 ? .completed : .guiding)
        }
    }
    func testOnlyStableStageReentryAutomaticallyResumes() throws {
        let r=try route([FloorPoint(1,1),FloorPoint(2,1)])
        var g=RouteGuide(route:r,settings:GuideSettings())
        XCTAssertTrue(g.start(position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        _=g.observe(time:0,position:FloorPoint(-0.1,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.pauseReason,.outsideStage)
        XCTAssertFalse(g.observeAutomaticRecovery(time:0.1,position:FloorPoint(0.1,1),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:0.2,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:0.6,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:1.0,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertTrue(g.observeAutomaticRecovery(time:1.21,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertEqual(g.state,.guiding)
        XCTAssertEqual(g.targetIndex,1)
        g.pause()
        XCTAssertEqual(g.pauseReason,.manual)
        XCTAssertFalse(g.observeAutomaticRecovery(time:2.5,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertTrue(g.resume(position:FloorPoint(1,1),trackingValid:true))
        _=g.observe(time:3,position:FloorPoint(1,1),headingDegrees:0,trackingValid:false)
        XCTAssertEqual(g.pauseReason,.invalidSample)
        XCTAssertFalse(g.observeAutomaticRecovery(time:4.1,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertTrue(g.resume(position:FloorPoint(1,1),trackingValid:true))
        _=g.observe(time:5,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true)
        _=g.observe(time:5.7,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.pauseReason,.sampleGap)
        XCTAssertFalse(g.observeAutomaticRecovery(time:5.8,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:6.3,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertTrue(g.observeAutomaticRecovery(time:6.8,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertEqual(g.targetIndex,1)
        g.pauseForUnclearHeading()
        XCTAssertEqual(g.pauseReason,.unclearHeading)
        XCTAssertFalse(g.observeAutomaticRecovery(time:7,position:FloorPoint(1,1),headingDegrees:.nan,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:7.1,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:7.6,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertFalse(g.observeAutomaticRecovery(time:8.0,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertTrue(g.observeAutomaticRecovery(time:8.2,position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        XCTAssertEqual(g.state,.guiding)
        XCTAssertEqual(g.targetIndex,1)
    }
    func testLeavingStagePausesGuidance() throws {
        var g=RouteGuide(route:try route([FloorPoint(1,1),FloorPoint(2,1)]),settings:GuideSettings())
        XCTAssertTrue(g.start(position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        _=g.observe(time:0,position:FloorPoint(-0.1,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.state,.paused)
    }
    func testArrivalOrderPauseAndExplicitResume() throws {
        var g=RouteGuide(route:try route([FloorPoint(1,1),FloorPoint(2,1),FloorPoint(3,1)]),settings:GuideSettings())
        XCTAssertTrue(g.start(position:FloorPoint(1,1),headingDegrees:0,trackingValid:true))
        _=g.observe(time:0,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.targetIndex,1)
        _=g.observe(time:0.3,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true)
        _=g.observe(time:0.7,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.targetIndex,1)
        _=g.observe(time:1.1,position:FloorPoint(2,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.targetIndex,2)
        _=g.observe(time:2.0,position:FloorPoint(2,1),headingDegrees:0,trackingValid:false)
        XCTAssertEqual(g.state,.paused)
        XCTAssertNil(g.observe(time:2.1,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true).announcement)
        XCTAssertEqual(g.targetIndex,2)
        XCTAssertTrue(g.resume(position:FloorPoint(2,1),trackingValid:true))
        _=g.observe(time:3,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        _=g.observe(time:3.4,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        _=g.observe(time:3.81,position:FloorPoint(3,1),headingDegrees:0,trackingValid:true)
        XCTAssertEqual(g.state,.completed)
    }
}
