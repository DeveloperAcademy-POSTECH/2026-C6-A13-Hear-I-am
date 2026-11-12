import SwiftUI
import HearIAmCore

/// A schematic view of user-authored data, never an image of a surveyed stage.
struct ReferencePlanCanvas: View {
    let plan: PerformancePlan
    var editing = false
    var selectedObject: UUID?
    /// A point picked in the list: the others dim (Figma 971:33008).
    var selectedPoint: Int?
    /// False while a new route's last point is not yet joined to the arrival (971:32668 · 971:33297).
    var arrivalLinked = true
    var onTap: ((FloorPoint) -> Void)?
    var onDragChanged: ((FloorPoint, FloorPoint) -> Void)?
    var onDragEnded: (() -> Void)?
    @ScaledMetric(relativeTo: .caption) private var labelSize = 11

    var body: some View {
        GeometryReader { geometry in
            let bounds = canvasBounds
            let inset: CGFloat = 16
            let drawable = CGSize(width: max(1, geometry.size.width - inset * 2), height: max(1, geometry.size.height - inset * 2))
            let project: (FloorPoint) -> CGPoint = { point in
                CGPoint(x: inset + (point.x - bounds.minX) / bounds.width * drawable.width,
                        y: inset + (bounds.maxY - point.y) / bounds.height * drawable.height)
            }
            let unproject: (CGPoint) -> FloorPoint = { point in
                FloorPoint(bounds.minX + (point.x - inset) / drawable.width * bounds.width,
                           bounds.maxY - (point.y - inset) / drawable.height * bounds.height)
            }
            Canvas { context, size in
                let area = CGRect(origin: .zero, size: size)
                // Figma 971:32296: the backstage strips either side are darker than the stage, crossed by two faint lines.
                // The editor follows Figma 971:32813 (#242424 ground, the stage 8% lighter); the saved-route card on the
                // performance page keeps its own look.
                context.fill(Path(area), with: .color(editing ? Color(white: 36 / 255) : Color(white: 0.15)))
                let stageLeft = project(.init(0, 0)).x, stageRight = project(.init(PerformancePlan.width, 0)).x
                let stage = CGRect(x: stageLeft, y: 0, width: stageRight - stageLeft, height: size.height)
                context.fill(Path(stage), with: .color(editing ? Color(white: 217 / 255).opacity(0.08) : Color(white: 0.2)))
                var cross = Path()
                cross.move(to: CGPoint(x: stage.midX, y: 0)); cross.addLine(to: CGPoint(x: stage.midX, y: size.height))
                cross.move(to: CGPoint(x: stage.minX, y: size.height / 2)); cross.addLine(to: CGPoint(x: stage.maxX, y: size.height / 2))
                context.stroke(cross, with: .color(.white.opacity(0.06)), lineWidth: 1)
                // A route that is only its start and arrival has no line yet (971:32668).
                let drawn = arrivalLinked ? plan.points : Array(plan.points.dropLast())
                if drawn.count > 2 || (drawn.count == 2 && (!plan.finished || !arrivalLinked)) {
                    var path = Path(); path.addLines(drawn.map(project))
                    context.stroke(path, with: .color(Self.line), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                for object in plan.objects {
                    let vertices = object.vertices.map(project)
                    var polygon = Path(); polygon.addLines(vertices); polygon.closeSubpath()
                    let center = CGPoint(x: vertices.map(\.x).reduce(0, +) / CGFloat(vertices.count), y: vertices.map(\.y).reduce(0, +) / CGFloat(vertices.count))
                    let picked = object.id == selectedObject
                    context.fill(polygon, with: .color(Color(white: picked ? 0.2 : 0.4)))
                    context.draw(Text(object.name).font(.system(size: labelSize, weight: .medium)).foregroundColor(.white.opacity(0.85)), at: center)
                    if picked {
                        context.stroke(polygon, with: .color(.white), lineWidth: 1)
                        for p in vertices where vertices.count <= 4 {
                            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(.white))
                        }
                    }
                }
                for index in plan.points.indices {
                    let p = project(plan.points[index])
                    let end = index == 0 || (plan.finished && index == plan.points.count - 1)
                    let radius: CGFloat = editing ? 6.5 : 6
                    var dot = context
                    if let selectedPoint, selectedPoint != index { dot.opacity = 0.45 }
                    dot.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(end ? Self.end : Self.point))
                    if selectedPoint == index {
                        // 971:32662 · 971:32808: the picked point gets a white ring with a dark gap, its edit handle.
                        let ring = radius + 3.5
                        dot.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)), with: .color(.white), lineWidth: 1.5)
                    }
                    let label = editing
                        ? Text(plan.pointLabel(at: index)).font(end ? .system(size: labelSize) : HearFont.pretendard(.regular, size: labelSize + 1)).foregroundColor(.white)
                        : Text(plan.pointLabel(at: index)).font(.system(size: labelSize, weight: .medium)).foregroundColor(HearV3.text)
                    dot.draw(label, at: CGPoint(x: p.x, y: p.y + radius + 10))
                }
            }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { event in onTap?(unproject(event.location)) })
                .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { event in
                    onDragChanged?(unproject(event.startLocation), unproject(event.location))
                }.onEnded { _ in onDragEnded?() })
                .allowsHitTesting(onTap != nil)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(L("%@, 동선 %@지점, 기물과 세트 %@개", plan.name, plan.points.count, plan.objects.count))
    }
    static let point = Color(red: 0, green: 0.92, blue: 0.62)
    static let line = Color(red: 0.12, green: 0.55, blue: 0.40)
    static let end = Color(red: 0.97, green: 0.78, blue: 0.05)
    /// The stage plus a 1.4 m backstage strip either side, where the start and the arrival wait.
    private var canvasBounds: CGRect {
        let xs = plan.points.map(\.x), ys = plan.points.map(\.y)
        let minX = min(-1.4, (xs.min() ?? 0) - 0.5), maxX = max(13.4, (xs.max() ?? 12) + 0.5)
        let minY = min(0, (ys.min() ?? 0) - 0.8), maxY = max(8, (ys.max() ?? 8) + 0.5)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct ReferenceSceneCard: View {
    let plan: PerformancePlan
    var height: CGFloat = 204
    var body: some View {
        VStack(spacing: 0) {
            ReferencePlanCanvas(plan: plan)
                .overlay(alignment: .topLeading) {
                    Text(plan.name).font(.caption.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.1), in: Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                        .padding(16)
                }
        }.frame(height: height)
    }
}
