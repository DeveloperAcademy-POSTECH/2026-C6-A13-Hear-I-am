import Foundation
import HearIAmCore

/// Step 3 · 장애물. An object is drafted as 3–8 floor vertices, then registered as one WorldObstacle.
extension PreparationViewModel {
    func beginObject(_ id: UUID? = nil) {
        objectEditing=true
        guard !busy else {return}
        editingObjectID=id
        if let object=draft.objects.first(where:{$0.id==id}) {
            obstacleName=object.name; obstacleKind=object.kind; pendingObjectWorld=object.vertices
        } else {obstacleName="장애물"; obstacleKind = .other; pendingObjectWorld=[]}
        synchronize()
    }
    func addObjectVertex() {
        guard canPlacePoint, let area=draft.area else {return}
        do {
            let p=try session.centerFloorPoint()
            guard pendingObjectWorld.count<8, abs(p.y-area.floorHeight)<=0.10, area.contains(area.floor(p)) else {throw LabError.invalid("무대 안 바닥에서 기물의 둘레를 3~8점으로 지정해주세요.")}
            pendingObjectWorld.append(p); synchronize()
        } catch {session.errorMessage=error.localizedDescription}
    }
    func undoObjectVertex() {
        guard !busy, !pendingObjectWorld.isEmpty else {return}
        pendingObjectWorld.removeLast(); synchronize()
    }
    func commitObject() {
        guard !busy, let area=draft.area else {return}
        do {
            let item=WorldObstacle(id:editingObjectID ?? UUID(),name:obstacleName.trimmingCharacters(in:.whitespacesAndNewlines),kind:obstacleKind,vertices:pendingObjectWorld)
            let projected=try item.projected(in:area)
            guard projected.vertices.allSatisfy({area.contains($0)}) else {throw LabError.invalid("기물을 무대 안에 지정해주세요.")}
            if let i=draft.objects.firstIndex(where:{$0.id==item.id}) {draft.objects[i]=item} else {draft.objects.append(item)}
            cancelObject()
        } catch {session.errorMessage=error.localizedDescription}
    }
    /// Ends editing. When editing an existing object, its registered version is kept.
    func cancelObject() {
        pendingObjectWorld=[]; editingObjectID=nil; synchronize()
        objectEditing=false
    }
    func deleteObject(_ id: UUID) {
        guard !busy else {return}
        draft.objects.removeAll {$0.id==id}; synchronize()
    }
}
