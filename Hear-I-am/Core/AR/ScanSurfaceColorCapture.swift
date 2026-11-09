import ARKit
import HearIAmCore

/// Delegate-queue capture: no ARFrame or camera pixel buffer survives the callback.
/// The lock also protects snapshots taken by the save operation on the main actor.
final class ScanSurfaceColorCapture: @unchecked Sendable {
    static let anchorPrefix="HearIAm.surfaceColor."
    private let lock=NSLock()
    private var observations=SurfaceColorFrames()
    // Only the opt-in Debug comparison keeps a second 48-frame buffer.
    private var baseline: SurfaceColorFrames? = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--surface-color-compare") ? SurfaceColorFrames(policy:.viewpointDiversity) : nil
        #else
        return nil
        #endif
    }()
    private var diagnostics=SurfaceColorCaptureDiagnostics()
    private var lastAttempt = -Double.infinity
    private var lastPose: simd_float4x4?
    private var finished=false

    func finish() {
        lock.lock();defer {lock.unlock()}
        finished=true;observations=SurfaceColorFrames();baseline=nil;lastPose=nil
    }

    func capture(_ frame: ARFrame, session: ARSession) {
        guard let configuration=session.configuration as? ARWorldTrackingConfiguration,
              configuration.sceneReconstruction != [], configuration.frameSemantics.contains(.sceneDepth) else {return}
        lock.lock();defer {lock.unlock()}
        guard !finished,frame.timestamp-lastAttempt>=0.5 else {return}
        let previous=lastPose
        lastAttempt=frame.timestamp;lastPose=frame.camera.transform
        diagnostics.attemptedFrames+=1
        guard case .normal=frame.camera.trackingState else {diagnostics.trackingRejected+=1;lastPose=nil;return}
        if let previous {
            let current=frame.camera.transform
            // Fast pans/walking frames are likely blurred; a later stable observation can fill the surface.
            guard simd_distance(previous.columns.3,current.columns.3)<0.4,
                  simd_dot(previous.columns.2,current.columns.2)>0.93 else {diagnostics.motionRejected+=1;return}
        }
        guard let observation=Self.copy(frame),observation.valid else {diagnostics.copyRejected+=1;return}
        diagnostics.capturedFrames+=1
        let previousIDs=Set(observations.frames.map(\.id)+(baseline?.frames.map(\.id) ?? []))
        let selectionStart=ProcessInfo.processInfo.systemUptime
        if observations.append(observation) != nil {diagnostics.evictedFrames+=1}
        let elapsed=(ProcessInfo.processInfo.systemUptime-selectionStart)*1000
        diagnostics.selectionMilliseconds+=elapsed
        diagnostics.maximumSelectionMilliseconds=max(diagnostics.maximumSelectionMilliseconds,elapsed)
        baseline?.append(observation)
        let retainedIDs=Set(observations.frames.map(\.id)+(baseline?.frames.map(\.id) ?? []))
        let anchor=ARAnchor(name:Self.anchorPrefix+observation.id.uuidString,transform:observation.cameraTransform)
        if retainedIDs.contains(observation.id) {session.add(anchor:anchor)}
        for removed in previousIDs.subtracting(retainedIDs) {
            if let old=frame.anchors.first(where:{$0.name==Self.anchorPrefix+removed.uuidString}) {session.remove(anchor:old)}
        }
    }

    /// The caller supplies the SAME anchor snapshot used to copy final mesh geometry.
    func snapshot(anchors: [ARAnchor]) -> (frames: [SurfaceColorFrame], baseline: [SurfaceColorFrame]?, diagnostics: SurfaceColorCaptureDiagnostics, alignment: SurfaceColorAlignmentDiagnostics) {
        let poses=Dictionary(anchors.compactMap {anchor -> (String,simd_float4x4)? in
            guard let name=anchor.name,name.hasPrefix(Self.anchorPrefix) else {return nil}
            return (name,anchor.transform)
        },uniquingKeysWith: {_,new in new})
        lock.lock();defer {lock.unlock()}
        func corrected(_ frames: [SurfaceColorFrame]) -> [SurfaceColorFrame] {
            frames.compactMap {frame in
                poses[Self.anchorPrefix+frame.id.uuidString].map {frame.withCameraTransform($0)}
            }
        }
        let frames=corrected(observations.frames)
        var report=diagnostics
        report.retainedFrames=frames.count;report.missingPoseFrames=observations.frames.count-frames.count
        let coverage=observations.coverage
        report.coveredRegions=coverage.regions;report.pairedRegions=coverage.paired
        var alignment=SurfaceColorAlignmentDiagnostics()
        for original in observations.frames {
            if let pose=poses[Self.anchorPrefix+original.id.uuidString] {alignment.recordCameraPose(original:original.cameraTransform,final:pose)}
        }
        return (frames,baseline.map {corrected($0.frames)},report,alignment)
    }

    private static func copy(_ frame: ARFrame) -> SurfaceColorFrame? {
        guard let scene=frame.sceneDepth,let confidence=scene.confidenceMap else {return nil}
        return copy(image:frame.capturedImage,depth:scene.depthMap,confidence:confidence,mask:frame.segmentationBuffer,
                    intrinsics:frame.camera.intrinsics,resolution:frame.camera.imageResolution,
                    cameraTransform:frame.camera.transform,time:frame.timestamp)
    }

    /// Kept independent of ARFrame so row strides, sensor orientation and person masks can be verified on Simulator.
    static func copy(image: CVPixelBuffer,depth: CVPixelBuffer,confidence: CVPixelBuffer,mask: CVPixelBuffer?,
                     intrinsics k: simd_float3x3,resolution: CGSize,cameraTransform: simd_float4x4,time: Double) -> SurfaceColorFrame? {
        let format=CVPixelBufferGetPixelFormatType(image)
        let fullRange=format==kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        guard fullRange || format==kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(image)==2,
              CVPixelBufferGetPixelFormatType(depth)==kCVPixelFormatType_DepthFloat32,
              CVPixelBufferGetPixelFormatType(confidence)==kCVPixelFormatType_OneComponent8 else {return nil}
        let dw=CVPixelBufferGetWidth(depth),dh=CVPixelBufferGetHeight(depth)
        guard dw>0,dh>0,CVPixelBufferGetWidth(confidence)==dw,CVPixelBufferGetHeight(confidence)==dh else {return nil}
        let iw=CVPixelBufferGetWidthOfPlane(image,0),ih=CVPixelBufferGetHeightOfPlane(image,0)
        guard resolution.width==CGFloat(iw),resolution.height==CGFloat(ih),
              let raster=SurfaceColorRasterMapping(imageWidth:iw,imageHeight:ih,depthWidth:dw,depthHeight:dh,intrinsics:k) else {return nil}
        // An integer stride preserves exact depth rays (256x192 -> 128x96), with at most 160 per edge.
        let width=raster.width,height=raster.height
        guard width>=3,height>=3 else {return nil}
        if let mask,CVPixelBufferGetPixelFormatType(mask) != kCVPixelFormatType_OneComponent8 {return nil}
        let buffers=[image,depth,confidence]+(mask.map {[$0]} ?? [])
        var locked=[CVPixelBuffer]()
        defer {for buffer in locked {CVPixelBufferUnlockBaseAddress(buffer,.readOnly)}}
        for buffer in buffers {
            guard CVPixelBufferLockBaseAddress(buffer,.readOnly)==kCVReturnSuccess else {return nil}
            locked.append(buffer)
        }
        guard let yBase=CVPixelBufferGetBaseAddressOfPlane(image,0),
              let uvBase=CVPixelBufferGetBaseAddressOfPlane(image,1),
              let dBase=CVPixelBufferGetBaseAddress(depth),let cBase=CVPixelBufferGetBaseAddress(confidence) else {return nil}
        let uw=CVPixelBufferGetWidthOfPlane(image,1),uh=CVPixelBufferGetHeightOfPlane(image,1)
        let yStride=CVPixelBufferGetBytesPerRowOfPlane(image,0),uvStride=CVPixelBufferGetBytesPerRowOfPlane(image,1)
        let dStride=CVPixelBufferGetBytesPerRow(depth),cStride=CVPixelBufferGetBytesPerRow(confidence)
        guard iw>0,ih>0,uw>0,uh>0 else {return nil}
        let matrix=CVBufferCopyAttachment(image,kCVImageBufferYCbCrMatrixKey,nil) as? String
        let kr: Float,kb: Float
        if matrix == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String) {kr=0.2126;kb=0.0722}
        else if matrix == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String) {kr=0.2627;kb=0.0593}
        else {kr=0.299;kb=0.114} // ARKit's usual ITU-R 601 camera buffer.
        let maskBase=mask.flatMap {CVPixelBufferGetBaseAddress($0)}
        let mw=mask.map {CVPixelBufferGetWidth($0)} ?? 0,mh=mask.map {CVPixelBufferGetHeight($0)} ?? 0
        let maskStride=mask.map {CVPixelBufferGetBytesPerRow($0)} ?? 0
        var rgb=[UInt8](repeating:0,count:width*height*3)
        var depths=[Float](repeating:0,count:width*height),confidenceValues=[UInt8](repeating:0,count:width*height)
        var personValues=mask == nil ? nil : [UInt8](repeating:0,count:width*height)
        for y in 0..<height {for x in 0..<width {
            let index=y*width+x
            let dx=raster.depthX(x),dy=raster.depthY(y)
            depths[index]=dBase.advanced(by:dy*dStride+dx*4).load(as:Float.self)
            confidenceValues[index]=cBase.advanced(by:dy*cStride+dx).load(as:UInt8.self)
            if let maskBase,mw>0,mh>0 {
                var person=false
                for my in raster.maskRange(y,depthSize:dh,maskSize:mh) {for mx in raster.maskRange(x,depthSize:dw,maskSize:mw) {
                    if maskBase.advanced(by:my*maskStride+mx).load(as:UInt8.self)>0 {person=true}
                }}
                if person {
                    confidenceValues[index]=0;personValues?[index]=1
                }
            }
            let ix=raster.imageX(x),iy=raster.imageY(y)
            let ux=min(uw-1,ix*uw/iw),uy=min(uh-1,iy*uh/ih)
            let luma=yBase.advanced(by:iy*yStride+ix).load(as:UInt8.self)
            let uv=uvBase.advanced(by:uy*uvStride+ux*2)
            let color=SurfaceCameraColor.rgb(y:luma,cb:uv.load(as:UInt8.self),cr:uv.advanced(by:1).load(as:UInt8.self),fullRange:fullRange,kr:kr,kb:kb)
            for channel in 0..<3 {rgb[index*3+channel]=UInt8(clamping:Int((color[channel]*255).rounded()))}
        }}
        return SurfaceColorFrame(time:time,cameraTransform:cameraTransform,width:width,height:height,
                                 fx:raster.fx,fy:raster.fy,cx:raster.cx,cy:raster.cy,
                                 rgb:rgb,depth:depths,confidence:confidenceValues,personMask:personValues)
    }
}
