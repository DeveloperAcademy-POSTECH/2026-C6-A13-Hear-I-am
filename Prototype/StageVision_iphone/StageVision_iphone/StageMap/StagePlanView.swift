import SwiftUI

struct PlanTransform {
    let scale: Double
    let center: MapPoint
    let size: CGSize
    init(points: [MapPoint], size: CGSize) {
        let minX = min(0, points.map(\.x).min() ?? 0), maxX = max(0, points.map(\.x).max() ?? 1)
        let minY = min(0, points.map(\.y).min() ?? 0), maxY = max(0, points.map(\.y).max() ?? 1)
        center = MapPoint((minX + maxX) / 2, (minY + maxY) / 2)
        scale = max(1, min(max(1, size.width - 64) / max(1, maxX - minX), max(1, size.height - 64) / max(1, maxY - minY)))
        self.size = size
    }
    func screen(_ p: MapPoint) -> CGPoint { CGPoint(x: size.width / 2 + (p.x - center.x) * scale, y: size.height / 2 - (p.y - center.y) * scale) }
    func stage(_ p: CGPoint) -> MapPoint { MapPoint((p.x - size.width / 2) / scale + center.x, (size.height / 2 - p.y) / scale + center.y) }
}

struct StagePlanView: View {
    let map: StageMap
    @Binding var selectedPoint: Int?
    @Binding var selectedEdge: Int
    let positionMode: Bool
    var move: (Int, MapPoint) -> Void
    var setPosition: (MapPoint) -> Void
    @State private var dragPoint: MapPoint?
    @State private var dragIndex: Int?
    @State private var dragTransform: PlanTransform?

    var body: some View {
        GeometryReader { geometry in
            let transform = dragTransform ?? PlanTransform(points: map.floorPolygon, size: geometry.size)
            let points = previewPoints
            let issue = StageGeometry.validate(points)
            Canvas { context, size in
                let floor = path(points, transform)
                context.fill(floor, with: .color(Color(red: 0.07, green: 0.24, blue: 0.26)))
                var clipped = context
                clipped.clip(to: floor)
                if dragIndex == nil && issue == nil {
                    // Fill one non-zero path so overlapping bands have a uniform color.
                    var danger = Path()
                    for zone in map.riskZones {
                        for piece in zone.polygons { danger.addPath(path(piece, transform)) }
                    }
                    clipped.fill(danger, with: .color(.orange.opacity(0.65)))
                }
                var grid = Path()
                let minP = transform.stage(CGPoint(x: 0, y: size.height))
                let maxP = transform.stage(CGPoint(x: size.width, y: 0))
                let gridStep = max(1, Int(ceil(24 / transform.scale)))
                for x in stride(from: Int(floorValue(minP.x)), through: Int(ceil(maxP.x)), by: gridStep) {
                    grid.move(to: transform.screen(MapPoint(Double(x), minP.y)))
                    grid.addLine(to: transform.screen(MapPoint(Double(x), maxP.y)))
                }
                for y in stride(from: Int(floorValue(minP.y)), through: Int(ceil(maxP.y)), by: gridStep) {
                    grid.move(to: transform.screen(MapPoint(minP.x, Double(y))))
                    grid.addLine(to: transform.screen(MapPoint(maxP.x, Double(y))))
                }
                clipped.stroke(grid, with: .color(.white.opacity(0.18)), lineWidth: 1)
                for i in points.indices {
                    var edge = Path()
                    edge.move(to: transform.screen(points[i])); edge.addLine(to: transform.screen(points[(i + 1) % points.count]))
                    let color: Color = issue?.edges.contains(i) == true ? .red : i == selectedEdge ? .yellow : .mint
                    context.stroke(edge, with: .color(color), lineWidth: i == selectedEdge ? 4 : 2)
                    let middle = transform.screen((points[i] + points[(i + 1) % points.count]) * 0.5)
                    context.draw(Text("S\(i + 1)").font(.caption2.bold()).foregroundColor(.white), at: middle)
                }
                let origin = transform.screen(MapPoint(0, 0))
                var axes = Path()
                axes.move(to: origin); axes.addLine(to: CGPoint(x: origin.x + 25, y: origin.y))
                axes.move(to: origin); axes.addLine(to: CGPoint(x: origin.x, y: origin.y - 25))
                context.stroke(axes, with: .color(.white), lineWidth: 2)
                context.draw(Text("O").font(.caption2).foregroundColor(.white), at: CGPoint(x: origin.x - 8, y: origin.y + 8))
                context.draw(Text("+X").font(.caption2).foregroundColor(.white), at: CGPoint(x: origin.x + 35, y: origin.y))
                context.draw(Text("+Y").font(.caption2).foregroundColor(.white), at: CGPoint(x: origin.x, y: origin.y - 35))
                if let p = map.startPosition {
                    let at = transform.screen(p)
                    context.fill(Path(ellipseIn: CGRect(x: at.x - 8, y: at.y - 8, width: 16, height: 16)), with: .color(.white))
                }
            }
            .overlay {
                ForEach(points.indices, id: \.self) { i in
                    Text("\(i + 1)").font(.caption2.bold())
                        .frame(width: 26, height: 26)
                        .background(selectedPoint == i ? Color.yellow : Color.mint, in: Circle())
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .position(transform.screen(points[i]))
                        .accessibilityLabel("경계점 \(i + 1)")
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !positionMode else { return }
                    if dragIndex == nil {
                        let t = PlanTransform(points: map.floorPolygon, size: geometry.size)
                        if let nearest = map.floorPolygon.indices.min(by: {
                            screenDistance(t.screen(map.floorPolygon[$0]), value.startLocation) < screenDistance(t.screen(map.floorPolygon[$1]), value.startLocation)
                        }), screenDistance(t.screen(map.floorPolygon[nearest]), value.startLocation) <= 24 {
                            dragIndex = nearest; selectedPoint = nearest; dragTransform = t
                        }
                    }
                    if dragIndex != nil, hypot(value.translation.width, value.translation.height) > 3 {
                        dragPoint = transform.stage(value.location)
                    }
                }
                .onEnded { value in
                    defer { dragIndex = nil; dragPoint = nil; dragTransform = nil }
                    if positionMode { setPosition(transform.stage(value.location)); return }
                    if let i = dragIndex {
                        if hypot(value.translation.width, value.translation.height) > 3 {
                            move(i, transform.stage(value.location))
                        }
                    } else {
                        let p = transform.stage(value.location)
                        if let edge = points.indices.min(by: {
                            StageGeometry.distance(p, to: points[$0], points[($0 + 1) % points.count]) < StageGeometry.distance(p, to: points[$1], points[($1 + 1) % points.count])
                        }) { selectedEdge = edge; selectedPoint = nil }
                    }
                })
        }
        .frame(minHeight: 280, idealHeight: 420, maxHeight: 500)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .clipped()
    }
    private var previewPoints: [MapPoint] {
        var points = map.floorPolygon
        if let dragIndex, let dragPoint, points.indices.contains(dragIndex) { points[dragIndex] = dragPoint }
        return points
    }
    private func path(_ points: [MapPoint], _ transform: PlanTransform) -> Path {
        var result = Path()
        if let first = points.first {
            result.move(to: transform.screen(first))
            for p in points.dropFirst() { result.addLine(to: transform.screen(p)) }
            result.closeSubpath()
        }
        return result
    }
    private func screenDistance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
    private func floorValue(_ x: Double) -> Double { x.rounded(.down) }
}
