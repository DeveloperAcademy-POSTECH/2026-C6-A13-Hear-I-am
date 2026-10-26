import Foundation

/// Display-only floor geometry. Never used as registered route points or collision objects.
public struct StagePlanReference: Equatable, Sendable {
    public struct Outline: Equatable, Sendable {
        public let name: String
        public let vertices: [FloorPoint]
    }
    public let points: [FloorPoint]
    public let objects: [Outline]
    public init(plan: PerformancePlan, area: StageArea) throws {
        try plan.validate()
        let sx=area.width / PerformancePlan.width, sy=area.depth / PerformancePlan.depth
        func scaled(_ p: FloorPoint) -> FloorPoint { FloorPoint(p.x*sx,p.y*sy) }
        points=plan.points.map(scaled)
        objects=plan.objects.map { Outline(name:$0.name,vertices:$0.vertices.map(scaled)) }
    }
}

extension PreparationDraft {
    /// Read-only projection; editing the stage changes the reference, never the captured input.
    public func reference(for plan: PerformancePlan) throws -> StagePlanReference {
        guard let area else { throw LabError.invalid("무대의 네 모서리를 먼저 지정해주세요.") }
        return try StagePlanReference(plan:plan,area:area)
    }
}
