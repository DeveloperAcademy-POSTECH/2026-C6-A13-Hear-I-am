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
    func testWallObservationPairSurvivesLongScanAndStillColorsFinalMesh() {
        var paired=SurfaceColorFrames(),legacy=SurfaceColorFrames(policy:.viewpointDiversity)
        let first=frame(time:1),second=frame(time:2)
        for f in [first,second] {paired.append(f);legacy.append(f)}
        for n in 1...70 {
            var pose=matrix_identity_float4x4;pose.columns.3.x=Float(n)*8
            let f=frame(time:Double(n+10),pose:pose)
            paired.append(f);legacy.append(f)
        }
        XCTAssertEqual(paired.frames.count,48)
        XCTAssertTrue(paired.frames.contains {$0.id==first.id})
        XCTAssertTrue(paired.frames.contains {$0.id==second.id})
        XCTAssertGreaterThan(paired.coverage.paired,0)
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:paired.frames).diagnostics.coloredTriangles,1)
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:legacy.frames).diagnostics.coloredTriangles,0)
    }
    func testRegionPairsNeedTimeColorAndUnmaskedDepth() {
        for second in [frame(time:1.1),frame(time:2,color:[30,40,180]),frame(time:2,confidence:0),
                       edited(frame(time:2),people:Array(0..<(32*24)))] {
            var buffer=SurfaceColorFrames();buffer.append(frame());buffer.append(second)
            XCTAssertEqual(buffer.coverage.paired,0)
        }
        var buffer=SurfaceColorFrames();buffer.append(frame());buffer.append(frame(time:2))
        XCTAssertGreaterThan(buffer.coverage.paired,0)
    }
    func testFullPairedBufferStillAdmitsANewWallPair() {
        var buffer=SurfaceColorFrames()
        for n in 0..<24 {
            var pose=matrix_identity_float4x4;pose.columns.3.x=Float(n)*8
            buffer.append(frame(time:Double(n)*2,pose:pose))
            buffer.append(frame(time:Double(n)*2+1,pose:pose))
        }
        var newPose=matrix_identity_float4x4;newPose.columns.3.x=300
        let first=frame(time:60,pose:newPose),second=frame(time:61,pose:newPose)
        buffer.append(first)
        XCTAssertTrue(buffer.frames.contains {$0.id==first.id})
        buffer.append(second)
        XCTAssertTrue(buffer.frames.contains {$0.id==first.id})
        XCTAssertTrue(buffer.frames.contains {$0.id==second.id})
        XCTAssertEqual(buffer.frames.count,48)
    }
    func testFullResolutionLongStreamKeepsBoundedPairedCoverage() {
        var buffer=SurfaceColorFrames()
        let count=160*120
        let rgb: [UInt8]=Array(repeating:[180,30,40],count:count).flatMap {$0}
        let start=ProcessInfo.processInfo.systemUptime
        for n in 0..<90 {
            let f=SurfaceColorFrame(time:Double(n)*0.5,cameraTransform:matrix_identity_float4x4,
                width:160,height:120,fx:100,fy:100,cx:80,cy:60,rgb:rgb,
                depth:Array(repeating:2,count:count),confidence:Array(repeating:2,count:count))
            buffer.append(f)
        }
        print("SURFACE_RETENTION_BENCHMARK: 160x120 frames=90 meanMs=\((ProcessInfo.processInfo.systemUptime-start)*1000/90)")
        XCTAssertEqual(buffer.frames.count,48)
        XCTAssertGreaterThan(buffer.coverage.paired,0)
    }
    func testCaptureReportsAndObservationBucketsRoundTripWithoutChangingOldReports() throws {
        let d=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame()]).diagnostics
        XCTAssertEqual(d.observationCounts,["one":3])
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[]).diagnostics.observationCounts,["zero":3])
        XCTAssertEqual(SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame(),frame(time:2)]).diagnostics.observationCounts,["twoOrMore":3])
        var report=d;report.capture=SurfaceColorCaptureDiagnostics()
        XCTAssertEqual(try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:JSONEncoder().encode(report)),report)
        var old=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(report)) as? [String:Any])
        old["version"]=2
        for key in ["capture","observationCounts","directColoredTriangles","directColoredAreaSquareMeters","depthAnalysis"] {old.removeValue(forKey:key)}
        let decoded=try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:JSONSerialization.data(withJSONObject:old))
        XCTAssertNil(decoded.capture);XCTAssertNil(decoded.observationCounts)
        XCTAssertNil(decoded.directColoredTriangles);XCTAssertNil(decoded.directColoredAreaSquareMeters)
        XCTAssertNil(decoded.depthAnalysis)
    }
    func testDepthDiagnosticsSeparateSmallOffsetsFromBroadDepthDifferences() throws {
        for (depth,pattern,excess): (Float,String,String) in [
            (1.92,"mostlyNearSmallOffset","upTo0.02"),(1,"mostlyNearLargeOffset","over0.15"),
            (2.08,"mostlyFarSmallOffset","upTo0.02"),(3,"mostlyFarLargeOffset","over0.15")] {
            let result=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame(depth:depth),frame(time:2,depth:depth)])
            let d=try XCTUnwrap(result.diagnostics.depthAnalysis)
            XCTAssertEqual(d.rejectedObservations,6)
            XCTAssertEqual(d.firstFailureLocation,["center":6])
            XCTAssertEqual(d.footprintPatterns,[pattern:6])
            XCTAssertEqual(d.firstExcessOverToleranceMeters,[excess:6])
            XCTAssertEqual(d.reliablePixelsPerFootprint,["9":6])
            XCTAssertEqual(d.uncoloredVerticesWithDepthConflict,3)
            XCTAssertEqual(d.uncoloredAcceptedViews,["zero":3])
            XCTAssertEqual(d.framesWithoutPersonMask,2)
            XCTAssertNil(result.meshes[0].surfaceColors) // Small offsets still reject; diagnostics never relax tolerance.
        }
    }
    func testDepthDiagnosticsDetectNeighborOnlyAndMixedFootprints() throws {
        let near=15*32+10,far=15*32+12
        for mixed in [false,true] {
            let changes: [Int:Float]=mixed ? [near:1,far:3] : [near:1]
            let result=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[edited(frame(),depthChanges:changes)])
            let d=try XCTUnwrap(result.diagnostics.depthAnalysis)
            XCTAssertEqual(d.rejectedObservations,1)
            XCTAssertEqual(d.firstFailureReason,["foregroundOcclusion":1])
            XCTAssertEqual(d.firstFailureLocation,["neighbor":1])
            XCTAssertEqual(d.footprintPatterns,[mixed ? "mixedSigns" : "neighborOnlyConflict":1])
            XCTAssertEqual(d.uncoloredSignPatterns,[mixed ? "mixedWithinView" : "nearOnly":1])
        }
        let masked=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[edited(frame(),people:[near])]).diagnostics
        XCTAssertEqual(masked.rejectedObservations["personMask"],1)
        XCTAssertEqual(masked.depthAnalysis?.rejectedObservations,0) // Person rejection is not relabeled as depth error.
        XCTAssertEqual(masked.depthAnalysis?.framesWithPersonMask,1)
    }
    func testDepthDiagnosticsDistinguishViewSignChangesAndCleanObservations() throws {
        let conflicting=[frame(depth:1.92),frame(time:2,depth:2.08),frame(time:3)]
        for cleanPair in [false,true] {
            let result=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:conflicting+(cleanPair ? [frame(time:4)] : []))
            let d=try XCTUnwrap(result.diagnostics.depthAnalysis)
            XCTAssertEqual(d.verticesWithDepthConflict,3)
            XCTAssertEqual(d.conflictViewsPerVertex,["twoOrThree":3])
            XCTAssertEqual(d.signPatternsAcrossViews,["signChangesAcrossViews":3])
            XCTAssertEqual(d.acceptedViewsAtConflictedVertices,[cleanPair ? "twoOrMore" : "one":3])
            XCTAssertEqual(d.directVerticesWithDepthConflict,cleanPair ? 3 : 0)
            XCTAssertEqual(d.uncoloredVerticesWithDepthConflict,cleanPair ? 0 : 3)
        }
    }
    func testInvalidPlanePredictionHasSeparateDiagnosticBucket() throws {
        let source=frame()
        let observation=SurfaceColorFrame(time:1,cameraTransform:source.cameraTransform,width:32,height:24,
            fx:0.1,fy:20,cx:16,cy:12,rgb:source.rgb,depth:source.depth,confidence:source.confidence)
        let slanted=mesh(vertices:[.init(-0.5,-0.4,-2.55),.init(0.5,-0.4,-1.45),.init(0,0.4,-2)])
        let d=try XCTUnwrap(SurfaceColorBaker.bakeWithDiagnostics([slanted],frames:[observation]).diagnostics.depthAnalysis)
        XCTAssertEqual(d.footprintPatterns,["invalidPrediction":3])
        XCTAssertEqual(d.firstResidualMagnitudeMeters,["invalidPrediction":3])
        XCTAssertEqual(d.firstFailureReason,["depthMismatch":3])
    }
    func testDepthDiagnosticsDoNotChangeAnyColorOrExistingRejectionMetric() throws {
        let source=mesh(),neighbor=15*32+10
        let cases: [[SurfaceColorFrame]]=[
            [frame(),frame(time:2)],[frame(depth:1.92),frame(time:2,depth:2.08)],
            [frame(),frame(time:2),frame(time:3,depth:1)],
            [edited(frame(),depthChanges:[neighbor:1])],[edited(frame(),people:[neighbor])],
            [edited(frame(),missing:[neighbor])],[frame(confidence:0)],
            [frame(color:[255,255,255])],[frame(),frame(time:2,color:[30,40,180])]]
        for policy: SurfaceColorBaker.SamplingPolicy in [.relaxed,.strict] {for frames in cases {
            let on=SurfaceColorBaker.bakeWithDiagnostics([source],frames:frames,policy:policy)
            let off=SurfaceColorBaker.bakeWithDiagnostics([source],frames:frames,policy:policy,collectDepthDiagnostics:false)
            XCTAssertEqual(on.meshes,off.meshes)
            var report=on.diagnostics;report.depthAnalysis=nil
            XCTAssertEqual(report,off.diagnostics)
            let d=try XCTUnwrap(on.diagnostics.depthAnalysis)
            XCTAssertEqual(d.rejectedObservations,
                (on.diagnostics.rejectedObservations["foregroundOcclusion"] ?? 0)+(on.diagnostics.rejectedObservations["depthMismatch"] ?? 0))
            XCTAssertEqual(d.rejectedObservations,d.footprintPatterns.values.reduce(0,+))
            XCTAssertEqual(d.rejectedObservations,d.firstResidualMagnitudeMeters.values.reduce(0,+))
            XCTAssertEqual(d.verticesWithDepthConflict,d.uncoloredVerticesWithDepthConflict+d.directVerticesWithDepthConflict)
        }}
    }
    func testDepthDiagnosticsVersionThreeCompatibilityAndRoundTrip() throws {
        let report=SurfaceColorBaker.bakeWithDiagnostics([mesh()],frames:[frame(depth:1.92)]).diagnostics
        XCTAssertEqual(report.version,5)
        XCTAssertEqual(try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:JSONEncoder().encode(report)),report)
        var legacy=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(report)) as? [String:Any])
        legacy["version"]=3;legacy.removeValue(forKey:"depthAnalysis")
        XCTAssertNil(try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:JSONSerialization.data(withJSONObject:legacy)).depthAnalysis)
    }
    func testNativeDepthRasterKeepsRGBAndDepthOnTheSameRay() throws {
        let k=simd_float3x3(columns:(SIMD3(1200,0,0),SIMD3(0,1200,0),SIMD3(960,720,1)))
        let raster=try XCTUnwrap(SurfaceColorRasterMapping(imageWidth:1920,imageHeight:1440,
            depthWidth:256,depthHeight:192,intrinsics:k))
        XCTAssertEqual(raster.width,128);XCTAssertEqual(raster.height,96)
        XCTAssertEqual(raster.cx,64,accuracy:1e-5);XCTAssertEqual(raster.cy,48,accuracy:1e-5)
        for y in 0..<raster.height {for x in 0..<raster.width {
            let rayX=(Float(x)-raster.cx)/raster.fx,rayY=(Float(y)-raster.cy)/raster.fy
            XCTAssertEqual(rayX,(Float(raster.depthX(x))-128)/160,accuracy:1e-6)
            XCTAssertEqual(rayY,(Float(raster.depthY(y))-96)/160,accuracy:1e-6)
            XCTAssertEqual(rayX,(Float(raster.imageX(x))-960)/1200,accuracy:1e-6)
            XCTAssertEqual(rayY,(Float(raster.imageY(y))-720)/1200,accuracy:1e-6)
        }}
        // Original 256 -> 160 nearest sampling paired a depth ray at native x=2 with RGB x=18.
        let oldDepthX=Int((1.5)*256/160),oldImageX=Int((1.5)*1920/160)
        XCTAssertNotEqual(Float(oldDepthX)/256,Float(oldImageX)/1920)
        // Sampling may skip native depth pixels, but a person mask on that ray must survive.
        XCTAssertTrue(raster.maskRange(1,depthSize:256,maskSize:256).contains(3))
    }
    func testNativeRasterHandlesOddDimensionsAndRejectsInvalidCalibration() throws {
        let k=simd_float3x3(columns:(SIMD3(400,0,0),SIMD3(0,400,0),SIMD3(320,240,1)))
        let r=try XCTUnwrap(SurfaceColorRasterMapping(imageWidth:640,imageHeight:480,depthWidth:255,depthHeight:191,intrinsics:k))
        XCTAssertLessThan(r.depthX(r.width-1),255);XCTAssertLessThan(r.depthY(r.height-1),191)
        XCTAssertEqual((Float(r.width-1)-r.cx)/r.fx,(Float(r.depthX(r.width-1))-320*255/640)/(400*255/640),accuracy:1e-6)
        XCTAssertNil(SurfaceColorRasterMapping(imageWidth:0,imageHeight:480,depthWidth:256,depthHeight:192,intrinsics:k))
    }
    func testSlantedNativeDepthRaysMatchCenterAndNeighborsWithoutToleranceChange() throws {
        let k=simd_float3x3(columns:(SIMD3(40,0,0),SIMD3(0,40,0),SIMD3(32,24,1)))
        let r=try XCTUnwrap(SurfaceColorRasterMapping(imageWidth:64,imageHeight:48,depthWidth:32,depthHeight:24,intrinsics:k))
        let slope: Float=1.1
        let source=mesh(vertices:[.init(-0.5,-0.4,-2.55),.init(0.5,-0.4,-1.45),.init(0,0.4,-2)])
        var depths=[Float]()
        for _ in 0..<r.height {for x in 0..<r.width {depths.append(2/(1+slope*(Float(r.depthX(x))-16)/20))}}
        func observation(_ time: Double) -> SurfaceColorFrame {
            SurfaceColorFrame(time:time,cameraTransform:matrix_identity_float4x4,width:r.width,height:r.height,
                fx:r.fx,fy:r.fy,cx:r.cx,cy:r.cy,rgb:frame().rgb,depth:depths,confidence:frame().confidence)
        }
        let result=SurfaceColorBaker.bakeWithDiagnostics([source],frames:[observation(1),observation(2)])
        XCTAssertEqual(result.diagnostics.coloredTriangles,1)
        XCTAssertEqual(result.diagnostics.depthAnalysis?.rejectedObservations,0)
        let bad=edited(observation(3),depthChanges:[7*32+15:0.5])
        let veto=SurfaceColorBaker.bakeWithDiagnostics([source],frames:[bad,edited(observation(4),depthChanges:[7*32+15:0.5])])
        XCTAssertEqual(veto.diagnostics.coloredTriangles,0)
        XCTAssertGreaterThan(veto.diagnostics.rejectedObservations["foregroundOcclusion"] ?? 0,0)
    }
    func testLargeWorldPoseCorrectionNeedsCoherentMeshAndCameraSnapshot() throws {
        let original=mesh(),base=frame(),second=frame(time:2)
        var pose=matrix_identity_float4x4;pose.columns.3.z=0.8
        let transformed=mesh(transform:(0..<4).flatMap {c in (0..<4).map {pose[c][$0]}})
        let corrected=[base.withCameraTransform(pose),second.withCameraTransform(pose)]
        let stale=SurfaceColorBaker.bakeWithDiagnostics([original],frames:corrected)
        XCTAssertEqual(stale.diagnostics.coloredTriangles,0)
        XCTAssertGreaterThan(stale.diagnostics.depthAnalysis?.firstResidualMagnitudeMeters["over0.50"] ?? 0,0)
        let coherent=SurfaceColorBaker.bakeWithDiagnostics([transformed],frames:corrected)
        XCTAssertEqual(coherent.diagnostics.coloredTriangles,1)
        XCTAssertEqual(coherent.meshes[0].surfaceColors,SurfaceColorBaker.bake([original],frames:[base,second])[0].surfaceColors)
        var report=SurfaceColorAlignmentDiagnostics()
        report.recordCameraPose(original:base.cameraTransform,final:pose)
        XCTAssertEqual(report.cameraTranslationMeters["over0.50"],1)
        XCTAssertEqual(report.maximumCameraTranslationMeters,0.8,accuracy:1e-6)
        XCTAssertEqual(report.maximumCameraRotationDegrees,0,accuracy:1e-6)
        // Existing reports do not need alignment data to decode.
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(coherent.diagnostics)) as? [String:Any])
        json["version"]=4;json.removeValue(forKey:"alignment")
        XCTAssertNil(try JSONDecoder().decode(SurfaceColorDiagnostics.self,from:JSONSerialization.data(withJSONObject:json)).alignment)
    }
    func testDepthDiagnosticCostAndReportSizeStayBoundedAcrossRepeatedConflicts() throws {
        let base=mesh()
        let vertices=(0..<300).flatMap {_ in base.vertices}
        let source=MeshSnapshot(id:UUID(),transform:identity,vertices:vertices,indices:(0..<vertices.count).map {UInt32($0)})
        let frames=(0..<48).map {frame(time:Double($0),depth:$0%2==0 ? 1.92 : 2)}
        let start=ProcessInfo.processInfo.systemUptime
        let off=SurfaceColorBaker.bakeWithDiagnostics([source],frames:frames,collectDepthDiagnostics:false)
        let middle=ProcessInfo.processInfo.systemUptime
        let on=SurfaceColorBaker.bakeWithDiagnostics([source],frames:frames)
        let end=ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(on.meshes,off.meshes)
        XCTAssertEqual(on.diagnostics.depthAnalysis?.rejectedObservations,21600)
        let data=try JSONEncoder().encode(on.diagnostics)
        XCTAssertLessThan(data.count,16000) // Aggregates only; no per-attempt data accumulates in the report.
        print("SURFACE_DEPTH_DIAGNOSTICS_BENCHMARK: attempts=43200 offMs=\((middle-start)*1000) onMs=\((end-middle)*1000) reportBytes=\(data.count)")
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
        let result=SurfaceColorBaker.bakeWithDiagnostics([source],frames:[frame(),frame(time:2),frame(time:3,depth:1.92)])
        XCTAssertEqual(result.diagnostics.depthAnalysis?.rejectedObservations,3)
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
