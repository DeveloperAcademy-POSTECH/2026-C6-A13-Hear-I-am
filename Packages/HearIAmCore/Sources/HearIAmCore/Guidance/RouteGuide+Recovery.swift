import Foundation

extension RouteGuide {
    /// Existing recovery rule: aim for the nearest point on the active segment, or away from the
    /// nearest blocking surface when already on that segment. This is not a detour planner.
    /// nil means no recovery direction can be defined, never an invented "aligned" bearing of zero.
    public func recoveryBearing(position: FloorPoint, headingDegrees: Double) -> Double? {
        guard position.valid, headingDegrees.isFinite, targetIndex > 0,
              route.points.indices.contains(targetIndex) else { return nil }
        let a=route.points[targetIndex-1], b=route.points[targetIndex]
        let dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
        let t=n > 0 ? max(0,min(1,((position.x-a.x)*dx+(position.y-a.y)*dy)/n)) : 0
        let toward=FloorPoint(a.x+t*dx,a.y+t*dy)
        if position.distance(to:toward) > 0.1 {
            return StageHeading.bearing(from:position,to:toward,headingDegrees:headingDegrees)
        }
        guard let blocked=route.obstacles.compactMap({$0.blockingPoint(from:position)}).min(by: {
            position.distance(to:$0) < position.distance(to:$1)
        }), position.distance(to:blocked) > 0.001 else { return nil }
        return HeadingMath.wrapDegrees(StageHeading.bearing(from:position,to:blocked,headingDegrees:headingDegrees)+180)
    }
}
