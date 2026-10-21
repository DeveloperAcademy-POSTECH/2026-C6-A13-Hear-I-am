import Foundation
import HearIAmCore

extension PreparationViewModel {
    func startAdditionalScan() {
        guard let area=draft.area else {return}
        do {try session.beginObjectScan(region:ObjectScanRegion(outline:pendingObjectWorld,floorHeight:area.floorHeight),objectID:pendingObjectID)}
        catch {session.errorMessage=error.localizedDescription}
    }
    func commitBaseObject(in area: StageArea) {
        do {
            let region=try ObjectScanRegion(outline:pendingObjectWorld,floorHeight:area.floorHeight)
            var item=WorldObstacle(id:pendingObjectID,name:obstacleName.trimmingCharacters(in:.whitespacesAndNewlines),kind:obstacleKind,
                vertices:pendingObjectWorld,height:objectHeight?.height,entryEdges:entryEdges.sorted(),exitEdges:exitEdges.sorted(),appearance:.init(model:objectModel,headingDegrees:objectHeading))
            let projected=try item.projected(in:area)
            guard projected.vertices.allSatisfy({area.contains($0)}) else {throw LabError.invalid("기물 둘레를 무대 안에 지정해주세요.")}
            // Metadata-only edits retain the captured mesh. A changed footprint requires a new capture.
            let existing=session.scopedLayers[item.id]
            let needsCapture=existing?.region != region || session.activeObjectRegion != nil
            Task {
                do {
                    if needsCapture {try await session.acceptObjectScan(objectID:item.id,region:region)}
                    let parts=session.scopedLayers[item.id]?.meshes ?? []
                    item.height=ObjectHeight.measure(meshes:parts,outline:item.vertices,area:area)?.height
                    if let i=draft.objects.firstIndex(where:{$0.id==item.id}) {draft.objects[i]=item} else {draft.objects.append(item)}
                    cancelObject()
                } catch {session.errorMessage=error.localizedDescription}
            }
        } catch {session.errorMessage=error.localizedDescription}
    }
}
