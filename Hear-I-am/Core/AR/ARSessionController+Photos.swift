import ARKit
import ImageIO
import HearIAmCore

extension ARSessionController {
    var canCapturePhoto: Bool {
        purpose == .preparation && active && canPlacePoint && !photoCapturing &&
        photoSources.count<ScanPhoto.maximumCount && !archiveWriteInProgress
    }
    func capturePhoto(objectID: UUID? = nil, routeIndex: Int? = nil) {
        guard canCapturePhoto, let frame=session?.currentFrame,
              case .normal=frame.camera.trackingState, now-frame.timestamp<0.5 else {return}
        let orientation: CGImagePropertyOrientation
        switch view?.window?.windowScene?.interfaceOrientation {
        case .landscapeLeft: orientation = .down
        case .landscapeRight: orientation = .up
        case .portraitUpsideDown: orientation = .left
        default: orientation = .right
        }
        let matrix=frame.camera.transform
        let snapshot=PhotoFrame(pixels:frame.capturedImage,transform:(0..<4).flatMap {c in (0..<4).map {matrix[c][$0]}},
                                timestamp:frame.timestamp,date:Date(),orientation:orientation,objectID:objectID,routeIndex:routeIndex)
        photoCapturing=true; photoStatus="사진 저장 중…"
        let operation=token, request=UUID(), worker=photoCapture
        photoRequest=request
        // An anchor lets ARKit refine the capture pose along with the saved world map.
        let anchor=ARAnchor(name:"HearIAm.photo."+request.uuidString,transform:matrix)
        session?.add(anchor:anchor)
        Task {
            do {
                let source=try await worker.capture(snapshot)
                guard token==operation, photoRequest==request, active, !preparationInterrupted, mode == .scanning else {
                    session?.remove(anchor:anchor); await worker.remove(source)
                    if token==operation,photoRequest==request {photoCapturing=false;photoStatus="촬영이 중단됐어요. 다시 촬영해주세요."}
                    return
                }
                photoSources.append(source); photoAnchors[source.photo.id]=anchor
                if let index=source.photo.routePointIndex,
                   preparedDraft?.route.indices.contains(index) != true {
                    linkPhoto(source.photo.id,objectID:source.photo.objectID,routeIndex:nil)
                }
                photoCapturing=false; photoStatus="사진 \(photoSources.count)장 저장됨"
            } catch {
                session?.remove(anchor:anchor)
                guard token==operation,photoRequest==request else {return}
                photoCapturing=false;photoStatus="촬영 실패";errorMessage=error.localizedDescription
            }
        }
    }
    func deletePhoto(_ id: UUID) {
        guard !busy, !archiveWriteInProgress, let source=photoSources.first(where:{$0.photo.id==id}) else {return}
        photoSources.removeAll {$0.photo.id==id}
        if let anchor=photoAnchors.removeValue(forKey:id) {session?.remove(anchor:anchor)}
        let worker=photoCapture
        Task {await worker.remove(source)}
        photoStatus="사진 \(photoSources.count)장"
    }
    func linkPhoto(_ id: UUID, objectID: UUID?, routeIndex: Int?) {
        guard !busy, let index=photoSources.firstIndex(where:{$0.photo.id==id}) else {return}
        let source=photoSources[index], p=source.photo
        let photo=ScanPhoto(id:p.id,capturedAt:p.capturedAt,frameTimestamp:p.frameTimestamp,cameraTransform:p.cameraTransform,
                            pixelWidth:p.pixelWidth,pixelHeight:p.pixelHeight,imageHash:p.imageHash,thumbnailHash:p.thumbnailHash,
                            objectID:objectID,routePointIndex:routeIndex)
        photoSources[index]=ScanPhotoSource(photo:photo,imageURL:source.imageURL,thumbnailURL:source.thumbnailURL)
    }
    func photosForSaving(route: StageRoute, map: ARWorldMap) -> [ScanPhotoSource] {
        photoSources.map {source in
            let p=source.photo
            let transform=photoAnchors[p.id].flatMap {saved in map.anchors.first {$0.identifier==saved.identifier}?.transform}
            let pose=transform.map {t in (0..<4).flatMap {c in (0..<4).map {t[c][$0]}}} ?? p.cameraTransform
            let photo=ScanPhoto(id:p.id,capturedAt:p.capturedAt,frameTimestamp:p.frameTimestamp,cameraTransform:pose,
                                pixelWidth:p.pixelWidth,pixelHeight:p.pixelHeight,imageHash:p.imageHash,thumbnailHash:p.thumbnailHash,
                                objectID:p.objectID.flatMap {id in route.obstacles.contains {$0.id==id} ? id : nil},
                                routePointIndex:p.routePointIndex.flatMap {route.points.indices.contains($0) ? $0 : nil})
            return ScanPhotoSource(photo:photo,imageURL:source.imageURL,thumbnailURL:source.thumbnailURL)
        }
    }
    func clearPhotos() {
        photoRequest=UUID();photoCapturing=false;photoSources=[];photoAnchors=[:];photoStatus=""
        photoCapture=ScanPhotoCapture()
    }
}
