import ARKit
import CoreImage
import ImageIO
import HearIAmCore

/// Retains only the requested pixel buffer, never an ARFrame or the continuous camera feed.
struct PhotoFrame: @unchecked Sendable {
    let pixels: CVPixelBuffer
    let transform: [Float]
    let timestamp: Double
    let date: Date
    let orientation: CGImagePropertyOrientation
    let objectID: UUID?
    let routeIndex: Int?
}

actor ScanPhotoCapture {
    private let directory=FileManager.default.temporaryDirectory.appendingPathComponent("HearIAm-photos-"+UUID().uuidString,isDirectory:true)
    private let context=CIContext(options:[.cacheIntermediates:false])
    deinit {try? FileManager.default.removeItem(at:directory)}
    func capture(_ frame: PhotoFrame) throws -> ScanPhotoSource {
        let image=CIImage(cvPixelBuffer:frame.pixels).oriented(frame.orientation)
        func encode(maximum: CGFloat, quality: Double) throws -> (Data,Int,Int) {
            let scale=min(1,maximum/max(image.extent.width,image.extent.height))
            let resized=image.transformed(by:CGAffineTransform(scaleX:scale,y:scale))
            guard let cg=context.createCGImage(resized,from:resized.extent) else {
                throw LabError.invalid("사진을 변환할 수 없습니다.")
            }
            // A dedicated output buffer avoids retaining full-size camera frames after encoding.
            let data=NSMutableData()
            guard let output=CGImageDestinationCreateWithData(data,"public.jpeg" as CFString,1,nil) else {
                throw LabError.invalid("사진을 변환할 수 없습니다.")
            }
            CGImageDestinationAddImage(output,cg,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
            guard CGImageDestinationFinalize(output) else {throw LabError.invalid("사진을 압축할 수 없습니다.")}
            return (data as Data,cg.width,cg.height)
        }
        let (jpeg,w,h)=try encode(maximum:1600,quality:0.82)
        let (thumbnail,_,_)=try encode(maximum:320,quality:0.72)
        guard jpeg.count<=ScanPhoto.maximumImageBytes,thumbnail.count<=ScanPhoto.maximumThumbnailBytes else {
            throw LabError.invalid("사진 용량이 너무 큽니다. 다시 촬영해주세요.")
        }
        let photo=ScanPhoto(capturedAt:frame.date,frameTimestamp:frame.timestamp,cameraTransform:frame.transform,
                            pixelWidth:w,pixelHeight:h,imageHash:ScanStore.hash(jpeg),thumbnailHash:ScanStore.hash(thumbnail),
                            objectID:frame.objectID,routePointIndex:frame.routeIndex)
        try photo.validate()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let full=directory.appendingPathComponent(photo.id.uuidString+".jpg")
        let thumb=directory.appendingPathComponent(photo.id.uuidString+"-thumb.jpg")
        do {
            try jpeg.write(to:full,options:.atomic); try thumbnail.write(to:thumb,options:.atomic)
        } catch {try? FileManager.default.removeItem(at:full);try? FileManager.default.removeItem(at:thumb);throw error}
        return ScanPhotoSource(photo:photo,imageURL:full,thumbnailURL:thumb)
    }
    func remove(_ source: ScanPhotoSource) {
        try? FileManager.default.removeItem(at:source.imageURL)
        try? FileManager.default.removeItem(at:source.thumbnailURL)
    }
}
