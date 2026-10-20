#if DEBUG
import SwiftUI
import CoreVideo
import CoreGraphics
import HearIAmCore

/// Opt-in, temporary fixtures for simulator inspection. Never touches the user's saved scans.
struct StageReplayPreviewHarness: View {
    @State private var record: ScanManifest?
    @State private var error: String?
    @State private var store=ScanStore(root:FileManager.default.temporaryDirectory.appendingPathComponent("replay-qa-"+UUID().uuidString))
    private let chairID=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
    var body: some View {
        NavigationStack {
            if let record {
                let args=ProcessInfo.processInfo.arguments
                SavedStagePreview(record:record,store:store,camera:args.contains("--replay-top") ? .overhead : args.contains("--replay-object") ? .close : .overview,
                                  selection:args.contains("--replay-object") ? .object(chairID) : args.contains("--replay-photo") ? record.photos.first.map {.photo($0.id)} : .point(0))
            } else if let error {Text(error)}
            else {ProgressView().task {await makeFixture()}}
        }.tint(.hearGreen)
    }
    private func makeFixture() async {
        do {
            let area=try StageArea(corners:[.init(2,0.5,3),.init(8,0.5,3),.init(8,0.5,-1),.init(2,0.5,-1)])
            let chair=try StageObstacle(id:chairID,name:"의자",kind:.other,vertices:[.init(4,1),.init(4.6,1),.init(4.6,1.6),.init(4,1.6)],
                                        height:0.85,appearance:.init(model:.chair,headingDegrees:0))
            let table=try StageObstacle(name:"테이블",kind:.other,vertices:[.init(0.5,2),.init(1.6,2),.init(1.6,2.6),.init(0.5,2.6)],
                                        height:0.75,appearance:.init(model:.table))
            let platform=try StageObstacle(name:"단상",kind:.platform,vertices:[.init(2,2.8),.init(5,2.8),.init(5,3.8),.init(2,3.8)],height:0.4)
            let stand=try StageObstacle(name:"보면대",kind:.other,vertices:[.init(5,1),.init(5.5,1),.init(5.5,1.5),.init(5,1.5)],
                                        height:1.2,appearance:.init(model:.musicStand,headingDegrees:180))
            let bounds=ReplayModelFactory.object(platform).boundingBox
            guard abs(bounds.min.y)<0.001,abs(bounds.max.y-0.4)<0.001 else {
                throw LabError.invalid("단상 높이·바닥 기준 검증 실패")
            }
            let route=try StageRoute(area:area,points:[.init(1,0.3),.init(2.5,1.2),.init(3,2.4),.init(3.6,3.3)],obstacles:[chair,table,platform,stand])
            let image=UIGraphicsImageRenderer(size:CGSize(width:640,height:360)).image {context in
                UIColor(white:0.92,alpha:1).setFill();context.fill(CGRect(x:0,y:0,width:640,height:360))
                ("현장 사진 테스트\n실제 촬영 사진이 아닙니다" as NSString).draw(at:CGPoint(x:65,y:130),
                    withAttributes:[.font:UIFont.systemFont(ofSize:26),.foregroundColor:UIColor.darkGray])
            }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault,640,360,kCVPixelFormatType_32BGRA,
                                      [kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,
                                      &buffer)==kCVReturnSuccess, let buffer else {throw LabError.invalid("검증 영상 버퍼 생성 실패")}
            CVPixelBufferLockBaseAddress(buffer,[])
            let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:640,height:360,bitsPerComponent:8,
                                  bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
            context.draw(image.cgImage!,in:CGRect(x:0,y:0,width:640,height:360))
            CVPixelBufferUnlockBaseAddress(buffer,[])
            let worker=ScanPhotoCapture()
            let pose: [Float]=[1,0,0,0,0,1,0,0,0,0,1,0,5,2,3,1]
            let source=try await worker.capture(PhotoFrame(pixels:buffer,transform:pose,timestamp:1,date:Date(),orientation:.up,objectID:nil,routeIndex:0))
            let rotated=try await worker.capture(PhotoFrame(pixels:buffer,transform:pose,timestamp:2,date:Date(),orientation:.right,objectID:nil,routeIndex:nil))
            guard source.photo.pixelWidth==640,source.photo.pixelHeight==360,
                  rotated.photo.pixelWidth==360,rotated.photo.pixelHeight==640,
                  let thumb=UIImage(contentsOfFile:source.thumbnailURL.path),max(thumb.size.width,thumb.size.height)==320 else {
                throw LabError.invalid("사진 회전·썸네일 검증 실패")
            }
            await worker.remove(rotated)
            record=try await store.save(id:UUID(),name:"다시보기 · 검증용 공간",frame:StageFrame(origin:area.world(.init(0,0)),front:area.world(.init(0,-1))),
                                       checkpoint:area.world(.init(5,2)),worldMap:Data([1]),
                                       meshes:[MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:area.corners,indices:[0,1,2,0,2,3])],
                                       device:"Simulator fixture",appVersion:"QA",route:route,
                                       photos:[source])
            withExtendedLifetime(worker) {}
            if let record {
                let model=SavedStagePreviewModel(record:record,store:store)
                await model.load()
                model.select(.point(0))
                guard model.selectedPhoto?.id==source.photo.id else {throw LabError.invalid("지점 사진 연결 검증 실패")}
                model.select(.object(chairID))
                guard model.cameraMode == .close, model.selectedObject?.id==chairID else {
                    throw LabError.invalid("기물 선택 검증 실패")
                }
                let revision=model.cameraRevision
                model.setCamera(.overhead)
                guard model.cameraRevision>revision else {throw LabError.invalid("카메라 전환 검증 실패")}
            }
        } catch {record=nil;self.error=error.localizedDescription}
    }
}
#endif
