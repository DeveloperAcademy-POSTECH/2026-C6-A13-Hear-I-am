import XCTest
import simd
@testable import HearIAmCore

final class UpperSurfaceColorFillTests: XCTestCase {
    private let identity: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    private let red: [UInt8]=[180,30,40,255],blue: [UInt8]=[30,40,180,255]
    private func index(_ row: Int,_ col: Int=2) -> Int {row*5+col}
    private func wall(observe: Bool=true,colors: ((Int,Int) -> [UInt8])? = nil,
                      position: ((Double,Double) -> Point3)? = nil,transform: [Float]? = nil) -> MeshSnapshot {
        var vertices=[Point3](),indices=[UInt32](),rgba=[UInt8]()
        for row in 0..<6 {for col in 0..<5 {
            let x=Double(col-2)*0.1,y=Double(row)*0.1
            vertices.append(position?(x,y) ?? .init(x,y,-2))
            rgba += colors?(row,col) ?? (observe && row<=1 ? red : [0,0,0,0])
        }}
        for row in 0..<5 {for col in 0..<4 {
            let a=UInt32(index(row,col)),b=a+1,c=a+5,d=c+1
            indices += [a,b,d,a,d,c]
        }}
        return MeshSnapshot(id:UUID(),transform:transform ?? identity,vertices:vertices,indices:indices,
                            surfaceColors:observe || colors != nil ? Data(rgba) : nil)
    }
    private func estimate(_ mesh: MeshSnapshot,_ row: Int,_ col: Int=2) -> [UInt8]? {
        mesh.inferredSurfaceColors.map {Array($0[index(row,col)*4..<index(row,col)*4+4])}
    }
    private func frame(time: Double,cy: Float=3.25,mask: Bool=false,occluder: Bool=false) -> SurfaceColorFrame {
        let w=32,h=24
        var depths=[Float](repeating:2,count:w*h),people=[UInt8](repeating:0,count:w*h)
        if mask || occluder {
            for y in 8...9 {for x in 0..<w {
                if mask {people[y*w+x]=1}
                if occluder {depths[y*w+x]=1}
            }}
        }
        return SurfaceColorFrame(time:time,cameraTransform:matrix_identity_float4x4,width:w,height:h,
            fx:20,fy:20,cx:16,cy:cy,rgb:Array(repeating:[UInt8(180),30,40],count:w*h).flatMap {$0},
            depth:depths,confidence:Array(repeating:2,count:w*h),personMask:mask ? people : nil)
    }
    func testSmallUpwardFillPreservesDirectColorsGeometryAndSeparateProvenance() throws {
        let original=wall(),result=UpperSurfaceColorFill.fill(original)
        XCTAssertEqual(estimate(result.mesh,2),red)
        XCTAssertEqual(estimate(result.mesh,3),red)
        XCTAssertEqual(estimate(result.mesh,4),[0,0,0,0]) // Two measured levels no longer within 30 cm.
        XCTAssertEqual(estimate(result.mesh,5),[0,0,0,0])
        XCTAssertEqual(result.mesh.surfaceColors,original.surfaceColors)
        XCTAssertEqual(result.mesh.vertices,original.vertices);XCTAssertEqual(result.mesh.indices,original.indices)
        XCTAssertEqual(result.mesh.transform,original.transform);XCTAssertEqual(result.mesh.id,original.id)
        XCTAssertNoThrow(try result.mesh.validate())
        XCTAssertEqual(result.mesh.surfaceColors?[index(2)*4+3],0)
        XCTAssertEqual(result.mesh.displaySurfaceColors?[index(2)*4+3],255)
        XCTAssertGreaterThan(result.diagnostics.inferredVertices,0)
    }
    func testInferredColorsNeverBecomeDonorsOrExtendAgain() {
        let first=UpperSurfaceColorFill.fill(wall()).mesh
        let second=UpperSurfaceColorFill.fill(first)
        XCTAssertEqual(second.mesh,first);XCTAssertEqual(second.diagnostics.inferredVertices,0)
        XCTAssertEqual(estimate(second.mesh,4),[0,0,0,0])
    }
    func testColorBoundaryAndKnownDifferentUpperColorStopFill() {
        let split=wall(colors:{row,col in row<=1 ? (col>=3 ? self.blue : self.red) : [0,0,0,0]})
        let result=UpperSurfaceColorFill.fill(split)
        XCTAssertEqual(estimate(result.mesh,2),[0,0,0,0])
        XCTAssertEqual(estimate(result.mesh,2,1),red) // Uniform red patch away from the boundary is still usable.
        XCTAssertGreaterThan(result.diagnostics.rejected["colorBoundary"] ?? 0,0)
        let upper=wall(colors:{row,col in
            if row==2 && col==1 {return self.blue}
            return row<=1 ? self.red : [0,0,0,0]
        })
        let blocked=UpperSurfaceColorFill.fill(upper)
        XCTAssertNotEqual(estimate(blocked.mesh,2),red)
        XCTAssertEqual(blocked.mesh.surfaceColors,upper.surfaceColors)
    }
    func testCornerSharedVertexIsBarrier() {
        let corner=wall(position:{x,y in x<=0 ? .init(x,y,-2) : .init(0,y,-2+x)})
        let result=UpperSurfaceColorFill.fill(corner)
        XCTAssertNotEqual(estimate(result.mesh,2),red)
        XCTAssertGreaterThan(result.diagnostics.rejected["cornerOrNonVertical"] ?? 0,0)
    }
    func testDisconnectedCoplanarPatchesCannotSupplyColors() {
        let base=wall()
        // Remove the triangles bridging measured and unmeasured rows, but keep their nearby positions.
        var indices=[UInt32]()
        for i in stride(from:0,to:base.indices.count,by:3) {
            let ids=Array(base.indices[i..<i+3])
            if !(ids.contains(where:{$0<10}) && ids.contains(where:{$0>=10})) {indices+=ids}
        }
        let separated=MeshSnapshot(id:base.id,transform:base.transform,vertices:base.vertices,indices:indices,surfaceColors:base.surfaceColors)
        XCTAssertNil(UpperSurfaceColorFill.fill(separated).mesh.inferredSurfaceColors)
    }
    func testOneHeightLevelAndOnlyOneSideAreNotEnough() {
        let oneRow=wall(colors:{row,_ in row==1 ? self.red : [0,0,0,0]})
        XCTAssertNil(UpperSurfaceColorFill.fill(oneRow).mesh.inferredSurfaceColors)
        let oneSide=wall(colors:{row,col in row<=1 && col<2 ? self.red : [0,0,0,0]})
        XCTAssertNotEqual(estimate(UpperSurfaceColorFill.fill(oneSide).mesh,2),red)
    }
    func testParallelOffsetAndHorizontalFloorAreNotFilled() {
        let offset=wall(position:{x,y in .init(x,y,y>=0.2 ? -1.95 : -2)})
        XCTAssertNotEqual(estimate(UpperSurfaceColorFill.fill(offset).mesh,2),red)
        let floor=wall(position:{x,y in .init(x,0,-2-y)})
        let result=UpperSurfaceColorFill.fill(floor)
        XCTAssertNil(result.mesh.inferredSurfaceColors);XCTAssertEqual(result.diagnostics.candidateVertices,0)
    }
    func testGravityAndPlaneChecksUseWorldCoordinates() {
        var pose=simd_float4x4(simd_quatf(angle:.pi/2,axis:SIMD3(0,1,0)))
        pose.columns.3=SIMD4(4,1,5,1)
        let transform=(0..<4).flatMap {col in (0..<4).map {pose[col][$0]}}
        XCTAssertEqual(estimate(UpperSurfaceColorFill.fill(wall(transform:transform)).mesh,2),red)
    }
    func testNewScanBakesObservationsThenInfersOnlyUnseenUpperVertices() {
        let mesh=wall(observe:false),frames=[frame(time:1),frame(time:2)]
        let before=SurfaceColorBaker.bakeWithDiagnostics([mesh],frames:frames,fillUpperSurfaces:false)
        let after=SurfaceColorBaker.bakeWithDiagnostics([mesh],frames:frames)
        XCTAssertNil(before.meshes[0].inferredSurfaceColors)
        XCTAssertEqual(after.meshes[0].surfaceColors,before.meshes[0].surfaceColors)
        XCTAssertEqual(estimate(after.meshes[0],3),red)
        XCTAssertEqual(estimate(after.meshes[0],5),[0,0,0,0])
        XCTAssertGreaterThan(after.diagnostics.coloredAreaFraction,before.diagnostics.coloredAreaFraction)
        XCTAssertEqual(after.diagnostics.coloredVertices,before.diagnostics.coloredVertices)
        XCTAssertGreaterThan(after.diagnostics.upperFill?.inferredTriangles ?? 0,0)
        XCTAssertGreaterThan(after.diagnostics.upperFill?.inferredAreaSquareMeters ?? 0,0)
        XCTAssertNil(SurfaceColorBaker.bakeWithDiagnostics([mesh],frames:frames,policy:.strict).meshes[0].inferredSurfaceColors)
    }
    func testPeopleAndForegroundRejectionsCannotBeOverwrittenByInference() {
        for mask in [false,true] {
            let frames=[frame(time:1,cy:12,mask:mask,occluder:!mask),frame(time:2,cy:12,mask:mask,occluder:!mask)]
            let result=SurfaceColorBaker.bakeWithDiagnostics([wall(observe:false)],frames:frames)
            XCTAssertNil(result.meshes[0].inferredSurfaceColors)
            XCTAssertGreaterThan(result.diagnostics.upperFill?.rejected["observationConflict"] ?? 0,0)
        }
    }
    func testProvenanceValidationLegacyDecodeAndStoreRoundTrip() async throws {
        let original=wall(),filled=UpperSurfaceColorFill.fill(original).mesh
        let legacy=try JSONDecoder().decode(MeshSnapshot.self,from:JSONEncoder().encode(original))
        XCTAssertNil(legacy.inferredSurfaceColors);XCTAssertEqual(legacy.surfaceColors,original.surfaceColors)
        let noColors=wall(observe:false)
        XCTAssertNil(UpperSurfaceColorFill.fill(noColors).mesh.inferredSurfaceColors)
        func invalid(_ colors: Data?,_ inferred: Data) -> MeshSnapshot {
            MeshSnapshot(id:original.id,transform:original.transform,vertices:original.vertices,indices:original.indices,
                         surfaceColors:colors,inferredSurfaceColors:inferred)
        }
        XCTAssertThrowsError(try invalid(nil,Data(repeating:0,count:original.vertices.count*4)).validate())
        XCTAssertThrowsError(try invalid(original.surfaceColors,Data([0,0,0,255])).validate())
        XCTAssertThrowsError(try invalid(original.surfaceColors,original.surfaceColors!).validate()) // Direct/estimated overlap.
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root)
        let saved=try await store.save(id:UUID(),name:"위쪽 보완",frame:StageFrame(origin:.init(0,0,0),front:.init(0,0,-1)),
            checkpoint:.init(2,0,0),worldMap:Data([1]),meshes:[filled],device:"test",appVersion:"1")
        let loaded=try await store.load(saved.id)
        XCTAssertEqual(loaded.meshes,[filled]);XCTAssertEqual(loaded.meshes[0].surfaceColors,original.surfaceColors)
        var report=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(SurfaceColorDiagnostics(policy:"relaxed"))) as? [String:Any])
        report["version"]=1;report.removeValue(forKey:"upperFill")
        XCTAssertNil(try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:JSONSerialization.data(withJSONObject:report)).upperFill)
    }
}
