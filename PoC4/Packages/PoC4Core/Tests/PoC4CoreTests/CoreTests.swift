import XCTest
import simd
@testable import PoC4Core

final class CoordinatesTests: XCTestCase {
    func testAudienceAndBodyRightSigns() throws {
        let frame=try StageFrame(origin:Point3(2,0,4),front:Point3(2,0,2))
        XCTAssertEqual(frame.position(Point3(3,1.2,4)),Point3(-1,0,1.2))
        XCTAssertEqual(frame.position(Point3(2,1,3)),Point3(0,-1,1))
        XCTAssertEqual(frame.heading(cameraForward:Point3(0,0,-1))!,0,accuracy:1e-8)
        XCTAssertEqual(frame.heading(cameraForward:Point3(1,0,0))!,90,accuracy:1e-8)
        XCTAssertEqual(frame.heading(cameraForward:Point3(-1,0,0))!,-90,accuracy:1e-8)
        XCTAssertEqual(abs(frame.heading(cameraForward:Point3(0,0,1))!),180,accuracy:1e-8)
    }
    func testRotatedStageAndTilt() throws {
        let frame=try StageFrame(origin:Point3(0,1,0),front:Point3(2,1,0))
        XCTAssertEqual(frame.position(Point3(1,2,0)),Point3(0,-1,1))
        XCTAssertEqual(frame.heading(cameraForward:Point3(1,0.4,0))!,0,accuracy:1e-8)
        XCTAssertNil(frame.heading(cameraForward:Point3(0,1,0)))
        XCTAssertNil(frame.heading(cameraForward:Point3(0,1,0.1)))
        XCTAssertNotNil(frame.heading(cameraForward:Point3(0,1,0.3)))
        XCTAssertNil(frame.heading(cameraForward:Point3(.nan,0,0)))
        XCTAssertNil(frame.heading(cameraForward:Point3(0,0,0)))
    }
    func testDegenerateReferenceRejected() {
        XCTAssertThrowsError(try StageFrame(origin:Point3(0,0,0),front:Point3(0.1,0,0)))
        XCTAssertThrowsError(try StageFrame(origin:Point3(0,0,0),front:Point3(1,0.5,0)))
        XCTAssertThrowsError(try StageFrame(origin:Point3(.infinity,0,0),front:Point3(1,0,0)))
    }
    func testDecodeDoesNotBypassValidation() throws {
        let bytes=Data(#"{"origin":{"x":0,"y":0,"z":0},"front":{"x":0,"y":0,"z":0}}"#.utf8)
        let frame=try JSONDecoder().decode(StageFrame.self,from:bytes)
        XCTAssertThrowsError(try frame.validate())
    }
}
final class TrackingTests: XCTestCase {
    func stable() -> TrackingGate {
        var gate=TrackingGate()
        for i in 0...12 { gate.observe(time:Double(i)/10,normal:true,anchorsPresent:true) }
        return gate
    }
    func testNormalAloneNeverVerifies() {
        let gate=stable()
        XCTAssertTrue(gate.canVerify(now:1.2)); XCTAssertFalse(gate.isReady(now:1.2))
    }
    func testExplicitCheckpointRequired() {
        var gate=stable()
        XCTAssertTrue(gate.verify(error:0.1,tolerance:0.15,now:1.2))
        XCTAssertTrue(gate.isReady(now:1.3))
        XCTAssertFalse(gate.verify(error:0.2,tolerance:0.15,now:1.3))
        XCTAssertFalse(gate.isReady(now:1.3))
    }
    func testLostAnchorsRevokeAndRecoveryDoesNotReverify() {
        var gate=stable(); gate.verify(error:0,tolerance:0.15,now:1.2)
        gate.observe(time:1.3,normal:true,anchorsPresent:false)
        XCTAssertFalse(gate.verified)
        for i in 14...26 {gate.observe(time:Double(i)/10,normal:true,anchorsPresent:true)}
        XCTAssertTrue(gate.canVerify(now:2.6)); XCTAssertFalse(gate.isReady(now:2.6))
    }
    func testLimitedRevoke() {
        var gate=stable(); gate.verify(error:0,tolerance:0.15,now:1.2)
        gate.observe(time:1.3,normal:false,anchorsPresent:true)
        XCTAssertFalse(gate.verified); XCTAssertFalse(gate.canVerify(now:1.3))
    }
    func testGapCannotCountAsStableTime() {
        var gate=TrackingGate(); gate.observe(time:1,normal:true,anchorsPresent:true)
        gate.observe(time:5,normal:true,anchorsPresent:true)
        XCTAssertFalse(gate.canVerify(now:5))
    }
    func testStaleDuplicateAndBackwardSamples() {
        var gate=stable()
        XCTAssertFalse(gate.observe(time:1.2,normal:true,anchorsPresent:true))
        XCTAssertFalse(gate.observe(time:1.1,normal:true,anchorsPresent:true))
        XCTAssertFalse(gate.observe(time:.nan,normal:true,anchorsPresent:true))
        XCTAssertFalse(gate.verify(error:0,tolerance:0.15,now:2))
        XCTAssertFalse(gate.canVerify(now:1.1))
    }
    func testWatchdogRevokesWithoutNewFrame() {
        var gate=stable(); gate.verify(error:0,tolerance:0.15,now:1.2)
        gate.expire(now:2); XCTAssertFalse(gate.verified)
        gate.observe(time:2.1,normal:true,anchorsPresent:true)
        XCTAssertFalse(gate.isReady(now:2.1))
    }
    func testInvalidVerificationData() {
        for error in [Double.nan, .infinity, -0.1] {
            var gate=stable(); XCTAssertFalse(gate.verify(error:error,tolerance:0.15,now:1.2))
        }
        for tolerance in [Double.nan, .infinity, -1, 0, 1] {
            var gate=stable(); XCTAssertFalse(gate.verify(error:0,tolerance:tolerance,now:1.2))
        }
    }
}
final class StoreTests: XCTestCase {
    let transform: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    func mesh() -> MeshSnapshot {
        MeshSnapshot(id:UUID(),transform:transform,vertices:[Point3(0,0,0),Point3(1,0,0),Point3(0,0,1)],indices:[0,1,2])
    }
    func temp() -> URL {FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)}
    func save(_ store: ScanStore, id: UUID=UUID()) async throws -> ScanManifest {
        try await store.save(id:id,name:"Test",frame:StageFrame(origin:Point3(0,0,0),front:Point3(0,0,-1)),
            checkpoint:Point3(1,0,0),worldMap:Data("map".utf8),meshes:[mesh()],device:"test",appVersion:"test")
    }
    func testRoundTripAndList() async throws {
        let root=temp(); defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), m=try await save(store)
        let loaded=try await store.load(m.id), list=try await store.list()
        XCTAssertEqual(loaded.worldMap,Data("map".utf8))
        XCTAssertEqual(loaded.meshes.count,1); XCTAssertEqual(loaded.manifest.frame,m.frame)
        XCTAssertEqual(list.map(\.id),[m.id])
    }
    func testCorruptMapRejected() async throws {
        let root=temp(); defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), m=try await save(store)
        try Data("changed".utf8).write(to:root.appendingPathComponent(m.id.uuidString+"/worldmap.bin"))
        do {_ = try await store.load(m.id); XCTFail("must reject corrupted map")} catch {}
    }
    func testCorruptMeshRejected() async throws {
        let root=temp(); defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), m=try await save(store)
        try Data("[]".utf8).write(to:root.appendingPathComponent(m.id.uuidString+"/mesh.json"))
        do {_ = try await store.load(m.id); XCTFail("must reject corrupted mesh")} catch {}
    }
    func testNoOverwriteAndNoPartialRecord() async throws {
        let root=temp(); defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root), m=try await save(store)
        do {_ = try await save(store,id:m.id); XCTFail("must preserve previous scan")} catch {}
        let list=try await store.list(); XCTAssertEqual(list.count,1)
        let dirs=try FileManager.default.contentsOfDirectory(atPath:root.path)
        XCTAssertEqual(dirs.count,1)
    }
    func testUnsupportedVersionRejected() async throws {
        let root=temp(); defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root); var m=try await save(store); m.version=99
        try JSONEncoder().encode(m).write(to:root.appendingPathComponent(m.id.uuidString+"/manifest.json"))
        do {_ = try await store.load(m.id); XCTFail("unsupported version")} catch {}
    }
    func testInvalidMeshAndEmptyMapRejected() async throws {
        let bad=MeshSnapshot(id:UUID(),transform:transform,vertices:[Point3(0,0,0)],indices:[0,1,2])
        XCTAssertThrowsError(try bad.validate())
        let noTransform=MeshSnapshot(id:UUID(),transform:[],vertices:[Point3(0,0,0)],indices:[0,0,0])
        XCTAssertThrowsError(try noTransform.validate())
        let root=temp(); defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        do {
            _ = try await store.save(id:UUID(),name:"x",frame:StageFrame(origin:Point3(0,0,0),front:Point3(1,0,0)),checkpoint:Point3(0,0,1),worldMap:Data(),meshes:[mesh()],device:"x",appVersion:"x")
            XCTFail("empty map")
        } catch {}
    }
}
final class LogTests: XCTestCase {
    func testStreamingOrderAndInvalidRowsRetainValidityFlag() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:dir)}
        let logger=try TrialLog(directory:dir,metadata:["source":"test"])
        for i in 0..<100 {
            logger.append(TrialRecord(sequence:i,uptime:Double(i),event:"pose",detail:"quote \" line\n",position:Point3(1,2,3),verified:i%2==0))
        }
        let url: URL=try await withCheckedThrowingContinuation { continuation in
            logger.close { continuation.resume(with:$0) }
        }
        let lines=try String(contentsOf:url,encoding:.utf8).split(separator:"\n")
        XCTAssertEqual(lines.count,101)
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for i in 0..<100 {
            let row=try decoder.decode(TrialRecord.self,from:Data(lines[i+1].utf8))
            XCTAssertEqual(row.sequence,i); XCTAssertEqual(row.verified,i%2==0)
        }
    }
    func testWriteErrorReportedAtClose() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:dir)}
        let logger=try TrialLog(directory:dir,metadata:[:])
        logger.append(TrialRecord(sequence:0,uptime:.nan,event:"bad"))
        let result: Result<URL,Error>=await withCheckedContinuation { c in logger.close { c.resume(returning:$0) } }
        if case .success=result { XCTFail("encoding failure must be visible") }
    }
}
