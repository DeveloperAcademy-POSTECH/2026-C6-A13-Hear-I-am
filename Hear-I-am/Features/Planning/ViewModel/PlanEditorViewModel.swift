import SwiftUI
import HearIAmCore

/// Editing one schematic 3:2 plan: route points, objects, name and saving.
@MainActor
final class PlanEditorViewModel: ObservableObject {
    @Published var plan: PerformancePlan
    @Published var tool: PlanEditorTool = .points { didSet { if tool != oldValue {selected=nil} } }
    @Published var selectedPoint: Int?
    @Published var selected: UUID?
    @Published var message: String?
    @Published var confirmingExit=false
    @Published var saving=false
    private let initial: PerformancePlan

    init(initial: PerformancePlan) { self.initial=initial; plan=initial }

    var hasChanges: Bool { plan != initial }
    var validationMessage: String? {
        do {try plan.validate(); return nil} catch {return error.localizedDescription}
    }
    var valid: Bool {validationMessage == nil}

    /// A tap moves the selected object, selects an object under the finger, or adds with the current tool.
    func tap(_ point: FloorPoint) {
        guard !saving else {return}
        if tool == .points, let index=plan.points.indices.min(by:{plan.points[$0].distance(to:point)<plan.points[$1].distance(to:point)}),plan.points[index].distance(to:point)<0.4 {
            selectedPoint=index;return
        }
        if let selected {perform {try plan.moveObject(selected,to:point)}; return}
        if let object=plan.objects.last(where:{$0.contains(point)}) {selected=object.id; return}
        perform {
            switch tool {
            case .points: try plan.append(point)
            case .obstacle: try plan.addObject(at:point,platform:false);selected=plan.objects.last?.id
            case .platform: try plan.addObject(at:point,platform:true);selected=plan.objects.last?.id
            }
        }
    }
    func deleteSelectedObject() {
        guard let selected else {return}
        plan.removeObject(selected); self.selected=nil
    }
    func undoPoint() { plan.undoPoint() }
    func finishRoute() { perform {try plan.finishRoute()} }
    /// Saves, then calls `onSaved`. Failures stay in `message`. The busy flag is set before returning.
    func save(to library: StageLibrary, performanceID: UUID? = nil, onSaved: @escaping () -> Void) {
        saving=true
        Task {
            do {
                if let performanceID {try await library.savePerformancePlan(plan,for:performanceID)}
                else {try await library.savePlan(plan)}
                onSaved()
            } catch {message=error.localizedDescription}
            saving=false
        }
    }
    func updatePoint(_ settings: PerformancePlanPointSettings, at index: Int) -> Bool {
        do {try plan.setPointSettings(settings,at:index);return true} catch {message=error.localizedDescription;return false}
    }
    func rotateChair(_ steps: Int) {
        guard let selected,plan.objects.contains(where:{$0.id==selected && $0.isStep}) else {return}
        let old=plan.objectFacings[selected] ?? .north
        let index=StageFacing.allCases.firstIndex(of:old) ?? 0
        plan.objectFacings[selected]=StageFacing.allCases[(index+steps+8)%8]
    }
    func drag(from start: FloorPoint, to end: FloorPoint) {
        guard !saving,let object=plan.objects.last(where:{$0.id==selected || $0.contains(start)}) else {return}
        selected=object.id
        let xs=object.vertices.map(\.x),ys=object.vertices.map(\.y)
        let center=FloorPoint(xs.reduce(0,+)/Double(xs.count),ys.reduce(0,+)/Double(ys.count))
        if object.vertices.contains(where:{$0.distance(to:start)<0.5}) {
            perform {try plan.resizeObject(object.id,width:max(0.3,abs(end.x-center.x)*2),depth:max(0.3,abs(end.y-center.y)*2))}
        } else if object.contains(start) {
            perform {try plan.moveObject(object.id,to:.init(center.x+end.x-start.x,center.y+end.y-start.y))}
        }
    }
    private func perform(_ action:() throws -> Void) {do {try action()} catch {message=error.localizedDescription}}
}
