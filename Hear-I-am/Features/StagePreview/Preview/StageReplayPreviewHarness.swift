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
                if args.contains("--replay-immersive") {
                    ImmersiveSavedStagePreview(record:record,store:store)
                } else {
                    SavedStagePreview(record:record,store:store,camera:args.contains("--replay-top") ? .overhead : .overview,
                                      display:args.contains("--replay-clean") ? .clean : .scan,
                                      selection:args.contains("--replay-object") ? .object(chairID) : args.contains("--replay-photo") ? record.photos.first.map {.photo($0.id)} : .point(args.contains("--replay-middle") ? 1 : 0))
                }
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
            let platform=try StageObstacle(name:"의자 영역",kind:.platform,vertices:[.init(2,2.8),.init(5,2.8),.init(5,3.8),.init(2,3.8)],height:0.4)
            let stand=try StageObstacle(name:"보면대",kind:.other,vertices:[.init(5,1),.init(5.5,1),.init(5.5,1.5),.init(5,1.5)],
                                        height:1.2,appearance:.init(model:.musicStand,headingDegrees:180))
            let bounds=ReplayModelFactory.object(platform).boundingBox
            guard abs(bounds.min.y)<0.001,abs(bounds.max.y-0.4)<0.001 else {
                throw LabError.invalid("의자 영역 높이·바닥 기준 검증 실패")
            }
            var route=try StageRoute(area:area,points:[.init(1,0.3),.init(2.5,1.2),.init(3,2.4),.init(3.6,3.3)],obstacles:[chair,table,platform,stand],pointHeights:[0,0,0,0.6])
            if ProcessInfo.processInfo.arguments.contains("--replay-facing") {try route.setFacing(.north,at:1)}
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
            let source=try await worker.capture(PhotoFrame(pixels:buffer,transform:pose,timestamp:1,date:Date(),orientation:.up,objectID:nil,routeIndex:0,projection:.init(focalX:0.8,focalY:1.42,centerX:0.46,centerY:0.53,clockwiseQuarterTurns:0)))
            let rotated=try await worker.capture(PhotoFrame(pixels:buffer,transform:pose,timestamp:2,date:Date(),orientation:.right,objectID:nil,routeIndex:nil,projection:.init(focalX:0.8,focalY:1.42,centerX:0.46,centerY:0.53,clockwiseQuarterTurns:1)))
            guard source.photo.pixelWidth==640,source.photo.pixelHeight==360,
                  rotated.photo.pixelWidth==360,rotated.photo.pixelHeight==640,
                  let thumb=UIImage(contentsOfFile:source.thumbnailURL.path),max(thumb.size.width,thumb.size.height)==320 else {
                throw LabError.invalid("사진 회전·썸네일 검증 실패")
            }
            try verifyPhotoProjection(source.photo)
            try verifyPhotoProjection(rotated.photo)
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
                try await verifyLegacyAndZeroHeights(loaded)
                try verifyPhotoComparison(loaded,cleanSurfaces:model.cleanSurfaces)
                try await verifyImmersiveFocusLighting(loaded,cleanSurfaces:model.cleanSurfaces)
                try verifyArrivalFacing(loaded)
                try await verifyImmersiveIsolation(loaded,cleanSurfaces:model.cleanSurfaces)
                print("REPLAY_QA_OK: oak asset, clean surroundings, raw restoration, camera round trips, photo capture, saved route heights, orbit limits, camera reset, clean markers, bundled models, calibrated photos, frustum and first-person comparison")
            }
        } catch {record=nil;self.error=error.localizedDescription;print("REPLAY_QA_FAILED: \(error.localizedDescription)")}
    }
    /// One figure transform moves the spotlight at the same pace, without steering the camera or changing saved data.
    private func verifyImmersiveFocusLighting(_ scan: LoadedScan,cleanSurfaces: [ReplaySurfaceMesh]) async throws {
        guard let route=scan.manifest.route,let photo=scan.manifest.photos.first,let object=route.obstacles.first else {
            throw LabError.invalid("조명 검증 자료 누락")
        }
        let persistedBefore=try await store.load(scan.manifest.id)
        let scene=ReplaySceneController(scan:scan,cleanSurfaces:cleanSurfaces,immersive:true)
        let view=SCNView(frame:CGRect(x:0,y:0,width:402,height:874));view.scene=scene.scene;scene.view=view
        defer {scene.stopProjectionUpdates()}
        scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(0),cameraMode:.overview,revision:0)
        guard let focus=scene.focusLighting,focus.node.parent === scene.person,
              simd_length(focus.node.simdPosition-SIMD3<Float>(0,ReplayStageLighting.elevation,0))<0.0001,
              focus.node.light?.type == .spot,focus.node.light?.castsShadow == false else {
            throw LabError.invalid("몰입형 지점 조명 구성 검증 실패")
        }
        let controls=view.defaultCameraController
        controls.rotateBy(x:24,y:5);controls.translateInCameraSpaceBy(x:0.3,y:0.2,z:0)
        let camera=scene.camera.simdTransform,cameraTarget=controls.target,revision=scene.revision
        func cameraUnchanged() -> Bool {
            scene.revision==revision && simd_length(SIMD3<Float>(controls.target)-SIMD3<Float>(cameraTarget))<0.0001 &&
                (0..<4).allSatisfy {simd_length(scene.camera.simdTransform[$0]-camera[$0])<0.0001}
        }
        for index in route.points.indices {
            scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(index),cameraMode:.overview,revision:revision)
            let point=route.points[index],height=route.pointHeights?[index] ?? 0
            let world=route.area.world(point)
            let expected=SIMD3<Float>(Float(world.x),Float(world.y+height)+ReplayStageLighting.elevation,Float(world.z))
            guard scene.focusLighting === focus,focus.node.parent === scene.person,!focus.node.isHidden,
                  (focus.node.light?.intensity ?? 0)>0,
                  simd_length(focus.node.simdWorldPosition-expected)<0.0001,
                  simd_length(simd_act(focus.node.simdWorldOrientation,SIMD3<Float>(0,0,-1))-SIMD3<Float>(0,-1,0))<0.0001,
                  focus.node.animationKeys.isEmpty,scene.person.animationKeys.isEmpty,cameraUnchanged() else {
                throw LabError.invalid("지점 조명의 저장 높이·좌표·카메라 유지 검증 실패: \(index)")
            }
        }
        for selection: ReplaySelection? in [.photo(photo.id),.object(object.id),nil,.point(-1),.point(route.points.count)] {
            scene.update(display:.clean,wireframe:false,showPhotos:true,selection:selection,cameraMode:.overview,revision:revision)
            guard focus.node.isHidden,focus.node.light?.intensity==0,
                  focus.node.animationKeys.isEmpty,scene.person.animationKeys.isEmpty,cameraUnchanged() else {
                throw LabError.invalid("사진·기물·유효하지 않은 지점 조명 해제 검증 실패")
            }
        }
        scene.update(display:.scan,wireframe:false,showPhotos:true,selection:.point(1),cameraMode:.overview,revision:revision)
        guard focus.node.isHidden,scene.person.animationKeys.isEmpty else {throw LabError.invalid("원본 스캔 조명 격리 검증 실패")}
        scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(1),cameraMode:.overview,revision:revision,photoViewpoint:photo)
        guard focus.node.isHidden,scene.person.animationKeys.isEmpty else {throw LabError.invalid("사진 촬영 시점 조명 격리 검증 실패")}
        scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(1),cameraMode:.overview,revision:revision)
        guard !focus.node.isHidden else {throw LabError.invalid("지점 재선택 조명 복원 검증 실패")}
        var spots=0
        scene.scene.rootNode.enumerateChildNodes {node,_ in if node.light?.type == .spot {spots+=1}}
        guard spots==1 else {throw LabError.invalid("지점 전환 중 조명 중복 생성 검증 실패")}

        // The figure owns the only animation, so the light cannot lag behind on rapid selections.
        scene.movePerson(to:0,animated:false)
        scene.movePerson(to:3,animated:true)
        scene.movePerson(to:2,animated:true)
        let motionValid=UIAccessibility.isReduceMotionEnabled ? scene.person.animationKeys.isEmpty : scene.person.animationKeys==["stage-person-move"]
        guard motionValid,focus.node.parent === scene.person,focus.node.animationKeys.isEmpty,
              simd_length(focus.node.simdWorldPosition-scene.person.simdWorldPosition-SIMD3<Float>(0,ReplayStageLighting.elevation,0))<0.0001 else {
            throw LabError.invalid("인물·조명의 단일 이동 애니메이션 교체 검증 실패")
        }
        scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.photo(photo.id),cameraMode:.overview,revision:revision)
        guard scene.person.animationKeys.isEmpty,focus.node.animationKeys.isEmpty,focus.node.isHidden,focus.node.light?.intensity==0 else {
            throw LabError.invalid("사진 전환 시 인물·조명 이동 해제 검증 실패")
        }
        scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(1),cameraMode:.overview,revision:revision)
        guard !focus.node.isHidden,scene.person.animationKeys.isEmpty else {throw LabError.invalid("사진 닫기 후 지점 조명 복원 검증 실패")}
        scene.movePerson(to:3,animated:true)
        scene.stopProjectionUpdates()
        guard scene.person.animationKeys.isEmpty,focus.node.animationKeys.isEmpty,focus.node.isHidden,focus.node.light?.intensity==0 else {
            throw LabError.invalid("화면 종료 시 인물·조명 이동 해제 검증 실패")
        }
        let ordinary=ReplaySceneController(scan:scan,cleanSurfaces:cleanSurfaces)
        let ordinaryView=SCNView(frame:view.frame);ordinaryView.scene=ordinary.scene;ordinary.view=ordinaryView
        ordinary.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(1),cameraMode:.overview,revision:0)
        guard ordinary.focusLighting==nil,ordinary.ambient.light?.intensity==800,ordinary.key.light?.intensity==650 else {
            throw LabError.invalid("일반 다시보기 조명 유지 검증 실패")
        }
        let manifest=scan.manifest
        let unplanned=ScanManifest(id:UUID(),name:"경로 없는 조명 검증",frame:manifest.frame,checkpoint:manifest.checkpoint,
            worldMapHash:manifest.worldMapHash,meshHash:manifest.meshHash,meshCount:manifest.meshCount,vertexCount:manifest.vertexCount,
            device:manifest.device,appVersion:manifest.appVersion)
        let noRoute=ReplaySceneController(scan:LoadedScan(manifest:unplanned,worldMap:scan.worldMap,meshes:scan.meshes),cleanSurfaces:[],immersive:true)
        guard noRoute.focusLighting==nil else {throw LabError.invalid("경로 없는 스캔 조명 격리 검증 실패")}
        let persistedAfter=try await store.load(scan.manifest.id)
        guard scene.scan.manifest.route==scan.manifest.route,scene.scan.meshes==scan.meshes,
              persistedAfter.manifest.route==persistedBefore.manifest.route,persistedAfter.manifest.photos==persistedBefore.manifest.photos,
              persistedAfter.meshes==persistedBefore.meshes,persistedAfter.worldMap==persistedBefore.worldMap else {
            throw LabError.invalid("조명 변경 후 저장 스캔 불변 검증 실패")
        }
        print("IMMERSIVE_LIGHTING_QA_OK: shared figure-light transform, saved heights, world coordinates, camera preservation, photo/raw isolation, rapid replacement and teardown, stored scan unchanged")
    }
    /// Saved stage directions are reached after translation, including wrap-around and interrupted moves.
    private func verifyArrivalFacing(_ scan: LoadedScan) throws {
        guard let originalRoute=scan.manifest.route,let photo=scan.manifest.photos.first else {throw LabError.invalid("도착 방향 검증 자료 누락")}
        func yaw(_ node: SCNNode) -> Float {
            let forward=simd_act(node.simdOrientation,SIMD3<Float>(0,0,1))
            return atan2(forward.x,forward.z)
        }
        func near(_ a: SCNVector3,_ b: SCNVector3) -> Bool {simd_length(SIMD3<Float>(a)-SIMD3<Float>(b))<0.0001}
        func anglesMatch(_ a: Float,_ b: Float) -> Bool {abs(atan2(sin(a-b),cos(a-b)))<0.0001}
        for facing in StageFacing.allCases {
            var route=originalRoute
            try route.setFacing(facing == .north ? .northWest : .north,at:0)
            try route.setFacing(facing,at:1)
            let m=scan.manifest
            let manifest=ScanManifest(id:UUID(),name:"도착 방향 검증",frame:m.frame,checkpoint:m.checkpoint,
                worldMapHash:m.worldMapHash,meshHash:m.meshHash,meshCount:m.meshCount,vertexCount:m.vertexCount,
                device:m.device,appVersion:m.appVersion,route:route,photos:m.photos)
            let scene=ReplaySceneController(scan:LoadedScan(manifest:manifest,worldMap:scan.worldMap,meshes:scan.meshes),cleanSurfaces:[],immersive:true)
            defer {scene.stopProjectionUpdates()}
            scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(0),cameraMode:.overview,revision:0)
            let origin=scene.person.position,originYaw=yaw(scene.person)
            scene.movePerson(to:1,animated:true)
            let desired=Float(facing.headingDegrees * .pi/180)
            guard anglesMatch(yaw(scene.person),desired) else {throw LabError.invalid("저장된 8방위의 인물 방향 검증 실패: \(facing.label)")}
            if UIAccessibility.isReduceMotionEnabled {
                guard scene.person.animationKeys.isEmpty else {throw LabError.invalid("동작 줄이기 도착 방향 검증 실패")}
            } else {
                guard let player=scene.person.animationPlayer(forKey:"stage-person-move"),
                      let group=CAAnimation(scnAnimation:player.animation) as? CAAnimationGroup,
                      let position=group.animations?.compactMap({$0 as? CAKeyframeAnimation}).first(where:{$0.keyPath=="position"}),
                      let rotation=group.animations?.compactMap({$0 as? CAKeyframeAnimation}).first(where:{$0.keyPath=="eulerAngles"}),
                      let positions=position.values as? [NSValue],let rotations=rotation.values as? [NSValue],
                      positions.count==3,rotations.count==3,
                      position.keyTimes?.map({$0.doubleValue})==[0,2.0/3.0,1],rotation.keyTimes==position.keyTimes,
                      abs(group.duration-0.75)<0.0001,position.duration==group.duration,rotation.duration==group.duration,
                      near(positions[0].scnVector3Value,origin),near(positions[1].scnVector3Value,scene.person.position),
                      near(positions[1].scnVector3Value,positions[2].scnVector3Value),
                      near(rotations[0].scnVector3Value,rotations[1].scnVector3Value),
                      anglesMatch(rotations[0].scnVector3Value.y,originYaw),anglesMatch(rotations[2].scnVector3Value.y,desired),
                      abs(rotations[2].scnVector3Value.y-rotations[0].scnVector3Value.y)<=Float.pi+0.0001 else {
                    throw LabError.invalid("이동 후 회전의 순서·최단각 검증 실패: \(facing.label)")
                }
            }
            scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.photo(photo.id),cameraMode:.overview,revision:0)
            guard scene.person.animationKeys.isEmpty,scene.focusLighting?.node.isHidden==true else {
                throw LabError.invalid("사진 전환 후 지연 회전 취소 검증 실패")
            }
            if facing == .east {
                scene.movePerson(to:1,animated:false);scene.person.eulerAngles.y=0
                scene.movePerson(to:1,animated:true)
                if !UIAccessibility.isReduceMotionEnabled {
                    guard let player=scene.person.animationPlayer(forKey:"stage-person-move"),
                          let group=CAAnimation(scnAnimation:player.animation) as? CAAnimationGroup,
                          abs(group.duration-0.25)<0.0001 else {throw LabError.invalid("같은 지점에서 방향만 회전 검증 실패")}
                }
                scene.stopProjectionUpdates()
                guard scene.person.animationKeys.isEmpty else {throw LabError.invalid("화면 종료 후 지연 회전 취소 검증 실패")}
            }
        }
        let legacy=ReplaySceneController(scan:scan,cleanSurfaces:[],immersive:true)
        defer {legacy.stopProjectionUpdates()}
        for index in originalRoute.points.indices where originalRoute.facing(at:index)==nil {
            legacy.movePerson(to:index,animated:false)
            let point=originalRoute.points[index]
            let previous=index>0 ? originalRoute.points[index-1] : point
            let next=originalRoute.points.indices.contains(index+1) ? originalRoute.points[index+1] : point
            let dx=index==originalRoute.points.count-1 ? point.x-previous.x : next.x-point.x
            let dz=index==originalRoute.points.count-1 ? -(point.y-previous.y) : -(next.y-point.y)
            guard anglesMatch(yaw(legacy.person),Float(atan2(dx,dz))) else {throw LabError.invalid("방향 미지정 지점의 기존 구간 방향 검증 실패")}
        }
        guard scan.manifest.route==originalRoute else {throw LabError.invalid("도착 방향 검증 후 원본 경로 불변 검증 실패")}
        print("ARRIVAL_FACING_QA_OK: eight saved directions, move then turn, shortest yaw, turn-only, cancellation, legacy heading")
    }
    /// The new scene mode must not mutate globally shared assets or the independently saved route.
    private func verifyImmersiveIsolation(_ scan: LoadedScan,cleanSurfaces: [ReplaySurfaceMesh]) async throws {
        let originalFloor=ReplaySurfaceFactory.wood.multiply.contents as? UIColor
        let scene=ReplaySceneController(scan:scan,cleanSurfaces:cleanSurfaces,immersive:true)
        let view=SCNView(frame:CGRect(x:0,y:0,width:402,height:874));view.scene=scene.scene;scene.view=view
        scene.update(display:.clean,wireframe:false,showPhotos:true,selection:.point(1),cameraMode:.overview,revision:0)
        defer {scene.stopProjectionUpdates()}
        guard scene.scan.manifest.id==scan.manifest.id, scene.scan.manifest.route==scan.manifest.route, scene.mesh.isHidden, !scene.surroundings.isHidden,
              !scene.cleanRouteNodes.isHidden, !scene.photos.isHidden,
              (ReplaySurfaceFactory.wood.multiply.contents as? UIColor)==originalFloor,
              view.backgroundColor != ReplaySurfaceFactory.background else {
            throw LabError.invalid("몰입형 다시보기 재질·저장 데이터 격리 검증 실패")
        }
        var photoCaptions=[String]()
        scene.photos.enumerateChildNodes {node,_ in
            if let text=node.geometry as? SCNText,let value=text.string as? String {photoCaptions.append(value)}
        }
        guard photoCaptions.contains("사진 1") else {throw LabError.invalid("사진 위치 라벨 보존 검증 실패")}
        scene.stopProjectionUpdates()
        let editor=SavedStagePreviewModel(record:scan.manifest,store:store)
        await editor.load();editor.select(.point(1))
        editor.pointFacing = .east;editor.holdSecondsText="3"
        await editor.savePointSettings()
        guard editor.holdSaveError==nil, let stored=try await store.load(scan.manifest.id).manifest.route,
              stored.facing(at:1) == .east,stored.holdSeconds(at:1)==3,
              stored.points==scan.manifest.route?.points,stored.obstacles==scan.manifest.route?.obstacles else {
            throw LabError.invalid("다시보기 지점 방향·대기 시간 저장 검증 실패")
        }
        if let photo=scan.manifest.photos.first {
            editor.select(.photo(photo.id))
            guard editor.activePointIndex==1 else {throw LabError.invalid("사진 선택 후 경로점 유지 검증 실패")}
        }
        print("IMMERSIVE_REPLAY_QA_OK: material isolation, saved geometry, point settings persistence, photo/point selection")
    }
    private func verifyPhotoProjection(_ photo: ScanPhoto) throws {
        let pose=ReplayPhotoCamera(photo),p=photo.projection!.upright
        let camera=SCNNode();camera.camera=SCNCamera();camera.simdTransform=pose.transform
        camera.camera?.projectionTransform=SCNMatrix4(pose.projection)
        let scene=SCNScene();scene.rootNode.addChildNode(camera)
        let view=SCNView(frame:CGRect(x:0,y:0,width:CGFloat(photo.pixelWidth)/2,height:CGFloat(photo.pixelHeight)/2))
        view.scene=scene;view.pointOfView=camera
        let expected: [(Float,Float)]=[(0,0),(1,0),(1,1),(0,1)]
        for (i,corner) in pose.corners(distance:2).enumerated() {
            let projected=view.projectPoint(camera.convertPosition(corner,to:nil))
            guard abs(projected.x/Float(view.bounds.width)-expected[i].0)<0.001,
                  abs(projected.y/Float(view.bounds.height)-expected[i].1)<0.001 else {
                throw LabError.invalid("사진 화각 모서리 재투영 검증 실패: \(i) \(projected)")
            }
        }
        let center=view.projectPoint(camera.convertPosition(SCNVector3(0,0,-2),to:nil))
        guard abs(center.x/Float(view.bounds.width)-Float(p.cx))<0.001,
              abs(center.y/Float(view.bounds.height)-Float(p.cy))<0.001,
              simd_length(SIMD3(camera.simdTransform.columns.3.x,camera.simdTransform.columns.3.y,camera.simdTransform.columns.3.z)-SIMD3(Float(photo.position.x),Float(photo.position.y),Float(photo.position.z)))<0.0001 else {
            throw LabError.invalid("사진 광학 중심·위치 재투영 검증 실패")
        }
    }
    private func verifyPhotoComparison(_ scan: LoadedScan,cleanSurfaces: [ReplaySurfaceMesh]) throws {
        guard let photo=scan.manifest.photos.first else {throw LabError.invalid("사진 검증 자료 누락")}
        let controller=ReplaySceneController(scan:scan,cleanSurfaces:cleanSurfaces)
        let view=SCNView(frame:CGRect(x:0,y:0,width:360,height:202.5));view.scene=controller.scene;controller.view=view
        controller.update(display:.clean,wireframe:false,showPhotos:true,selection:.photo(photo.id),cameraMode:.overview,revision:0)
        guard controller.cleanPerson.childNode(withName:"ReplayPerson",recursively:true)?.geometry != nil,
              controller.photos.childNodes.contains(where:{$0.childNode(withName:"projector-asset",recursively:true) != nil}),
              controller.scene.rootNode.childNode(withName:"photo-direction",recursively:false)?.childNodes.count==9 else {
            throw LabError.invalid("실제 인물·영사기·촬영 범위 표시 검증 실패")
        }
        let overview=controller.camera.simdTransform
        for display in ReplayDisplay.allCases {
            controller.update(display:display,wireframe:false,showPhotos:true,selection:.photo(photo.id),cameraMode:.overview,revision:1,photoViewpoint:photo)
            let expected=ReplayPhotoCamera(photo).transform
            guard (0..<4).allSatisfy({simd_length(controller.camera.simdTransform[$0]-expected[$0])<0.0001}),
                  !view.allowsCameraControl,controller.photos.isHidden,controller.person.isHidden,
                  controller.routeNodes.isHidden,controller.cleanRouteNodes.isHidden else {
                throw LabError.invalid("촬영 시점의 원본·정리 화면 전환 검증 실패")
            }
            view.frame.size=CGSize(width:640,height:360);controller.reframe()
            guard (0..<4).allSatisfy({simd_length(controller.camera.simdTransform[$0]-expected[$0])<0.0001}) else {
                throw LabError.invalid("사진 시점 레이아웃 변경 검증 실패")
            }
        }
        view.frame.size=CGSize(width:360,height:202.5)
        controller.update(display:.clean,wireframe:false,showPhotos:false,selection:.point(0),cameraMode:.overview,revision:2)
        guard view.allowsCameraControl,controller.photoViewpoint==nil,
              (0..<4).allSatisfy({simd_length(controller.camera.simdTransform[$0]-overview[$0])<0.0001}) else {
            throw LabError.invalid("사진 시점에서 전체 구도 복귀 검증 실패")
        }
        let parent=SavedStagePreviewModel(scan:scan,store:store,cleanSurfaces:cleanSurfaces,display:.clean)
        parent.setCamera(.overhead)
        let revision=parent.cameraRevision
        let comparison=SavedStagePreviewModel(scan:scan,store:store,cleanSurfaces:cleanSurfaces,display:parent.display)
        comparison.setCamera(.overview);comparison.display = .scan
        guard parent.cameraMode == .overhead,parent.cameraRevision==revision,parent.display == .clean else {
            throw LabError.invalid("비교 화면의 기본 카메라 상태 격리 검증 실패")
        }
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
            try verifyCameraInteraction(scene,view:view,display:display,revision:&revision)
            try verifyRouteHeights(scene,view:view)
            try verifyCleanMarkers(scene,display:display)
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
            guard scene.mesh.isHidden != raw,scene.objects.isHidden==raw,scene.surroundings.isHidden==raw,scene.scanAnnotations.isHidden != raw,
                  scene.routeNodes.isHidden != raw,scene.cleanRouteNodes.isHidden==raw,
                  scene.cleanAnnotations.isHidden==raw,scene.scanPerson.isHidden != raw,scene.cleanPerson.isHidden==raw,
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
    }
    /// Both representations must select the same saved point without altering its height or the camera.
    private func verifyCleanMarkers(_ scene: ReplaySceneController,display: ReplayDisplay) throws {
        guard let route=scene.scan.manifest.route else {throw LabError.invalid("표식 검증용 경로 누락")}
        let transform=scene.camera.simdTransform,revision=scene.revision
        for index in route.points.indices {
            let p=route.points[index],height=route.pointHeights?[index] ?? 0
            guard let marker=scene.cleanMarkers[index],
                  marker.name.flatMap({scene.names[$0]}) == .point(index),
                  abs(marker.position.x-Float(p.x))<0.0001,abs(marker.position.z+Float(p.y))<0.0001,
                  abs(marker.position.y-Float(height+0.015))<0.0001 else {
                throw LabError.invalid("정리 표식 위치·높이·선택 연결 검증 실패")
            }
            scene.update(display:display,wireframe:false,showPhotos:false,selection:.point(index),cameraMode:.overview,revision:revision)
            guard abs(scene.person.position.y-Float(height))<0.0001,
                  scene.names["clean-person"] == .point(index),
                  (0..<4).allSatisfy({simd_length(scene.camera.simdTransform[$0]-transform[$0])<0.0001}) else {
                throw LabError.invalid("새 인물 선택·카메라 유지 검증 실패")
            }
        }
        if display == .clean,let object=route.obstacles.first {
            scene.update(display:display,wireframe:false,showPhotos:false,selection:.object(object.id),cameraMode:.overview,revision:revision)
            guard scene.selectionOverlay.childNodes.count==object.vertices.count,scene.scanAnnotations.isHidden else {
                throw LabError.invalid("선택 기물 범위·원본 주석 분리 검증 실패")
            }
        }
        scene.update(display:display,wireframe:false,showPhotos:true,selection:.point(0),cameraMode:.overview,revision:revision)
        // A saved height difference must survive the dashed line and arrow, not become a flat floor projection.
        for index in 1..<route.points.count {
            guard let segment=scene.cleanRouteNodes.childNode(withName:"clean-segment-\(index)",recursively:false),
                  let arrow=scene.cleanRouteNodes.childNode(withName:"clean-chevron-\(index)",recursively:false) else {
                throw LabError.invalid("정리 동선 누락")
            }
            let a=route.points[index-1],b=route.points[index],dy=(route.pointHeights?[index] ?? 0)-(route.pointHeights?[index-1] ?? 0)
            let delta=SIMD3<Float>(Float(b.x-a.x),Float(dy),Float(-(b.y-a.y)))
            if simd_length(delta)>0.65 {
                let forward=simd_normalize(delta),up=simd_act(arrow.simdOrientation,SIMD3<Float>(0,1,0))
                let expectedUp=simd_normalize(SIMD3<Float>(0,1,0)-forward*forward.y)
                guard simd_length(simd_act(arrow.simdOrientation,SIMD3<Float>(0,0,1))-forward)<0.0001,
                      simd_length(up-expectedUp)<0.0001 else {
                    throw LabError.invalid("정리 화살표 경사 검증 실패")
                }
            }
            if abs(dy)>0.1 {
                guard segment.boundingBox.max.y-segment.boundingBox.min.y>Float(abs(dy)*0.5) else {
                    throw LabError.invalid("점선 경사 높이 검증 실패")
                }
            }
        }
        // Degenerate and short segments must not divide by zero or grow backwards through discs.
        guard ReplayModelFactory.dashedRoute(from:.init(0,0,0),to:.init(0,0,0)).childNodes.isEmpty,
              ReplayModelFactory.dashedRoute(from:.init(0,0,0),to:.init(0.1,0,0)).childNodes.isEmpty else {
            throw LabError.invalid("짧은 경로 표식 겹침 방지 검증 실패")
        }
    }
    /// Exercise SceneKit's real controls, including repeated drags beyond the limit and a translated/zoomed view.
    private func verifyCameraInteraction(_ scene: ReplaySceneController,view: SCNView,display: ReplayDisplay,revision: inout Int) throws {
        let controls=view.defaultCameraController
        let viewport=view.bounds.size,origin=CGPoint(x:view.bounds.midX,y:view.bounds.midY)
        for mode in ReplayCamera.allCases {
            for delta: CGFloat in [-2000,2000] {
                scene.frame(mode)
                for _ in 0..<8 {
                    // Gesture interaction applies SceneKit's angle limits; raw rotateBy bypasses them.
                    let end=CGPoint(x:origin.x+80,y:origin.y+delta)
                    controls.beginInteraction(origin,withViewport:viewport)
                    controls.continueInteraction(end,withViewport:viewport,sensitivity:1)
                    controls.endInteraction(end,withViewport:viewport,velocity:.zero)
                    let forward=simd_act(scene.camera.simdWorldOrientation,SIMD3<Float>(0,0,-1))
                    let elevation=asin(max(-1,min(1,-forward.y)))*180 / .pi
                    guard elevation>=14.99,elevation<=90.01 else {
                        throw LabError.invalid("카메라 하한 검증 실패: \(mode) \(elevation)")
                    }
                }
            }
        }
        scene.frame(.overview)
        let initial=scene.camera.simdTransform,initialTarget=controls.target
        // The reset button and both preset buttons share this revision-driven model action.
        let model=SavedStagePreviewModel(record:scene.scan.manifest,store:store)
        for startingMode in ReplayCamera.allCases {
            scene.frame(startingMode)
            controls.rotateBy(x:45,y:10)
            controls.translateInCameraSpaceBy(x:1,y:1,z:0)
            controls.dolly(toTarget:0.5)
            model.cameraRevision=revision
            model.setCamera(.overview)
            revision=model.cameraRevision
            scene.update(display:display,wireframe:false,showPhotos:true,selection:.point(0),
                         cameraMode:model.cameraMode,revision:revision)
            guard (0..<4).allSatisfy({simd_length(scene.camera.simdTransform[$0]-initial[$0])<0.0001}),
                  controls.target.x==initialTarget.x,controls.target.y==initialTarget.y,controls.target.z==initialTarget.z,
                  scene.camera.camera?.usesOrthographicProjection==false else {
                throw LabError.invalid("이동·확대 후 시점 초기화 검증 실패")
            }
        }
    }
    /// Check rendered geometry, not only the height helper: the measured surface may differ from a confirmed route point.
    private func verifyRouteHeights(_ scene: ReplaySceneController,view: SCNView) throws {
        guard let route=scene.scan.manifest.route, let heights=route.pointHeights else {
            throw LabError.invalid("높이 검증용 경로 정보 누락")
        }
        func near(_ actual: Float,_ expected: Double) -> Bool {abs(actual-Float(expected))<0.0001}
        for index in route.points.indices {
            let marker=scene.routeNodes.childNodes.first { node in
                node.geometry is SCNSphere && node.name.flatMap {scene.names[$0]} == .point(index)
            }
            guard let marker,near(marker.position.y,heights[index]+0.08) else {
                throw LabError.invalid("동선 지점 높이 검증 실패")
            }
            scene.movePerson(to:index)
            guard near(scene.person.position.y,heights[index]),
                  scene.pointLabels.allSatisfy({ i,label in near(label.position.y,heights[i]+(i==index ? 1.8 : 0.24)) }) else {
                throw LabError.invalid("인물·동선 라벨 높이 검증 실패")
            }
            let head=scene.stage.convertPosition(SCNVector3(route.points[index].x,heights[index]+1.8,-route.points[index].y),to:nil)
            let projected=view.projectPoint(head)
            guard projected.x>=0,projected.x<=Float(view.bounds.width),projected.y>=0,projected.y<=Float(view.bounds.height),
                  projected.z>=0,projected.z<=1 else {throw LabError.invalid("높은 동선 지점 카메라 맞춤 검증 실패")}
        }
        let lines=scene.routeNodes.childNodes.filter {$0.geometry is SCNCylinder}
        let arrows=scene.routeNodes.childNodes.filter {$0.geometry is SCNCone}
        guard lines.count==route.points.count-1,arrows.count==lines.count else {throw LabError.invalid("동선 선분 검증 자료 누락")}
        for index in lines.indices {
            let a=route.points[index],b=route.points[index+1],dy=heights[index+1]-heights[index]
            let line=lines[index],cylinder=line.geometry as! SCNCylinder
            let start=line.convertPosition(.init(0,-Float(cylinder.height)/2,0),to:scene.routeNodes)
            let end=line.convertPosition(.init(0,Float(cylinder.height)/2,0),to:scene.routeNodes)
            let expectedDirection=simd_normalize(SIMD3<Float>(Float(b.x-a.x),Float(dy),Float(-(b.y-a.y))))
            let actualDirection=simd_act(arrows[index].simdOrientation,SIMD3<Float>(0,1,0))
            guard near(start.y,heights[index]+0.06),near(end.y,heights[index+1]+0.06),
                  near(arrows[index].position.y,(heights[index]+heights[index+1])/2+0.065),
                  simd_length(expectedDirection-actualDirection)<0.0001 else {
                throw LabError.invalid("동선 선·화살표의 경사 검증 실패")
            }
        }
        scene.movePerson(to:0)
    }
    private func verifyLegacyAndZeroHeights(_ original: LoadedScan) async throws {
        guard var route=original.manifest.route else {throw LabError.invalid("호환 검증용 경로 누락")}
        let manifest=original.manifest
        for heights: [Double]? in [Array(repeating:0,count:route.points.count),nil] {
            route.pointHeights=heights
            let saved=try await store.save(id:UUID(),name:"높이 호환 검증",frame:manifest.frame,checkpoint:manifest.checkpoint,
                worldMap:original.worldMap,meshes:original.meshes,device:"Simulator fixture",appVersion:"QA",route:route,secondCheckpoint:manifest.secondCheckpoint)
            let loaded=try await store.load(saved.id)
            let scene=ReplaySceneController(scan:loaded,cleanSurfaces:[])
            scene.movePerson(to:route.points.count-1)
            // develop keeps missing heights at floor level, even inside a raised object outline.
            guard abs(scene.person.position.y)<0.0001 else {
                throw LabError.invalid("기존 저장본·명시된 바닥 높이 호환 검증 실패")
            }
            try await store.delete(saved.id)
        }
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
