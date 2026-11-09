import ARKit
import HearIAmCore

/// Delegate-queue capture: no ARFrame or camera pixel buffer survives the callback.
/// The lock also protects snapshots taken by the save operation on the main actor.
final class ScanSurfaceColorCapture: @unchecked Sendable {
    static let anchorPrefix="HearIAm.surfaceColor."
    private let lock=NSLock()
    private var observations=SurfaceColorFrames()
    private var lastAttempt = -Double.infinity
    private var lastPose: simd_float4x4?
    private var finished=false

    func finish() {
        lock.lock();defer {lock.unlock()}
        finished=true;observations=SurfaceColorFrames();lastPose=nil
    }

    func capture(_ frame: ARFrame, session: ARSession) {
        guard let configuration=session.configuration as? ARWorldTrackingConfiguration,
              configuration.sceneReconstruction != [], configuration.frameSemantics.contains(.sceneDepth),
              case .normal=frame.camera.trackingState else {return}
        lock.lock();defer {lock.unlock()}
        guard !finished,frame.timestamp-lastAttempt>=0.5 else {return}
        let previous=lastPose
        lastAttempt=frame.timestamp;lastPose=frame.camera.transform
        if let previous {
            let current=frame.camera.transform
            // Fast pans/walking frames are likely blurred; a later stable observation can fill the surface.
            guard simd_distance(previous.columns.3,current.columns.3)<0.4,
                  simd_dot(previous.columns.2,current.columns.2)>0.93 else {return}
        }
        guard let observation=Self.copy(frame),observation.valid else {return}
        let anchor=ARAnchor(name:Self.anchorPrefix+observation.id.uuidString,transform:observation.cameraTransform)
        session.add(anchor:anchor)
        if let removed=observations.append(observation),
           let old=frame.anchors.first(where:{$0.name==Self.anchorPrefix+removed.uuidString}) {
            session.remove(anchor:old)
        }
    }

    /// Use refined poses from the SAME world map being saved. Missing anchors cannot safely color a wall.
    func snapshot(map: ARWorldMap) -> [SurfaceColorFrame] {
        let poses=Dictionary(map.anchors.compactMap {anchor -> (String,simd_float4x4)? in
            guard let name=anchor.name,name.hasPrefix(Self.anchorPrefix) else {return nil}
            return (name,anchor.transform)
        },uniquingKeysWith: {_,new in new})
        lock.lock();defer {lock.unlock()}
        return observations.frames.compactMap {frame in
            poses[Self.anchorPrefix+frame.id.uuidString].map {frame.withCameraTransform($0)}
        }
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
        // At most 160 x 160 RGB/depth/confidence samples per view (~200 KB); at most 48 views.
        let scale=min(1,160.0/Double(max(dw,dh)))
        let width=Int(Double(dw)*scale),height=Int(Double(dh)*scale)
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
        let iw=CVPixelBufferGetWidthOfPlane(image,0),ih=CVPixelBufferGetHeightOfPlane(image,0)
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
            let dx=min(dw-1,Int((Double(x)+0.5)*Double(dw)/Double(width)))
            let dy=min(dh-1,Int((Double(y)+0.5)*Double(dh)/Double(height)))
            depths[index]=dBase.advanced(by:dy*dStride+dx*4).load(as:Float.self)
            confidenceValues[index]=cBase.advanced(by:dy*cStride+dx).load(as:UInt8.self)
            if let maskBase,mw>0,mh>0 {
                let mx=min(mw-1,Int((Double(x)+0.5)*Double(mw)/Double(width)))
                let my=min(mh-1,Int((Double(y)+0.5)*Double(mh)/Double(height)))
                if maskBase.advanced(by:my*maskStride+mx).load(as:UInt8.self)>0 {
                    confidenceValues[index]=0;personValues?[index]=1
                }
            }
            let ix=min(iw-1,Int((Double(x)+0.5)*Double(iw)/Double(width)))
            let iy=min(ih-1,Int((Double(y)+0.5)*Double(ih)/Double(height)))
            let ux=min(uw-1,ix*uw/iw),uy=min(uh-1,iy*uh/ih)
            let luma=yBase.advanced(by:iy*yStride+ix).load(as:UInt8.self)
            let uv=uvBase.advanced(by:uy*uvStride+ux*2)
            let color=SurfaceCameraColor.rgb(y:luma,cb:uv.load(as:UInt8.self),cr:uv.advanced(by:1).load(as:UInt8.self),fullRange:fullRange,kr:kr,kb:kb)
            for channel in 0..<3 {rgb[index*3+channel]=UInt8(clamping:Int((color[channel]*255).rounded()))}
        }}
        guard resolution.width>0,resolution.height>0 else {return nil}
        let sx=Float(width)/Float(resolution.width),sy=Float(height)/Float(resolution.height)
        return SurfaceColorFrame(time:time,cameraTransform:cameraTransform,width:width,height:height,
                                 fx:k[0][0]*sx,fy:k[1][1]*sy,cx:(k[2][0]+0.5)*sx-0.5,cy:(k[2][1]+0.5)*sy-0.5,
                                 rgb:rgb,depth:depths,confidence:confidenceValues,personMask:personValues)
    }
}
