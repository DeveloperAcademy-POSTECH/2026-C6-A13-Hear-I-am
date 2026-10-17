import XCTest
@testable import HearIAmCore

/// Object height from the scan mesh, used to suggest platform or obstacle (asked 10/17).
final class ObjectHeightTests: XCTestCase {
    func area() throws -> StageArea { try StageArea(corners:[Point3(6,0,0),Point3(0,0,0),Point3(0,0,6),Point3(6,0,6)]) }
    /// A grid of vertices at `height` over x,z in [from, to], placed through a translated mesh transform.
    func slab(from: Double, to: Double, height: Double, offset: Point3=Point3(0,0,0)) -> MeshSnapshot {
        var points: [Point3]=[]
        for i in 0...10 { for j in 0...10 {
            points.append(Point3(from+(to-from)*Double(i)/10-offset.x,height-offset.y,from+(to-from)*Double(j)/10-offset.z))
        }}
        let t: [Float]=[1,0,0,0, 0,1,0,0, 0,0,1,0, Float(offset.x),Float(offset.y),Float(offset.z),1]
        return MeshSnapshot(id:UUID(),transform:t,vertices:points,indices:[0,1,2])
    }
    func outline(_ a: Double,_ b: Double) -> [Point3] { [Point3(a,0,a),Point3(b,0,a),Point3(b,0,b),Point3(a,0,b)] }

    func testLowTopIsSuggestedAsPlatform() throws {
        let a=try area()
        let h=try XCTUnwrap(ObjectHeight.measure(meshes:[slab(from:1,to:2,height:0.15,offset:Point3(0.5,0.1,0.5))],outline:outline(1.1,1.9),area:a))
        XCTAssertEqual(h.height,0.15,accuracy:1e-6);XCTAssertEqual(h.suggestedKind,.platform)
    }
    func testTallTopIsSuggestedAsObstacleAndFloorAroundItDoesNotPullItDown() throws {
        let a=try area()
        // Outline drawn a little wide: floor vertices around a 0.8 m box fall inside too.
        let meshes=[slab(from:1,to:2,height:0.8),slab(from:0.9,to:1.05,height:0)]
        let h=try XCTUnwrap(ObjectHeight.measure(meshes:meshes,outline:outline(0.95,1.95),area:a))
        XCTAssertEqual(h.height,0.8,accuracy:1e-6);XCTAssertEqual(h.suggestedKind,.other)
    }
    func testFlatFloorSuggestsNothingAndEmptyMeshMeasuresNothing() throws {
        let a=try area()
        XCTAssertNil(try XCTUnwrap(ObjectHeight.measure(meshes:[slab(from:1,to:2,height:0.01)],outline:outline(1.1,1.9),area:a)).suggestedKind)
        XCTAssertNil(ObjectHeight.measure(meshes:[slab(from:3,to:3.5,height:0.2)],outline:outline(1.1,1.9),area:a))
        XCTAssertNil(ObjectHeight.measure(meshes:[slab(from:1,to:2,height:0.2)],outline:[Point3(1,0,1),Point3(2,0,1)],area:a))
    }
    func testCeilingAboveTheOutlineIsIgnored() throws {
        let a=try area()
        let h=try XCTUnwrap(ObjectHeight.measure(meshes:[slab(from:1,to:2,height:0.2),slab(from:1,to:2,height:2.8)],outline:outline(1.1,1.9),area:a))
        XCTAssertEqual(h.height,0.2,accuracy:1e-6)
    }
    func testHeightIsKeptWhenProjectedAndOlderSavesDecodeWithoutIt() throws {
        let a=try area()
        let projected=try WorldObstacle(name:"단상",kind:.platform,vertices:outline(1,2),height:0.15).projected(in:a)
        XCTAssertEqual(projected.height,0.15)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(projected)) as? [String:Any])
        json["height"]=nil
        XCTAssertNil(try JSONDecoder().decode(StageObstacle.self,from:JSONSerialization.data(withJSONObject:json)).height)
    }
}
