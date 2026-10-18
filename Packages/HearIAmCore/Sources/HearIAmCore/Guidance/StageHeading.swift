import Foundation

/// Body-relative directions on the stage floor. Heading 0 faces the audience (−stage Y);
/// positive headings and bearings turn to the performer's right.
/// GuidanceCue and RouteGuide both use this, so the spoken direction and the signals agree.
public enum StageHeading {
    /// Signed angle in [-180, 180] from the body's forward direction to `target`. Positive: target on the right.
    public static func bearing(from position: FloorPoint, to target: FloorPoint, headingDegrees: Double) -> Double {
        let r=headingDegrees * .pi/180
        let forward=FloorPoint(-sin(r),-cos(r)), right=FloorPoint(-cos(r),sin(r))
        let dx=target.x-position.x, dy=target.y-position.y
        return atan2(dx*right.x+dy*right.y,dx*forward.x+dy*forward.y)*180 / .pi
    }
    /// 8-way sector of a bearing: 0 front, 2 right, 4 back, 6 left.
    public static func sector(_ bearing: Double) -> Int {
        Int(floor(((bearing+360).truncatingRemainder(dividingBy:360)+22.5)/45))%8
    }
}
