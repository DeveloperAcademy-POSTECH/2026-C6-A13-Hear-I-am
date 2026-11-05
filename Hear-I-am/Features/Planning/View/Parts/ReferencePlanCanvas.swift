import SwiftUI
import HearIAmCore

/// A schematic view of user-authored data, never an image of a surveyed stage.
struct ReferencePlanCanvas: View {
    let plan: PerformancePlan
    var editing = false
    var selectedObject: UUID?
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
                context.fill(Path(roundedRect: area, cornerRadius: editing ? 18 : 24), with: .color(HearV3.raised))
                if editing {
                    // The texture and its crop are the design's static grid; all objects and routes remain data-driven.
                    var grid = context
                    grid.opacity = 0.5
                    grid.draw(Image("ReferencePlanGrid"), in: CGRect(x: -size.width * 0.3891, y: -size.height * 0.6288,
                                                                   width: size.width * 1.8243, height: size.height * 4.8))
                } else {
                    var grid = Path()
                    for x in 0...12 { grid.move(to: project(.init(Double(x), 0))); grid.addLine(to: project(.init(Double(x), 8))) }
                    for y in 0...8 { grid.move(to: project(.init(0, Double(y)))); grid.addLine(to: project(.init(12, Double(y)))) }
                    context.stroke(grid, with: .color(.white.opacity(0.045)), lineWidth: 0.7)
                }
                if plan.points.count > 1 {
                    var path = Path(); path.addLines(plan.points.map(project))
                    context.stroke(path, with: .color(HearV3.accent), style: StrokeStyle(lineWidth: editing ? 3 : 2.5, lineCap: .round, lineJoin: .round))
                }
                for object in plan.objects {
                    let vertices = object.vertices.map(project)
                    var polygon = Path(); polygon.addLines(vertices); polygon.closeSubpath()
                    let center = CGPoint(x: vertices.map(\.x).reduce(0, +) / CGFloat(vertices.count), y: vertices.map(\.y).reduce(0, +) / CGFloat(vertices.count))
                    if object.isStep && editing {
                        let size: CGFloat = 30
                        context.fill(Path(ellipseIn: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)), with: .color(Color(red: 0.49, green: 0.27, blue: 0.69)))
                    } else {
                        context.fill(polygon, with: .color(object.isStep ? HearV3.secondary.opacity(0.65) : HearV3.selected))
                    }
                    context.draw(Text(object.name).font(.system(size: labelSize, weight: .medium)).foregroundColor(object.isStep && editing ? Color(red: 0.75, green: 0.62, blue: 0.86) : HearV3.secondary), at: center)
                    if object.id == selectedObject {
                        context.stroke(polygon, with: .color(HearV3.secondary), lineWidth: 0.8)
                        for p in vertices {
                            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(HearV3.text))
                        }
                    }
                }
                for index in plan.points.indices {
                    let p = project(plan.points[index])
                    let final = plan.finished && index == plan.points.count - 1
                    let radius: CGFloat = editing ? 5.5 : 6.5
                    context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(final ? Color(red: 0.95, green: 0.79, blue: 0.48) : HearV3.accent))
                    context.draw(Text(plan.pointLabel(at: index)).font(.system(size: labelSize, weight: .medium)).foregroundColor(HearV3.text), at: CGPoint(x: p.x, y: p.y + radius + 10))
                }
            }.clipShape(RoundedRectangle(cornerRadius: editing ? 18 : 24))
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { event in onTap?(unproject(event.location)) })
                .simultaneousGesture(DragGesture(minimumDistance: 5).onChanged { event in
                    onDragChanged?(unproject(event.startLocation), unproject(event.location))
                }.onEnded { _ in onDragEnded?() })
                .allowsHitTesting(onTap != nil)
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(plan.name), 동선 \(plan.points.count)지점, 기물과 세트 \(plan.objects.count)개")
    }
    private var canvasBounds: CGRect {
        let xs = plan.points.map(\.x), ys = plan.points.map(\.y)
        let minX = min(0, (xs.min() ?? 0) - 0.5), maxX = max(12, (xs.max() ?? 12) + 0.5)
        let minY = min(0, (ys.min() ?? 0) - 0.8), maxY = max(8, (ys.max() ?? 8) + 0.5)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

struct ReferenceSceneCard: View {
    let plan: PerformancePlan
    var body: some View {
        VStack(spacing: 0) {
            ReferencePlanCanvas(plan: plan)
                .overlay(alignment: .topLeading) {
                    Text(plan.name).font(.caption.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.1), in: Capsule()).overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
                        .padding(16)
                }
            Rectangle().fill(HearV3.secondary.opacity(0.8)).frame(height: 3).padding(.horizontal, 12)
        }.frame(height: 204)
    }
}
