import XCTest
@testable import HearIAmCore

final class ObjectScanRegionTests: XCTestCase {
    let identity: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    func testOnlyChosenFootprintAndHeightAreCapturedButSidesTouchingFloorRemain() throws {
        let region=try ObjectScanRegion(outline:[.init(0,0,0),.init(2,0,0),.init(2,0,2),.init(0,0,2)],floorHeight:0)
        let vertices: [Point3]=[
            .init(0.2,0,0.2),.init(1,0,0.2),.init(1,0,1), // floor excluded
            .init(0.2,0,0.2),.init(1,0,0.2),.init(1,1,0.2), // side included
            .init(0.2,1,0.2),.init(1,1,0.2),.init(1,1,1), // top included
            .init(3,1,0.2),.init(4,1,0.2),.init(4,1,1), // other object excluded
            .init(0.2,3,0.2),.init(1,3,0.2),.init(1,3,1)] // ceiling excluded
        let mesh=MeshSnapshot(id:UUID(),transform:identity,vertices:vertices,indices:Array(0..<15).map(UInt32.init))
        let result=try XCTUnwrap(region.selecting(mesh,inside:true))
        XCTAssertEqual(result.indices.count,6);try result.validate()
        XCTAssertEqual(region.selecting(mesh,inside:false)?.indices.count,9)
    }
    func testWorldTransformAppliedAndInputMeshUnchanged() throws {
        let region=try ObjectScanRegion(outline:[.init(10,2,20),.init(12,2,20),.init(12,2,22),.init(10,2,22)],floorHeight:2)
        let t: [Float]=[0,0,1,0,0,1,0,0,-1,0,0,0,12,2,20,1]
        let mesh=MeshSnapshot(id:UUID(),transform:t,vertices:[.init(0.2,1,0.2),.init(1,1,0.2),.init(1,1,1)],indices:[0,1,2])
        let bytes=try JSONEncoder().encode(mesh)
        let result=try XCTUnwrap(region.selecting(mesh,inside:true))
        XCTAssertEqual(result.vertices[0].x,11.8,accuracy:0.0001)
        XCTAssertEqual(result.vertices[0].y,3,accuracy:0.0001)
        XCTAssertEqual(result.vertices[0].z,20.2,accuracy:0.0001)
        XCTAssertEqual(result.transform,identity)
        XCTAssertEqual(mesh,try JSONDecoder().decode(MeshSnapshot.self,from:bytes))
    }
    func testComposingOnePerformanceDoesNotModifyBaseOrAnotherPerformance() throws {
        let region=try ObjectScanRegion(outline:[.init(0,0,0),.init(2,0,0),.init(2,0,2),.init(0,0,2)],floorHeight:0)
        let base=MeshSnapshot(id:UUID(),transform:identity,vertices:[.init(0,0,0),.init(2,0,0),.init(2,0,2)],indices:[0,1,2])
        let addition=MeshSnapshot(id:UUID(),transform:identity,vertices:[.init(0.2,1,0.2),.init(1,1,0.2),.init(1,1,1)],indices:[0,1,2])
        let a=ObjectScanRegion.compose(base:[base],regions:[region],additions:[addition])
        let b=ObjectScanRegion.compose(base:[base],regions:[],additions:[])
        XCTAssertEqual(a.count,2);XCTAssertEqual(b,[base])
        XCTAssertEqual(ObjectScanRegion.compose(base:[base],regions:[],additions:[]),[base],"Deleting a layer restores original base surfaces")
    }
    func testInvalidSelfCrossingOutlineAndOverlap() throws {
        XCTAssertThrowsError(try ObjectScanRegion(outline:[.init(0,0,0),.init(2,0,2),.init(2,0,0),.init(0,0,2)],floorHeight:0))
        let a=try ObjectScanRegion(outline:[.init(0,0,0),.init(2,0,0),.init(2,0,2),.init(0,0,2)],floorHeight:0)
        let b=try ObjectScanRegion(outline:[.init(1,0,1),.init(3,0,1),.init(3,0,3),.init(1,0,3)],floorHeight:0)
        XCTAssertTrue(a.overlaps(b))
    }
}
