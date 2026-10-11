import SwiftUI

struct BodyPlanView: View {
    let polygon: [MapPoint]
    var start: MapPoint?
    var position: MapPoint?
    var target: MapPoint?
    var heading: MapPoint?
    var rotated180 = false
    var tap: ((MapPoint) -> Void)?
    var body: some View {
        GeometryReader { geometry in
            let transform = PlanTransform(points: polygon, size: geometry.size, rotated180: rotated180)
            Canvas { context, size in
                var path = Path()
                if let p = polygon.first {
                    path.move(to: transform.screen(p))
                    polygon.dropFirst().forEach { path.addLine(to: transform.screen($0)) }
                    path.closeSubpath()
                }
                context.fill(path, with: .color(.mint.opacity(0.13)))
                context.stroke(path, with: .color(.mint), lineWidth: 2)
                if let p = position ?? start, let target {
                    var route = Path(); route.move(to: transform.screen(p)); route.addLine(to: transform.screen(target))
                    context.stroke(route, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                }
                if let start {
                    context.draw(Text("S").font(.caption.bold()).foregroundColor(.mint), at: transform.screen(start) + CGSize(width: -14, height: 14))
                }
                if let position {
                    let point = transform.screen(position)
                    context.fill(Path(ellipseIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)), with: .color(.white))
                    context.draw(Text("P").font(.caption.bold()).foregroundColor(.white), at: point + CGSize(width: 14, height: 12))
                    if let heading {
                        let tip = transform.screen(position + heading * 0.75)
                        let side = MapPoint(-heading.y, heading.x)
                        var arrow = Path(); arrow.move(to: point); arrow.addLine(to: tip)
                        arrow.addLine(to: transform.screen(position + heading * 0.5 + side * 0.13))
                        arrow.move(to: tip); arrow.addLine(to: transform.screen(position + heading * 0.5 - side * 0.13))
                        context.stroke(arrow, with: .color(.yellow), lineWidth: 3)
                    }
                }
                if let target { context.draw(Text("◎ D").font(.headline).foregroundColor(.orange), at: transform.screen(target)) }
                context.draw(Text(rotated180 ? "↑ 무대 정면 · 객석" : "↓ 무대 정면 · 객석").font(.caption).foregroundColor(.secondary), at: CGPoint(x: size.width / 2, y: rotated180 ? 12 : size.height - 12))
            }
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { tap?(transform.stage($0.location)) })
        }
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("무대 평면도. " + (rotated180 ? "위가 객석 방향. " : "아래가 객석 방향. ") + (position == nil ? "P 위치 없음" : "P 위치 표시 중"))
    }
}

private extension CGPoint {
    static func + (point: CGPoint, size: CGSize) -> CGPoint { CGPoint(x: point.x + size.width, y: point.y + size.height) }
}
