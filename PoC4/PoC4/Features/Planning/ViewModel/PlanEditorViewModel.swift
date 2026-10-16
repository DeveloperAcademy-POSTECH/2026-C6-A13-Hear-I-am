import SwiftUI
import PoC4Core

/// Editing one schematic 3:2 plan: route points, objects, name and saving.
@MainActor
final class PlanEditorViewModel: ObservableObject {
    @Published var plan: PerformancePlan
    @Published var tool: PlanEditorTool = .points { didSet { if tool != oldValue {selected=nil} } }
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
        if let selected {perform {try plan.moveObject(selected,to:point)}; return}
        if let object=plan.objects.last(where:{$0.contains(point)}) {selected=object.id; return}
        perform {
            switch tool {
            case .points: try plan.append(point)
            case .obstacle: try plan.addObject(at:point,platform:false)
            case .platform: try plan.addObject(at:point,platform:true)
            }
        }
    }
    func deleteSelectedObject() {
        guard let selected else {return}
        plan.objects.removeAll {$0.id==selected}; self.selected=nil
    }
    func undoPoint() { plan.undoPoint() }
    func finishRoute() { perform {try plan.finishRoute()} }
    /// Returns true when saved; failures stay in `message`.
    func save(to library: StageLibrary) async -> Bool {
        saving=true
        defer {saving=false}
        do {try await library.savePlan(plan); return true} catch {message=error.localizedDescription; return false}
    }
    private func perform(_ action:() throws -> Void) {do {try action()} catch {message=error.localizedDescription}}
}
