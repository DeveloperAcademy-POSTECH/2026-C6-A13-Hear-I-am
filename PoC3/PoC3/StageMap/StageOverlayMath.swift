import Foundation

/// Clip axis-aligned grid lines to polygon interiors, including concave cut-outs.
enum StageOverlayMath {
    static func grid(_ polygon: [MapPoint], spacing: Double = 0.5) -> [(MapPoint, MapPoint)] {
        guard StageGeometry.validate(polygon) == nil, spacing.isFinite, spacing > 0 else { return [] }
        let minX = polygon.map(\.x).min()!, maxX = polygon.map(\.x).max()!
        let minY = polygon.map(\.y).min()!, maxY = polygon.map(\.y).max()!
        let step = max(spacing, ceil(max(maxX-minX, maxY-minY) / 80 / spacing) * spacing)
        var result: [(MapPoint, MapPoint)] = []
        for vertical in [true, false] {
            let low = vertical ? minX : minY, high = vertical ? maxX : maxY
            let first = Int(ceil(low / step)), last = Int(floor(high / step))
            guard first <= last else { continue }
            for index in first...last {
                let fixed = Double(index) * step
                var hits: [Double] = []
                for i in polygon.indices {
                    let a = polygon[i], b = polygon[(i+1) % polygon.count]
                    let av = vertical ? a.x : a.y, bv = vertical ? b.x : b.y
                    guard (av <= fixed && fixed < bv) || (bv <= fixed && fixed < av) else { continue }
                    let t = (fixed-av)/(bv-av)
                    hits.append(vertical ? a.y + t*(b.y-a.y) : a.x + t*(b.x-a.x))
                }
                hits.sort()
                var i = 0
                while i + 1 < hits.count {
                    if hits[i+1]-hits[i] > 1e-6 {
                        let a = vertical ? MapPoint(fixed,hits[i]) : MapPoint(hits[i],fixed)
                        let b = vertical ? MapPoint(fixed,hits[i+1]) : MapPoint(hits[i+1],fixed)
                        result.append((a,b))
                    }
                    i += 2
                }
            }
        }
        return result
    }
}
