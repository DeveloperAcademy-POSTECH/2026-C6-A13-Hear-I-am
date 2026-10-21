import ARKit
import HearIAmCore

struct ScopedObjectLayer {
    let region: ObjectScanRegion
    let meshes: [MeshSnapshot]
}

extension ARSessionController {
    func beginBasePerformance() throws {
        guard purpose == .preparation, mode == .restoring, gate.isReady(now:now),
              let context=spaceContext, context.baseScanID==manifest?.id, !meshes.isEmpty,
              let session, let configuration=session.configuration as? ARWorldTrackingConfiguration else {
            throw LabError.invalid("기본 공간의 확인점을 먼저 검증해주세요.")
        }
        baseGeometry=Array(meshes.values)
        let oldPrefix=referencePrefix
        session.currentFrame?.anchors.filter {$0.name?.hasPrefix(oldPrefix)==true || $0 is ARMeshAnchor}.forEach {session.remove(anchor:$0)}
        scanID=UUID();manifest=nil;cornerAnchors=[:];preparedDraft=PreparationDraft()
        corners=Array(repeating:nil,count:4);origin=nil;front=nil;checkpoint=nil;stage=nil;area=nil;routePoints=[];obstacles=[]
        mode = .scanning;restoreStarted=nil;gate.invalidate();ready=false;canSave=false
        configuration.initialWorldMap=nil
        if supportsMesh {configuration.sceneReconstruction = .mesh}
        // Keep the localized world coordinate system: no resetTracking and no new ARSession.
        session.run(configuration)
        renderer.meshLayer.isHidden = !showMesh;renderer.referenceLayer.isHidden=false
        status="기본 공간 위치 확인 완료 · 이번 공연의 무대 범위를 지정하세요"
    }
    func spaceContextForSaving(area: StageArea) -> ScanSpaceContext? {
        guard let context=spaceContext else {return nil}
        return ScanSpaceContext(venueID:context.venueID,roomID:context.roomID,purpose:context.purpose,
            baseScanID:context.baseScanID,baseMeshHash:context.baseMeshHash,
            roomArea:isBaseRegistration ? area : context.roomArea,
            checkpointNote:isBaseRegistration ? baseCheckpointNote : nil,
            additions:scopedLayers.keys.sorted {$0.uuidString<$1.uuidString}.map {ObjectMeshLayer(objectID:$0,meshIDs:scopedLayers[$0]!.meshes.map(\.id))})
    }
    func beginObjectScan(region: ObjectScanRegion, objectID: UUID) throws {
        guard canPlacePoint, baseGeometry != nil, supportsMesh, !photoCapturing else {
            throw LabError.invalid("정상 추적 중인 LiDAR 기기에서 추가 스캔을 시작해주세요.")
        }
        guard !scopedLayers.contains(where:{$0.key != objectID && $0.value.region.overlaps(region)}) else {
            throw LabError.invalid("다른 추가 기물의 둘레와 겹칩니다. 각각의 둘레를 구분해주세요.")
        }
        cancelObjectScan()
        activeObjectRegion=region;objectScanChunks=[:];objectScanTriangles=0;objectScanActive=true
        // Only new callbacks after the explicit scan start are accepted, never cached map meshes.
        status="지정한 기물을 여러 각도에서 비춰주세요. 바닥 위 3.5cm~2.5m 표면을 수집합니다."
    }
    func receiveObjectMeshes(_ parts: [MeshSnapshot], removed: [UUID]) {
        guard objectScanActive, activeObjectRegion != nil else {return}
        for id in removed {pendingObjectMeshes[id]=nil;pendingObjectRemovals.insert(id)}
        for part in parts {pendingObjectRemovals.remove(part.id);pendingObjectMeshes[part.id]=part}
        // Coalesce pending updates by anchor. One worker crops the latest chunks off the UI thread.
        guard objectScanTask == nil else {return}
        let generation=objectScanGeneration,operation=token
        objectScanTask=Task { [weak self] in
            guard let self else {return}
            while !Task.isCancelled, objectScanGeneration==generation, token==operation,
                  let region=activeObjectRegion, !pendingObjectMeshes.isEmpty || !pendingObjectRemovals.isEmpty {
                let parts=Array(pendingObjectMeshes.values),removed=pendingObjectRemovals
                pendingObjectMeshes=[:];pendingObjectRemovals=[]
                let selected=await Task.detached(priority:.userInitiated) {
                    parts.compactMap {region.selecting($0,inside:true)}
                }.value
                guard !Task.isCancelled, objectScanGeneration==generation, token==operation else {break}
                for id in removed.union(parts.map(\.id)) {objectScanChunks[id]=nil}
                for part in selected {objectScanChunks[part.id]=part}
                objectScanTriangles=objectScanChunks.values.reduce(0) {$0+$1.indices.count/3}
                if objectScanChunks.values.reduce(0,{$0+$1.vertices.count})>150_000 {
                    cancelObjectScan();errorMessage="추가 기물 스캔이 너무 큽니다. 둘레를 줄여 다시 스캔해주세요.";return
                }
            }
            if objectScanGeneration==generation {objectScanTask=nil}
        }
    }
    func acceptObjectScan(objectID: UUID, region: ObjectScanRegion) async throws {
        guard activeObjectRegion==region else {
            throw LabError.invalid("둘레 안 표면을 먼저 추가 스캔해주세요. 둘레가 바뀌었다면 다시 스캔해야 합니다.")
        }
        objectScanActive=false;busy=true
        let operation=token,generation=objectScanGeneration
        await objectScanTask?.value
        guard token==operation, objectScanGeneration==generation, active, !preparationInterrupted,
              !objectScanChunks.isEmpty, latest?.normal==true, now-(latest?.time ?? 0)<0.5 else {
            if token==operation {busy=false}
            throw LabError.invalid("추가 스캔 표면과 공간 추적을 다시 확인해주세요.")
        }
        let parts=objectScanChunks.values.map {MeshSnapshot(id:UUID(),transform:$0.transform,vertices:$0.vertices,indices:$0.indices)}
        var next=scopedLayers;next[objectID]=ScopedObjectLayer(region:region,meshes:parts)
        let base=baseGeometry ?? []
        let combined=await Task.detached(priority:.userInitiated) {
            ObjectScanRegion.compose(base:base,regions:next.values.map(\.region),additions:next.values.flatMap(\.meshes))
        }.value
        guard token==operation, objectScanGeneration==generation, active, !preparationInterrupted else {
            if token==operation {busy=false};throw LabError.invalid("추가 스캔이 중단됐어요. 다시 확인해주세요.")
        }
        guard combined.reduce(0,{$0+$1.vertices.count})<=800_000 else {busy=false;throw LabError.invalid("공간 메시가 너무 큽니다. 추가 스캔 범위를 줄여주세요.")}
        scopedLayers=next;meshes=Dictionary(uniqueKeysWithValues:combined.map {($0.id,$0)})
        updateCounts();renderer.rebuildMeshes(meshes.values,saved:true)
        busy=false;activeObjectRegion=nil;objectScanChunks=[:];objectScanTriangles=0
    }
    func cancelObjectScan() {
        objectScanTask?.cancel();objectScanTask=nil;pendingObjectMeshes=[:];pendingObjectRemovals=[]
        objectScanGeneration=UUID();objectScanActive=false;activeObjectRegion=nil;objectScanChunks=[:];objectScanTriangles=0
    }
    func removeObjectLayer(_ id: UUID) {
        guard scopedLayers.removeValue(forKey:id) != nil, let base=baseGeometry else {return}
        let combined=ObjectScanRegion.compose(base:base,regions:scopedLayers.values.map(\.region),additions:scopedLayers.values.flatMap(\.meshes))
        meshes=Dictionary(uniqueKeysWithValues:combined.map {($0.id,$0)})
        updateCounts();renderer.rebuildMeshes(meshes.values,saved:true)
    }
}
