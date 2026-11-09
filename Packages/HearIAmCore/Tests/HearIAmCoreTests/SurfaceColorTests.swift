import XCTest
import simd
@testable import HearIAmCore

final class SurfaceColorTests: XCTestCase {
    private let identity: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]
    private func mesh(vertices: [Point3]? = nil, transform: [Float]? = nil, colors: Data? = nil) -> MeshSnapshot {
        MeshSnapshot(id:UUID(),transform:transform ?? identity,
                     vertices:vertices ?? [.init(-0.5,-0.4,-2),.init(0.5,-0.4,-2),.init(0,0.4,-2)],
                     indices:[0,1,2],surfaceColors:colors)
    }
    private func frame(time: Double=1, color: [UInt8]=[180,30,40],depth: Float=2,confidence: UInt8=2,
                       pose: simd_float4x4=matrix_identity_float4x4, split: Bool=false) -> SurfaceColorFrame {
        let w=32,h=24
        var rgb=[UInt8]()
        for y in 0..<h {for _ in 0..<w {rgb += split && y<h/2 ? [30,40,180] : color}}
        return SurfaceColorFrame(time:time,cameraTransform:pose,width:w,height:h,fx:20,fy:20,cx:16,cy:12,
                                 rgb:rgb,depth:Array(repeating:depth,count:w*h),confidence:Array(repeating:confidence,count:w*h))
    }
    private func edited(_ source: SurfaceColorFrame,missing: [Int]=[],depthChanges: [Int:Float]=[:],
                        people: [Int]=[]) -> SurfaceColorFrame {
        var depth=source.depth,confidence=source.confidence,rgb=source.rgb
        var mask=people.isEmpty ? nil : [UInt8](repeating:0,count:depth.count)
        for i in missing {confidence[i]=0;rgb[i*3]=0;rgb[i*3+1]=255;rgb[i*3+2]=0}
        for (i,value) in depthChanges {depth[i]=value}
        for i in people {mask?[i]=1;confidence[i]=0}
        return SurfaceColorFrame(time:source.time,cameraTransform:source.cameraTransform,
            width:source.width,height:source.height,fx:source.fx,fy:source.fy,cx:source.cx,cy:source.cy,
            rgb:rgb,depth:depth,confidence:confidence,personMask:mask)
    }
    func testLegacyDecodeAndColorValidation() throws {
        let original=mesh(),encoded=try JSONEncoder().encode(original)
        let json=try XCTUnwrap(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        XCTAssertNil(json["surfaceColors"])
        let old=try JSONDecoder().decode(MeshSnapshot.self,from:encoded)
        XCTAssertNil(old.surfaceColors);XCTAssertEqual(old,original)
        XCTAssertThrowsError(try mesh(colors:Data([1,2,3,255])).validate())
        XCTAssertThrowsError(try mesh(colors:Data(repeating:1,count:12)).validate())
        XCTAssertNoThrow(try mesh(colors:Data(repeating:0,count:12)).validate())
    }
    func testCameraProjectionAndImageYDirection() throws {
        let original=mesh()
        let baked=SurfaceColorBaker.bake([original],frames:[frame(split:true),frame(time:2,split:true)])[0]
        let colors=try XCTUnwrap(baked.surfaceColors)
        XCTAssertEqual(Array(colors[0..<4]),[180,30,40,255])
        XCTAssertEqual(Array(colors[8..<12]),[30,40,180,255]) // +Y projects into the TOP of the unrotated image.
        XCTAssertEqual(baked.vertices,original.vertices);XCTAssertEqual(baked.indices,original.indices)
        XCTAssertEqual(baked.transform,original.transform);XCTAssertEqual(baked.id,original.id)
    }
    func testCorrectedCameraPoseAndFinalMeshTopology() throws {
        var pose=simd_float4x4(simd_quatf(angle:.pi/2,axis:SIMD3(0,1,0)))
        pose.columns.3=SIMD4(10,1,4,1)
        let transform=(0..<4).flatMap {i in (0..<4).map {pose[i][$0]}}
        let final=mesh(vertices:[.init(0,0.4,-2),.init(-0.5,-0.4,-2),.init(0.5,-0.4,-2)],transform:transform)
        let observations=[frame(split:true).withCameraTransform(pose),frame(time:2,split:true).withCameraTransform(pose)]
        let colors=try XCTUnwrap(SurfaceColorBaker.bake([final],frames:observations)[0].surfaceColors)
        XCTAssertEqual(Array(colors[0..<4]),[30,40,180,255])
        XCTAssertEqual(Array(colors[4..<8]),[180,30,40,255])
    }
    func testFloorAndUnobservedSurfacesStayUncolored() {
        let floor=mesh(vertices:[.init(-0.5,0,-2),.init(0.5,0,-2),.init(0,0,-1)])
        let behind=mesh(vertices:[.init(-0.5,-0.4,2),.init(0.5,-0.4,2),.init(0,0.4,2)])
        for original in [floor,behind] {
            XCTAssertNil(SurfaceColorBaker.bake([original],frames:[frame(),frame(time:2)])[0].surfaceColors)
        }
        XCTAssertEqual(SurfaceColorBaker.bake([floor],frames:[]),[floor])
    }
    func testOcclusionLowConfidenceAndSingleObservationFallBack() {
        for frames in [[frame()], [frame(),frame(time:1.1)],
                       [frame(depth:1),frame(time:2,depth:1)],
                       [frame(confidence:0),frame(time:2,confidence:0)],
                       [frame(),frame(time:2,color:[30,40,180])]] {
            XCTAssertNil(SurfaceColorBaker.bake([mesh()],frames:frames)[0].surfaceColors)
        }
    }
    func testPassingForegroundDoesNotPaintWallAndDarkCurtainIsAllowed() throws {
        let colors=try XCTUnwrap(SurfaceColorBaker.bake([mesh()],frames:[
            frame(color:[12,12,12]),frame(time:2,color:[12,12,12]),frame(time:3,color:[200,30,30],depth:1)
        ])[0].surfaceColors)
        XCTAssertEqual(Array(colors[0..<4]),[12,12,12,255])
    }
    func testColorOutlierRejectedAcrossMultipleFrames() throws {
        let colors=try XCTUnwrap(SurfaceColorBaker.bake([mesh()],frames:[
            frame(),frame(time:2),frame(time:3,color:[30,40,180])
        ])[0].surfaceColors)
        XCTAssertEqual(Array(colors[0..<4]),[180,30,40,255])
    }
    func testObservationBufferBoundedAndKeepsDistinctView() {
        var buffer=SurfaceColorFrames(),pose=matrix_identity_float4x4
        pose.columns.3.x=8
        let distinct=frame(pose:pose)
        buffer.append(distinct)
        for n in 0..<120 {buffer.append(frame(time:Double(n)))}
        XCTAssertEqual(buffer.frames.count,SurfaceColorFrames.capacity)
        XCTAssertTrue(buffer.frames.contains {$0.id==distinct.id})
    }
    func testYCbCrRangeAndMatrixConversion() {
        for full in [true,false] {
            let black=SurfaceCameraColor.rgb(y:full ? 0 : 16,cb:128,cr:128,fullRange:full,kr:0.299,kb:0.114)
            let white=SurfaceCameraColor.rgb(y:full ? 255 : 235,cb:128,cr:128,fullRange:full,kr:0.2126,kb:0.0722)
            XCTAssertEqual(black,.zero);XCTAssertEqual(white,SIMD3(repeating:1))
        }
        let red=SurfaceCameraColor.rgb(y:76,cb:85,cr:255,fullRange:true,kr:0.299,kb:0.114)
        XCTAssertGreaterThan(red.x,0.98);XCTAssertLessThan(red.y,0.02);XCTAssertLessThan(red.z,0.02)
    }
    func testSavedColorsSurviveStoreAndDoNotChangeFloorClassification() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {try? FileManager.default.removeItem(at:root)}
        let store=ScanStore(root:root),source=mesh()
        let result=SurfaceColorBaker.bakeWithDiagnostics([source],frames:[frame(),frame(time:2)])
        let colored=result.meshes[0]
        let saved=try await store.save(id:UUID(),name:"벽 색상",frame:StageFrame(origin:.init(0,0,0),front:.init(0,0,-1)),
                                       checkpoint:.init(2,0,0),worldMap:Data([1]),meshes:[colored],device:"test",appVersion:"1",
                                       surfaceColorDiagnostics:result.diagnostics)
        let loaded=try await store.load(saved.id)
        XCTAssertEqual(loaded.meshes,[colored])
        let reportURL=root.appendingPathComponent(saved.id.uuidString).appendingPathComponent("surface-colors.json")
        XCTAssertEqual(try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:Data(contentsOf:reportURL)),result.diagnostics)
        let area=try StageArea(corners:[.init(0,0,0),.init(4,0,0),.init(4,0,-3),.init(0,0,-3)])
        let route=try StageRoute(area:area,points:[.init(0.2,0.2),.init(1,1)],obstacles:[])
        let before=ReplaySurfaceMesh(mesh:source,route:route),after=ReplaySurfaceMesh(mesh:loaded.meshes[0],route:route)
        XCTAssertEqual(after.surfaceColors,colored.surfaceColors)
        XCTAssertEqual(before.floorIndices,after.floorIndices);XCTAssertEqual(before.surfaceIndices,after.surfaceIndices)
        XCTAssertEqual(before.vertices,after.vertices)
        // A scan containing no new field continues to load through the unchanged archive format.
        let legacy=try await store.save(id:UUID(),name:"기존 무대",frame:saved.frame,checkpoint:saved.checkpoint,
                                        worldMap:Data([1]),meshes:[source],device:"test",appVersion:"1")
        let old=try await store.load(legacy.id)
        XCTAssertNil(old.meshes[0].surfaceColors)
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent(legacy.id.uuidString).appendingPathComponent("surface-colors.json").path))
    }

    func testSixValidNeighborsRecoverHoleWithoutUsingMissingPixelColors() throws {
        // First vertex projects to (11,16); only its upper row is unavailable, with deliberately WRONG green RGB.
        let missing=[15*32+10,15*32+11,15*32+12]
        let frames=[edited(frame(),missing:missing),edited(frame(time:2),missing:missing)]
        let strict=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:frames,policy:.strict)
        let relaxed=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:frames)
        XCTAssertEqual(strict.diagnostics.grayTrianglesByMissingVertices,["1":1])
        XCTAssertEqual(strict.diagnostics.rejectedObservations["neighborhoodDepthUnavailable"],2)
        XCTAssertEqual(strict.diagnostics.coloredAreaFraction,0)
        XCTAssertEqual(relaxed.diagnostics.coloredAreaFraction,1)
        XCTAssertEqual(relaxed.diagnostics.partialNeighborhoodObservations,2)
        XCTAssertEqual(relaxed.diagnostics.acceptedObservations,6)
        XCTAssertEqual(relaxed.diagnostics.eligibleVertices,3)
        XCTAssertEqual(relaxed.diagnostics.coloredVertices,3)
        XCTAssertEqual(relaxed.diagnostics.eligibleAreaSquareMeters,0.4,accuracy:1e-6)
        let colors=try XCTUnwrap(relaxed.meshes[0].surfaceColors)
        XCTAssertEqual(Array(colors[0..<4]),[180,30,40,255])
    }
    func testNaNDepthMayBeSkippedButFourMissingNeighborsStillFail() {
        let upper=[15*32+10,15*32+11,15*32+12]
        let valid=[edited(frame(),depthChanges:[upper[0]:.nan]),edited(frame(time:2),depthChanges:[upper[0]:.nan])]
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:valid).diagnostics.coloredTriangles,1)
        let missing=upper+[16*32+10]
        let rejected=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[edited(frame(),missing:missing),edited(frame(time:2),missing:missing)])
        XCTAssertEqual(rejected.diagnostics.rejectedObservations["insufficientNeighbors"],2)
        XCTAssertEqual(rejected.diagnostics.grayTrianglesByMissingVertices,["1":1])
    }
    func testCenterDepthRemainsRequiredWithEightGoodNeighbors() {
        let center=16*32+11
        let result=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[edited(frame(),missing:[center]),edited(frame(time:2),missing:[center])])
        XCTAssertEqual(result.diagnostics.rejectedObservations["centerDepthUnavailable"],2)
        XCTAssertEqual(result.diagnostics.grayTrianglesByMissingVertices,["1":1])
    }
    func testForegroundAndBackgroundEdgesStillVetoWithEightGoodNeighbors() {
        let neighbor=15*32+10
        for (depth,reason): (Float,String) in [(1,"foregroundOcclusion"),(3,"depthMismatch")] {
            let result=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[
                edited(frame(),depthChanges:[neighbor:depth]),edited(frame(time:2),depthChanges:[neighbor:depth])])
            XCTAssertEqual(result.diagnostics.rejectedObservations[reason],2)
            XCTAssertEqual(result.diagnostics.grayTrianglesByMissingVertices,["1":1])
        }
    }
    func testMaskedPersonNeighborCannotBecomeAnIgnorableDepthHole() {
        let neighbor=15*32+10
        let first=edited(frame(),people:[neighbor]),second=edited(frame(time:2),people:[neighbor])
        XCTAssertEqual(first.withCameraTransform(matrix_identity_float4x4).personMask,first.personMask)
        let result=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[first,second])
        XCTAssertEqual(result.diagnostics.rejectedObservations["personMask"],2)
        XCTAssertEqual(result.diagnostics.grayTrianglesByMissingVertices,["1":1])
    }
    func testSlantedWallUsesDepthOfEachRayWithoutLooseningOcclusionTolerance() {
        let slope=1.1
        let wall=mesh(vertices:[.init(-0.5,-0.4,-2-slope*0.5),.init(0.5,-0.4,-2+slope*0.5),.init(0,0.4,-2)])
        var depths=[Int:Float]()
        for y in 0..<24 {for x in 0..<32 {depths[y*32+x]=2/(1+Float(slope)*Float(x-16)/20)}}
        let frames=[edited(frame(),depthChanges:depths),edited(frame(time:2),depthChanges:depths)]
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([wall],frames:frames).diagnostics.coloredTriangles,1)
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([wall],frames:frames,policy:.strict).diagnostics.coloredTriangles,0)
        // An actual foreground pixel is still rejected on that slanted plane.
        depths[7*32+15]=0.5
        let occluded=[edited(frame(),depthChanges:depths),edited(frame(time:2),depthChanges:depths)]
        let result=SurfaceColorBaker.bakeWithDiagnostics([wall],frames:occluded)
        XCTAssertEqual(result.diagnostics.coloredTriangles,0)
        XCTAssertGreaterThan(result.diagnostics.rejectedObservations["foregroundOcclusion"] ?? 0,0)
    }
    func testDiagnosticsAccountForAttemptsAndTemporalRejections() {
        for frames in [[frame()], [frame(),frame(time:1.1)], [frame(),frame(time:2,color:[30,40,180])]] {
            let d=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:frames).diagnostics
            XCTAssertEqual(d.attemptedObservations,d.acceptedObservations+d.rejectedObservations.values.reduce(0,+))
            XCTAssertEqual(d.eligibleVertices,d.coloredVertices+d.missingVertices.values.reduce(0,+))
            XCTAssertEqual(d.eligibleTriangles,d.coloredTriangles+d.grayTrianglesByMissingVertices.values.reduce(0,+))
            XCTAssertEqual(d.coloredTriangles,0)
        }
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame()]).diagnostics.missingVertices["insufficientObservations"],3)
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame(),frame(time:1.1)]).diagnostics.missingVertices["insufficientTimeSeparation"],3)
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame(),frame(time:2,color:[30,40,180])]).diagnostics.missingVertices["inconsistentColor"],3)
    }
    func testFolderCoverageExcludesFloorAndUsesTriangleArea() throws {
        let area=try StageArea(corners:[.init(0,0,0),.init(4,0,0),.init(4,0,-3),.init(0,0,-3)])
        let route=try StageRoute(area:area,points:[.init(0.2,0.2),.init(1,1)],obstacles:[])
        let floor=mesh(vertices:[.init(0,0,0),.init(4,0,0),.init(0,0,-3)])
        let unobserved=mesh(vertices:[.init(-1,-0.8,2),.init(1,-0.8,2),.init(0,0.8,2)])
        let result=SurfaceColorBaker.bakeWithDiagnostics([mesh(),unobserved,floor],frames:[frame(),frame(time:2)],route:route)
        let d=result.diagnostics
        XCTAssertEqual(d.coverageScope,"folder");XCTAssertEqual(d.eligibleTriangles,2)
        XCTAssertEqual(d.coloredTriangles,1);XCTAssertEqual(d.grayTrianglesByMissingVertices,["3":1])
        XCTAssertEqual(d.coloredAreaFraction,0.2,accuracy:1e-6) // Colored small wall .4m² / total 2m², not 1/2 triangles.
        XCTAssertNil(result.meshes[2].surfaceColors)
    }
}
