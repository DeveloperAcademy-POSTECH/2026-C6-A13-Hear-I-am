import Foundation

struct PlanTransform {
    let scale: Double
    let center: MapPoint
    let size: CGSize
    let rotated180: Bool
    init(points: [MapPoint], size: CGSize, rotated180: Bool = false) {
        self.rotated180 = rotated180
        let minX = min(0, points.map(\.x).min() ?? 0), maxX = max(0, points.map(\.x).max() ?? 1)
        let minY = min(0, points.map(\.y).min() ?? 0), maxY = max(0, points.map(\.y).max() ?? 1)
        center = MapPoint((minX + maxX) / 2, (minY + maxY) / 2)
        scale = max(1, min(max(1, size.width - 64) / max(1, maxX - minX), max(1, size.height - 64) / max(1, maxY - minY)))
        self.size = size
    }
    private var direction: Double { rotated180 ? -1 : 1 }
    func screen(_ p: MapPoint) -> CGPoint {
        CGPoint(x: size.width / 2 + direction * (p.x - center.x) * scale,
                y: size.height / 2 - direction * (p.y - center.y) * scale)
    }
    func stage(_ p: CGPoint) -> MapPoint {
        MapPoint(direction * (p.x - size.width / 2) / scale + center.x,
                 direction * (size.height / 2 - p.y) / scale + center.y)
    }
}
