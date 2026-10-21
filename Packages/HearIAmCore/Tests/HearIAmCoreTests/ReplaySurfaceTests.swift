import XCTest
@testable import HearIAmCore

final class ReplaySurfaceTests: XCTestCase {
    private let identity: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    private func route(obstacles: [StageObstacle]=[]) throws -> StageRoute {
        let area=try StageArea(corners:[.init(0,0,0),.init(4,0,0),.init(4,0,-3),.init(0,0,-3)])
        return try StageRoute(area:area,points:[.init(0.2,0.2),.init(0.6,0.2)],obstacles:obstacles)
    }
    private func mesh(_ vertices: [Point3],indices: [UInt32]=[0,1,2],transform: [Float]?=nil) -> MeshSnapshot {
        MeshSnapshot(id:UUID(),transform:transform ?? identity,vertices:vertices,indices:indices)
    }
    func testAnchorAndRotatedStageUseSameLocalMetresAndUV() throws {
        let area=try StageArea(corners:[.init(10,2,5),.init(10,2,9),.init(13,2,9),.init(13,2,5)])
        let route=try StageRoute(area:area,points:[.init(0.2,0.2),.init(0.6,0.2)],obstacles:[])
        // Correct column-major rigid transform: local x maps +world Z, local z maps -world X.
        let rotation: [Float]=[0,0,1,0,0,1,0,0,-1,0,0,0,10,2,5,1]
        let original=mesh([.init(0,0,0),.init(2.4,0,0),.init(2.4,0,-2.4)],transform:rotation)
        let surface=ReplaySurfaceMesh(mesh:original,route:route)
        for (actual,expected) in zip(surface.vertices,[Point3(0,0,0),.init(2.4,0,0),.init(2.4,0,-2.4)]) {
            XCTAssertEqual(actual.x,expected.x,accuracy:1e-8);XCTAssertEqual(actual.z,expected.z,accuracy:1e-8)
        }
        XCTAssertEqual(surface.floorIndices,[0,1,2])
        XCTAssertEqual(ReplaySurfaceMesh.textureCoordinate(surface.vertices[2]).x,1,accuracy:1e-8)
        XCTAssertEqual(ReplaySurfaceMesh.textureCoordinate(surface.vertices[2]).y,1,accuracy:1e-8)
    }
    func testSmallFloorNoiseUsesFlatDisplayWithoutChangingSavedVertices() throws {
        let original=mesh([.init(0,0.03,0),.init(2,-0.02,0),.init(0,0.01,-2)])
        let copy=original
        let surface=ReplaySurfaceMesh(mesh:original,route:try route())
        XCTAssertEqual(surface.floorIndices,[0,1,2]);XCTAssertTrue(surface.surfaceIndices.isEmpty)
        XCTAssertEqual(original,copy)
        XCTAssertEqual(surface.vertices[0].y,0.03) // Flattening belongs only to the renderer.
    }
    func testRaisedFloorsVerticalEdgesAndRampsRemainSurfaces() throws {
        for vertices: [Point3] in [
            [.init(0,0.4,0),.init(1,0.4,0),.init(0,0.4,-1)],
            [.init(0,0,0),.init(1,0,0),.init(1,0.06,0)],
            [.init(0,0,0),.init(0.05,0.07,0),.init(0,0,-1)]
        ] {
            let result=ReplaySurfaceMesh(mesh:mesh(vertices),route:try route())
            XCTAssertTrue(result.floorIndices.isEmpty)
            XCTAssertEqual(result.surfaceIndices,[0,1,2])
        }
    }
    func testDisconnectedFloorKeepsOriginalCoverageAndSharedUVOrigin() throws {
        let a=ReplaySurfaceMesh(mesh:mesh([.init(-2,0,0),.init(-1,0,0),.init(-2,0,-1)]),route:try route())
        var translated=identity;translated[12]=10
        let b=ReplaySurfaceMesh(mesh:mesh([.init(0,0,0),.init(1,0,0),.init(0,0,-1)],transform:translated),route:try route())
        XCTAssertEqual(a.floorIndices.count+b.floorIndices.count,6)
        XCTAssertEqual(a.vertices.map(\.x).max(),-1)
        XCTAssertEqual(b.vertices.map(\.x).min(),10)
        XCTAssertEqual(ReplaySurfaceMesh.textureCoordinate(b.vertices[0]).x,10/2.4,accuracy:1e-9)
        // No bounding rectangle is inferred to fill the unscanned gap between patches.
    }
    func testOnlyContainedObjectSurfacesAreReplaced() throws {
        let object=try StageObstacle(name:"의자",kind:.other,vertices:[.init(1,1),.init(2,1),.init(2,2),.init(1,2)],height:0.9,
                                     appearance:.init(model:.chair))
        let route=try route(obstacles:[object])
        let inside=mesh([.init(1.1,0.5,-1.1),.init(1.8,0.5,-1.1),.init(1.1,0.5,-1.8)])
        XCTAssertTrue(ReplaySurfaceMesh(mesh:inside,route:route).surfaceIndices.isEmpty)
        let boundary=mesh([.init(0.9,0.5,-1.1),.init(1.8,0.5,-1.1),.init(1.1,0.5,-1.8)])
        XCTAssertEqual(ReplaySurfaceMesh(mesh:boundary,route:route).surfaceIndices,[0,1,2])
        let wall=mesh([.init(1.1,1.5,-1.1),.init(1.8,1.5,-1.1),.init(1.1,2.5,-1.1)])
        XCTAssertEqual(ReplaySurfaceMesh(mesh:wall,route:route).surfaceIndices,[0,1,2])
        let floor=mesh([.init(1.1,0,-1.1),.init(1.8,0,-1.1),.init(1.1,0,-1.8)])
        XCTAssertEqual(ReplaySurfaceMesh(mesh:floor,route:route).floorIndices,[0,1,2])
        XCTAssertEqual(route.obstacles,[object])
    }
    func testBothWindingOrdersProduceFloorAndDegenerateFacesAreSkipped() throws {
        let original=mesh([.init(0,0,0),.init(1,0,0),.init(0,0,-1)],indices:[0,1,2,2,1,0,0,0,0])
        let result=ReplaySurfaceMesh(mesh:original,route:try route())
        XCTAssertEqual(result.floorIndices,[0,1,2,2,1,0]);XCTAssertTrue(result.surfaceIndices.isEmpty)
    }
}
