import Foundation
import HearIAmCore

/// Step 3 · 장애물. An object is drafted as 3–8 floor vertices, then registered as one WorldObstacle.
/// From 3 vertices on, its height is read from the scan mesh and suggests platform or obstacle;
/// the operator confirms by registering it (asked 10/17).
extension PreparationViewModel {
    func beginObject(_ id: UUID? = nil) {
        guard !session.photoCapturing else {return}
        objectEditing=true
        guard !busy else {return}
        editingObjectID=id
        entryEdges=[]; exitEdges=[]
        if let object=draft.objects.first(where:{$0.id==id}) {
            obstacleName=object.name; obstacleKind=object.kind; pendingObjectWorld=object.vertices
            entryEdges=Set(object.entryEdges ?? Array(object.vertices.indices)); exitEdges=Set(object.exitEdges ?? Array(object.vertices.indices))
            objectModel=object.appearance?.model ?? .generic; objectHeading=object.appearance?.headingDegrees ?? 0
        } else {obstacleName="장애물"; obstacleKind = .other; pendingObjectWorld=[];objectModel = .generic;objectHeading=0}
        // An existing object keeps the kind it was registered with; a new one takes the suggestion.
        kindChosen=id != nil; objectHeight=nil
        measureObject()
        synchronize()
    }
    func addObjectVertex() {
        guard canPlacePoint, let area=draft.area else {return}
        do {
            let p=try session.centerFloorPoint()
            guard pendingObjectWorld.count<8, abs(p.y-area.floorHeight)<=0.10, area.contains(area.floor(p)) else {throw LabError.invalid("무대 안 바닥에서 기물의 둘레를 3~8점으로 지정해주세요.")}
            pendingObjectWorld.append(p); entryEdges=[]; exitEdges=[]; measureObject(); synchronize()
        } catch {session.errorMessage=error.localizedDescription}
    }
    /// One line under the kind picker telling what the height suggests; nil before 3 points.
    var objectHeightNote: String? {
        guard pendingObjectWorld.count >= 3 else { return nil }
        guard let measured=objectHeight else { return "높이를 재지 못했어요. 이 물체 둘레를 더 스캔했는지 확인해주세요." }
        let cm=Int((measured.height*100).rounded())
        guard let kind=measured.suggestedKind else { return "바닥과 높이가 거의 같아요(약 \(cm)cm). 종류를 직접 골라주세요." }
        return "높이 약 \(cm)cm · \(kind.defaultName) 같아요"+(kindChosen ? "" : ". 맞는지 확인하고 등록해주세요.")
    }
    /// Reads the height inside the drafted outline and, until the operator picks a kind, applies its suggestion.
    func measureObject() {
        guard pendingObjectWorld.count >= 3, let area=draft.area else { objectHeight=nil; return }
        let measured=ObjectHeight.measure(meshes:Array(session.meshes.values),outline:pendingObjectWorld,area:area)
        objectHeight=measured
        var applied="none"
        if !kindChosen, let kind=measured?.suggestedKind, kind != obstacleKind {
            applyingSuggestion=true; obstacleKind=kind; applyingSuggestion=false
            applied=kind.rawValue
        }
        session.event("object_height",detail:"\(measured?.detail ?? "unmeasured") vertices=\(pendingObjectWorld.count) applied=\(applied) chosen=\(kindChosen)")
    }
    func undoObjectVertex() {
        guard !busy, !pendingObjectWorld.isEmpty else {return}
        pendingObjectWorld.removeLast(); entryEdges=[]; exitEdges=[]; measureObject(); synchronize()
    }
    func commitObject() {
        guard !busy, let area=draft.area else {return}
        do {
            let item=WorldObstacle(id:editingObjectID ?? UUID(),name:obstacleName.trimmingCharacters(in:.whitespacesAndNewlines),kind:obstacleKind,vertices:pendingObjectWorld,height:objectHeight?.height ?? draft.objects.first(where:{$0.id==editingObjectID})?.height, entryEdges:entryEdges.sorted(), exitEdges:exitEdges.sorted(), appearance:.init(model:objectModel,headingDegrees:objectHeading))
            let projected=try item.projected(in:area)
            guard projected.vertices.allSatisfy({area.contains($0)}) else {throw LabError.invalid("기물을 무대 안에 지정해주세요.")}
            if let i=draft.objects.firstIndex(where:{$0.id==item.id}) {draft.objects[i]=item} else {draft.objects.append(item)}
            session.event("object_saved",detail:"\(item.name) kind=\(item.kind.rawValue) passage=\(projected.passage.rawValue) vertices=\(item.vertices.count) height=\(item.height.map { String(format:"%.2f",$0) } ?? "none") suggested=\(objectHeight?.suggestedKind?.rawValue ?? "none")")
            cancelObject()
        } catch {session.errorMessage=error.localizedDescription}
    }
    /// Ends editing. When editing an existing object, its registered version is kept.
    func cancelObject() {
        pendingObjectWorld=[]; editingObjectID=nil; objectHeight=nil; synchronize()
        objectEditing=false
    }
    func deleteObject(_ id: UUID) {
        guard !busy else {return}
        for source in session.photoSources where source.photo.objectID==id {
            session.linkPhoto(source.photo.id,objectID:nil,routeIndex:source.photo.routePointIndex)
        }
        draft.objects.removeAll {$0.id==id}; synchronize()
    }
}
