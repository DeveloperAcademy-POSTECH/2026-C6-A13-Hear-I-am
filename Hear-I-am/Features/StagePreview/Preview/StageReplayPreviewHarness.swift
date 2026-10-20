#if DEBUG
import SwiftUI
import CoreVideo
import SceneKit
import simd
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
                SavedStagePreview(record:record,store:store,camera:args.contains("--replay-top") ? .overhead : .overview,
                                  display:args.contains("--replay-clean") ? .clean : .scan,
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
                                       meshes:[MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],vertices:[.init(-1,0.5,5),.init(10,0.5,5),.init(10,0.5,-3),.init(-1,0.5,-3),
                                                 .init(-1,3.5,-3),.init(10,3.5,-3),.init(-1,3.5,5)],
                                       indices:[0,1,2,0,2,3,3,2,5,3,5,4,0,3,4,0,4,6]),
                                               boxMesh(center:.init(4.5,0.75,-2.3),size:.init(6,0.5,0.9)),
                                               boxMesh(center:.init(4.5,1.25,-2.65),size:.init(6,0.6,0.2)),
                                               boxMesh(center:.init(-0.35,0.75,0),size:.init(0.9,0.5,5)),
                                               boxMesh(center:.init(-0.7,1.25,0),size:.init(0.2,0.6,5))],
                                       device:"Simulator fixture",appVersion:"QA",route:route,
                                       photos:[source])
            withExtendedLifetime(worker) {}
            if let record {
                let model=SavedStagePreviewModel(record:record,store:store)
                await model.load()
                model.select(.point(0))
                guard model.selectedPhoto?.id==source.photo.id else {throw LabError.invalid("지점 사진 연결 검증 실패")}
                model.setCamera(.overhead)
                let selectionRevision=model.cameraRevision
                model.select(.object(chairID))
                guard model.cameraMode == .overhead, model.cameraRevision==selectionRevision,
                      model.selectedObject?.id==chairID else {
                    throw LabError.invalid("기물 선택 검증 실패")
                }
                let revision=model.cameraRevision
                model.setCamera(.overhead)
                guard model.cameraRevision>revision else {throw LabError.invalid("카메라 전환 검증 실패")}
                guard ReplayCamera.allCases.count==2,model.display == .scan,let loaded=model.loaded else {
                    throw LabError.invalid("기본 보기·카메라 옵션 검증 실패")
                }
                try verifyCameraPresets(loaded,cleanSurfaces:model.cleanSurfaces)
            }
        } catch {record=nil;self.error=error.localizedDescription}
    }
    /// Real SceneKit regression: every preset round trip restores both orientation and position.
    private func verifyCameraPresets(_ scan: LoadedScan,cleanSurfaces: [ReplaySurfaceMesh]) throws {
        let scene=ReplaySceneController(scan:scan,cleanSurfaces:cleanSurfaces)
        let view=SCNView(frame:CGRect(x:0,y:0,width:390,height:420))
        view.scene=scene.scene;scene.view=view
        view.allowsCameraControl=true
        var revision=0
        for display in ReplayDisplay.allCases {
            scene.update(display:display,wireframe:false,showPhotos:true,selection:.point(0),cameraMode:.overview,revision:revision)
            revision+=1
            let expected=scene.camera.simdTransform
            for _ in 0..<4 {
                scene.frame(.overhead)
                guard scene.camera.camera?.usesOrthographicProjection==true else {throw LabError.invalid("위 시점 투영 검증 실패")}
                scene.frame(.overview)
                let actual=scene.camera.simdTransform
                guard (0..<4).allSatisfy({simd_length(actual[$0]-expected[$0])<0.0001}),
                      scene.camera.camera?.usesOrthographicProjection==false else {
                    throw LabError.invalid("전체→위→전체 카메라 복귀 검증 실패")
                }
                scene.camera.eulerAngles=SCNVector3(0.4,1.2,0.7)
                scene.frame(.overview)
                guard (0..<4).allSatisfy({simd_length(scene.camera.simdTransform[$0]-expected[$0])<0.0001}) else {
                    throw LabError.invalid("수동 회전 뒤 카메라 복귀 검증 실패")
                }
            }
            let raw=display == .scan
            do {
                // Both overviews must fit scanned walls/floor beyond the registered stage.
                for mesh in scan.meshes {
                    for p in mesh.vertices {
                        let point=SCNVector3(p.x,p.y,p.z)
                        let projected=view.projectPoint(point)
                        guard projected.x>=0,projected.x<=Float(view.bounds.width),
                              projected.y>=0,projected.y<=Float(view.bounds.height),
                              projected.z>=0,projected.z<=1 else {
                            throw LabError.invalid("무대 밖 스캔 영역 카메라 맞춤 검증 실패: \(display)")
                        }
                    }
                }
            }
            guard scene.mesh.isHidden != raw,scene.objects.isHidden==raw,scene.surroundings.isHidden==raw,scene.scanAnnotations.isHidden==false,
                  view.backgroundColor==(raw ? UIColor(white:0.10,alpha:1) : ReplaySurfaceFactory.background) else {
                throw LabError.invalid("스캔·정리 화면 전환 검증 실패")
            }
        }
        // Returning to raw must preserve both original vertex data and original gray material.
        scene.update(display:.scan,wireframe:true,showPhotos:false,selection:nil,cameraMode:.overview,revision:revision)
        guard scene.mesh.childNodes.allSatisfy({$0.geometry?.firstMaterial?.diffuse.contents as? UIColor == UIColor(white:0.72,alpha:1)}),
              scene.mesh.childNodes.allSatisfy({$0.geometry?.firstMaterial?.fillMode == .lines}),
              scene.surroundings.isHidden,scene.floor.isHidden,scene.objects.isHidden,
              scene.key.light?.castsShadow==false,
              scene.surroundings.childNodes.contains(where:{$0.name=="clean-oak-floor"}),
              scene.surroundings.childNodes.contains(where:{$0.name=="clean-scan-surroundings"}),
              UIImage(named:"ReplayOakFloor") != nil,
              ReplaySurfaceFactory.wood.diffuse.contents is UIImage else {
            throw LabError.invalid("원목 재질·주변 공간·원본 스캔 복원 검증 실패")
        }
        let floor=ReplaySurfaceFactory.stageFloor(scan.manifest.route!.area)
        guard floor.geometry?.sources(for:.texcoord).first?.vectorCount==4,
              abs(floor.boundingBox.max.y+0.002)<0.0001 else {
            throw LabError.invalid("원목 바닥 좌표·겹침 방지 검증 실패")
        }
        print("REPLAY_QA_OK: oak asset, clean surroundings, raw restoration, camera round trips, photo capture")
    }
    private func boxMesh(center: Point3,size: Point3) -> MeshSnapshot {
        let x=center.x,y=center.y,z=center.z,w=size.x/2,h=size.y/2,d=size.z/2
        return MeshSnapshot(id:UUID(),transform:[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1],
                            vertices:[.init(x-w,y-h,z-d),.init(x+w,y-h,z-d),.init(x+w,y+h,z-d),.init(x-w,y+h,z-d),
                                      .init(x-w,y-h,z+d),.init(x+w,y-h,z+d),.init(x+w,y+h,z+d),.init(x-w,y+h,z+d)],
                            indices:[0,2,1,0,3,2,4,5,6,4,6,7,0,4,7,0,7,3,1,2,6,1,6,5,3,7,6,3,6,2,0,1,5,0,5,4])
    }
}
#endif
