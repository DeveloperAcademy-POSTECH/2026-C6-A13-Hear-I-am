import Foundation

/// Stage coordinates, in meters. Encoded as [X, Y] to match the interchange schema.
struct MapPoint: Codable, Equatable {
    var x: Double
    var y: Double
    init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    init(from decoder: Decoder) throws {
        var values = try decoder.unkeyedContainer()
        x = try values.decode(Double.self)
        y = try values.decode(Double.self)
        guard values.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: values, debugDescription: "Expected [X, Y]")
        }
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.unkeyedContainer()
        try values.encode(x)
        try values.encode(y)
    }
    static func + (a: Self, b: Self) -> Self { Self(a.x + b.x, a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { Self(a.x - b.x, a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { Self(a.x * b, a.y * b) }
    var length: Double { hypot(x, y) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y }
    func cross(_ b: Self) -> Double { x * b.y - y * b.x }
}

struct PolygonIssue: Equatable {
    var message: String
    var edges: Set<Int> = []
}

enum StageGeometry {
    static let minimumSpacing = 0.05
    static let maximumPoints = 128
    static func signedArea(_ p: [MapPoint]) -> Double {
        guard p.count >= 3 else { return 0 }
        return p.indices.reduce(0) { $0 + p[$1].cross(p[($1 + 1) % p.count]) } / 2
    }
    static func distance(_ p: MapPoint, to a: MapPoint, _ b: MapPoint) -> Double {
        let d = b - a
        let t = max(0, min(1, (p - a).dot(d) / max(d.dot(d), 1e-15)))
        return (p - (a + d * t)).length
    }
    static func intersects(_ a: MapPoint, _ b: MapPoint, _ c: MapPoint, _ d: MapPoint) -> Bool {
        let abC = (b - a).cross(c - a), abD = (b - a).cross(d - a)
        let cdA = (d - c).cross(a - c), cdB = (d - c).cross(b - c)
        if abC * abD < -1e-12 && cdA * cdB < -1e-12 { return true }
        return distance(c, to: a, b) < 1e-7 || distance(d, to: a, b) < 1e-7
            || distance(a, to: c, d) < 1e-7 || distance(b, to: c, d) < 1e-7
    }
    static func validate(_ p: [MapPoint]) -> PolygonIssue? {
        guard p.count >= 3 else { return PolygonIssue(message: "서로 다른 점이 최소 3개 필요합니다.") }
        guard p.count <= maximumPoints else { return PolygonIssue(message: "경계점은 최대 128개입니다.") }
        guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 200 && abs($0.y) <= 200 }) else {
            return PolygonIssue(message: "좌표가 유효하지 않거나 원점에서 200m 범위를 벗어났습니다.")
        }
        for i in p.indices {
            for j in p.indices where j > i {
                if (p[i] - p[j]).length < minimumSpacing {
                    return PolygonIssue(message: "점 \(i + 1)과 \(j + 1)이 5cm 미만으로 겹칩니다.", edges: [i, j])
                }
            }
            let previous = p[(i + p.count - 1) % p.count] - p[i]
            let next = p[(i + 1) % p.count] - p[i]
            if abs(previous.cross(next)) < 1e-8 && previous.dot(next) > 0 {
                return PolygonIssue(message: "점 \(i + 1)에서 선분이 되돌아 겹칩니다.", edges: [(i + p.count - 1) % p.count, i])
            }
        }
        var crossed = Set<Int>()
        for i in p.indices {
            for j in p.indices where j > i && j != (i + 1) % p.count && i != (j + 1) % p.count {
                if intersects(p[i], p[(i + 1) % p.count], p[j], p[(j + 1) % p.count]) {
                    crossed.formUnion([i, j])
                }
            }
        }
        if !crossed.isEmpty { return PolygonIssue(message: "빨간 선분이 교차하거나 서로 닿습니다. 점을 이동하거나 삭제하세요.", edges: crossed) }
        if abs(signedArea(p)) < 0.01 { return PolygonIssue(message: "면적이 너무 작거나 점이 일직선입니다.") }
        return nil
    }
    static func contains(_ point: MapPoint, polygon: [MapPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if distance(point, to: a, b) < 1e-7 { return true }
            if (a.y > point.y) != (b.y > point.y),
               point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
        }
        return inside
    }

    /// Ear clipping supports either winding and concavities; collinear vertices are omitted only here.
    static func triangles(_ points: [MapPoint]) -> [[MapPoint]] {
        guard validate(points) == nil else { return [] }
        var p = signedArea(points) > 0 ? points : Array(points.reversed())
        var result: [[MapPoint]] = []
        while p.count > 3 {
            var removed = false
            for i in p.indices {
                let prev = (i + p.count - 1) % p.count, next = (i + 1) % p.count
                let a = p[prev], b = p[i], c = p[next]
                let cross = (b - a).cross(c - b)
                if abs(cross) < 1e-10 { p.remove(at: i); removed = true; break }
                guard cross > 0 else { continue }
                let hasPoint = p.indices.contains { j in
                    j != prev && j != i && j != next && contains(p[j], polygon: [a, b, c])
                }
                if !hasPoint {
                    result.append([a, b, c]); p.remove(at: i); removed = true; break
                }
            }
            guard removed else { return [] } // Never emit a partial unsafe geometry.
        }
        if p.count == 3 { result.append(p) }
        return result
    }

    /// Intersection of a subject polygon with a convex, CCW clipping polygon.
    static func clip(_ subject: [MapPoint], to clip: [MapPoint]) -> [MapPoint] {
        var output = subject
        for i in clip.indices {
            let a = clip[i], edge = clip[(i + 1) % clip.count] - a
            let input = output
            output = []
            guard var previous = input.last else { break }
            var previousSide = edge.cross(previous - a)
            for current in input {
                let side = edge.cross(current - a)
                if (side >= 0) != (previousSide >= 0) {
                    let t = previousSide / (previousSide - side)
                    output.append(previous + (current - previous) * t)
                }
                if side >= 0 { output.append(current) }
                previous = current; previousSide = side
            }
        }
        return output
    }

    /// Round-ended distance band, clipped into the actual floor. Pieces may overlap across segments.
    static func riskPieces(polygon: [MapPoint], edge: Int, width: Double, triangles: [[MapPoint]]) -> [[MapPoint]] {
        guard polygon.indices.contains(edge), width > 0 else { return [] }
        let a = polygon[edge], b = polygon[(edge + 1) % polygon.count]
        let theta = atan2(b.y - a.y, b.x - a.x)
        var capsule: [MapPoint] = []
        for step in 0...24 {
            let angle = theta - .pi / 2 + Double(step) * .pi / 24
            capsule.append(b + MapPoint(cos(angle), sin(angle)) * width)
        }
        for step in 0...24 {
            let angle = theta + .pi / 2 + Double(step) * .pi / 24
            capsule.append(a + MapPoint(cos(angle), sin(angle)) * width)
        }
        return triangles.map { clip($0, to: capsule) }.filter { abs(signedArea($0)) > 1e-9 }
    }
}
