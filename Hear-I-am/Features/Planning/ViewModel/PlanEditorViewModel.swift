import SwiftUI
import HearIAmCore

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
    var segmentSummary: String? {
        let segments = plan.scaledSegments()
        guard !segments.isEmpty else { return nil }
        func pointName(_ index: Int) -> String {
            if index == 0 { return "출발" }
            if plan.finished && index == plan.points.count - 1 { return "도착" }
            return "P\(index)"
        }
        return segments.map { seg in
            String(format: "%@→%@ %.2fm(%+.0f°)", pointName(seg.fromIndex), pointName(seg.toIndex), seg.distanceMeters, seg.angleDegrees)
        }.joined(separator: " · ")
    }

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
    /// Saves, then calls `onSaved`. Failures stay in `message`. The busy flag is set before returning.
    func save(to library: StageLibrary, onSaved: @escaping () -> Void) {
        saving=true
        Task {do {try await library.savePlan(plan); onSaved()} catch {message=error.localizedDescription}; saving=false}
    }
    private func perform(_ action:() throws -> Void) {do {try action()} catch {message=error.localizedDescription}}
}
