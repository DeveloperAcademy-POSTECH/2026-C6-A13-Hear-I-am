import XCTest
@testable import HearIAmCore

final class ScannedFootprintTests: XCTestCase {
    static let identity: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    static func rectangle(_ x0: Double,_ y0: Double,_ x1: Double,_ y1: Double, area: StageArea = PerformancePlan.area) -> MeshSnapshot {
        MeshSnapshot(id:UUID(),transform:identity,vertices:[.init(x0,y0),.init(x1,y0),.init(x1,y1),.init(x0,y1)].map(area.world),indices:[0,1,2,0,2,3])
    }
    func testMeshTransformsAndStageCoordinatesAgree() throws {
        let area=try StageArea(corners:[.init(10,2,20),.init(10,2,30),.init(18,2,30),.init(18,2,20)])
        let original=Self.rectangle(-2,-2,12,10,area:area)
        var transform=Self.identity;transform[12]=3;transform[13]=4;transform[14]=5
        let mesh=MeshSnapshot(id:UUID(),transform:transform,vertices:original.vertices.map {.init($0.x-3,$0.y-4,$0.z-5)},indices:original.indices)
        let coverage=try ScannedFootprint(meshes:[mesh],area:area)
        XCTAssertTrue(coverage.contains(.init(-1,5)))
        XCTAssertTrue(coverage.covers(from:.init(-1,5),to:.init(11,5)))
        XCTAssertFalse(coverage.contains(.init(-3,5)))
    }
    func testDisconnectedScansDoNotFillTheirBoundingRectangle() throws {
        let coverage=try ScannedFootprint(meshes:[Self.rectangle(-3,0,-1,4),Self.rectangle(1,0,3,4)],area:PerformancePlan.area)
        XCTAssertTrue(coverage.contains(.init(-2,2)));XCTAssertTrue(coverage.contains(.init(2,2)))
        XCTAssertFalse(coverage.contains(.init(0,2)))
        XCTAssertFalse(coverage.covers(from:.init(-2,2),to:.init(2,2)))
    }
    func testAdjacentAnchorsAndSmallSeamsConnectButLargeHolesDoNot() throws {
        for (gap,expected) in [(0.0,true),(0.03,true),(0.2,false)] {
            let coverage=try ScannedFootprint(meshes:[Self.rectangle(-3,0,0,4),Self.rectangle(gap,0,3,4)],area:PerformancePlan.area)
            XCTAssertEqual(coverage.covers(from:.init(-2,2),to:.init(2,2)),expected)
        }
    }
    func testVerticalWallsAndEmptyMeshesDoNotClaimCoverage() throws {
        let wall=MeshSnapshot(id:UUID(),transform:Self.identity,vertices:[.init(0,0,0),.init(0,2,0),.init(3,2,0)],indices:[0,1,2])
        XCTAssertThrowsError(try ScannedFootprint(meshes:[wall],area:PerformancePlan.area))
        XCTAssertThrowsError(try ScannedFootprint(meshes:[],area:PerformancePlan.area))
        let malformed=MeshSnapshot(id:UUID(),transform:Self.identity,vertices:[.init(0,0,0)],indices:[0,1,2])
        XCTAssertThrowsError(try ScannedFootprint(meshes:[malformed],area:PerformancePlan.area))
    }
    func testTriangleCoverageDoesNotFillAnUnscannedCorner() throws {
        let area=PerformancePlan.area
        let mesh=MeshSnapshot(id:UUID(),transform:Self.identity,vertices:[.init(0,0),.init(4,0),.init(0,4)].map(area.world),indices:[0,1,2])
        let coverage=try ScannedFootprint(meshes:[mesh],area:area)
        XCTAssertTrue(coverage.contains(.init(1,1)));XCTAssertFalse(coverage.contains(.init(3,3)))
        XCTAssertTrue(coverage.covers(from:.init(0.5,0.5),to:.init(2,1)))
        XCTAssertFalse(coverage.contains(.init(.nan,0)));XCTAssertFalse(coverage.covers(from:.init(0,0),to:.init(.infinity,0)))
    }
}
