import Foundation

public enum GuideState: Equatable, Sendable { case idle, guiding, paused, completed }
public enum GuidePauseReason: Equatable, Sendable { case manual, invalidSample, sampleGap, outsideStage, unclearHeading, offRoute, obstacleProximity }
public struct GuideUpdate: Equatable, Sendable {
    public let state: GuideState
    public let targetIndex: Int
    public let announcement: String?
}
/// One target advances only after dwell. All timestamps must come from distinct, fresh frames.
public struct RouteGuide: Sendable {
    public private(set) var state: GuideState = .idle
    public private(set) var targetIndex=1
    public private(set) var pauseReason: GuidePauseReason?
    public var canAutomaticallyRecover: Bool {
        state == .paused && (pauseReason == .unclearHeading ||
            (!usesRouteCorridor && (pauseReason == .outsideStage || pauseReason == .sampleGap)))
    }
    public let route: StageRoute
    public let settings: GuideSettings
    /// Opt in for the portrait guidance flow. The legacy experiment keeps its original rules.
    public let usesRouteCorridor: Bool
    public static let corridorRadius = 0.60
    private var arrivedSince: Double?
    private var lastTime: Double?
    private var lastSpeech: Double = -.infinity
    private var reentrySince: Double?
    private var lastReentryTime: Double?
    private var sector: Int?
    public init(route: StageRoute, settings: GuideSettings, usesRouteCorridor: Bool = false) {
        self.route=route; self.settings=settings; self.usesRouteCorridor=usesRouteCorridor
    }
    public func ready(position: FloorPoint, headingDegrees: Double, trackingValid: Bool) -> Bool {
        guard route.version == 1 || usesRouteCorridor, trackingValid, position.valid, headingDegrees.isFinite,
              (try? route.validate()) != nil, !usesRouteCorridor || (try? settings.validate()) != nil,
              position.distance(to:route.points[0]) <= settings.startRadius,
              !usesRouteCorridor || positionIssue(position) == nil else { return false }
        let angle=atan2(sin(headingDegrees * .pi/180),cos(headingDegrees * .pi/180))*180 / .pi
        // Portrait guidance already computes directions relative to the measured body heading.
        // Only the legacy experiment requires facing the audience before departure.
        return (usesRouteCorridor || abs(angle) <= settings.frontToleranceDegrees) &&
            route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty
    }
    @discardableResult public mutating func start(position: FloorPoint, headingDegrees: Double, trackingValid: Bool) -> Bool {
        guard state == .idle, ready(position:position,headingDegrees:headingDegrees,trackingValid:trackingValid) else { return false }
        state = .guiding; targetIndex=1; arrivedSince=nil; lastTime=nil; lastSpeech = -.infinity; sector=nil; pauseReason=nil
        return true
    }
    public mutating func pause() { pause(reason:.manual) }
    public mutating func pauseForUnclearHeading() {
        guard state == .guiding else { return }
        pause(reason:.unclearHeading)
    }
    private mutating func pause(reason: GuidePauseReason) {
        guard state == .guiding || state == .paused else { return }
        state = .paused; pauseReason=reason; arrivedSince=nil; reentrySince=nil; lastReentryTime=nil
    }
    @discardableResult public mutating func resume(position: FloorPoint, trackingValid: Bool) -> Bool {
        guard canResume(position:position,trackingValid:trackingValid) else { return false }
        state = .guiding; pauseReason=nil; arrivedSince=nil; lastTime=nil; lastSpeech = -.infinity
        reentrySince=nil; lastReentryTime=nil; sector=nil
        return true
    }
    public func canResume(position: FloorPoint, trackingValid: Bool) -> Bool {
        state == .paused && trackingValid && position.valid &&
        (usesRouteCorridor ? positionIssue(position) == nil : route.area.contains(position,margin:settings.boundaryMargin)) &&
        route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty
    }
    /// Only the active entry/exit segment may extend outside the stage. This is not obstacle detection.
    public func positionIssue(_ position: FloorPoint) -> GuidePauseReason? {
        guard position.valid, route.points.indices.contains(targetIndex), targetIndex > 0 else { return .invalidSample }
        let externalSegment=route.version == 2 && (targetIndex == 1 || targetIndex == route.points.count-1)
        if !route.area.contains(position) && !externalSegment { return .outsideStage }
        let a=route.points[targetIndex-1], b=route.points[targetIndex]
        if position.distance(toSegmentFrom:a,to:b) > Self.corridorRadius { return .offRoute }
        if route.obstacles.contains(where: { $0.passage == .prohibited && $0.overlaps(position,b,clearance:settings.obstacleClearance) }) {
            return .obstacleProximity
        }
        return nil
    }
    public func cue(position: FloorPoint, headingDegrees: Double) -> GuidanceCue? {
        guard route.points.indices.contains(targetIndex) else { return nil }
        return GuidanceCue(position:position,goal:route.points[targetIndex],headingDegrees:headingDegrees,sector:sector)
    }
    /// Portrait guidance only auto-recovers a tilt pause, within its active route corridor.
    /// The caller may hold resumption until the correction speech has finished.
    @discardableResult public mutating func observeAutomaticRecovery(time: Double, position: FloorPoint, headingDegrees: Double, trackingValid: Bool, allowsResume: Bool = true) -> Bool {
        guard canAutomaticallyRecover else { return false }
        guard time.isFinite, position.valid, headingDegrees.isFinite, trackingValid,
              canResume(position:position,trackingValid:trackingValid),
              lastReentryTime.map({time > $0 && time-$0 <= 0.5}) ?? true else {
            reentrySince=nil; lastReentryTime=nil; return false
        }
        lastReentryTime=time
        guard let since=reentrySince else { reentrySince=time; return false }
        guard time-since >= 1.0, allowsResume else { return false }
        return resume(position:position,trackingValid:true)
    }
    public mutating func observe(time: Double, position: FloorPoint, headingDegrees: Double, trackingValid: Bool, allowsTargetAdvance: Bool = true) -> GuideUpdate {
        guard state == .guiding else { return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil) }
        guard time.isFinite, position.valid, headingDegrees.isFinite, trackingValid else {
            pause(reason:.invalidSample); return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil)
        }
        guard lastTime.map({time > $0 && time-$0 <= 0.5}) ?? true else {
            pause(reason:.sampleGap); return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil)
        }
        let issue=usesRouteCorridor ? positionIssue(position) : (route.area.contains(position) ? nil : GuidePauseReason.outsideStage)
        if let issue {
            pause(reason:issue); return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil)
        }
        lastTime=time
        var goal=route.points[targetIndex], distance=position.distance(to:goal)
        var arrivedIndex: Int?
        if allowsTargetAdvance && distance <= settings.arrivalRadius {
            if arrivedSince == nil { arrivedSince=time }
            if let since=arrivedSince, time-since >= settings.arrivalDwell {
                if targetIndex == route.points.count-1 {
                    state = .completed
                    return GuideUpdate(state:state,targetIndex:targetIndex,announcement:GuidanceCopy.completed)
                }
                arrivedIndex=targetIndex
                targetIndex += 1; arrivedSince=nil; sector=nil
                goal=route.points[targetIndex]; distance=position.distance(to:goal)
            }
        } else { arrivedSince=nil }
        let dx=goal.x-position.x, dy=goal.y-position.y
        // heading 0 faces audience (-stage Y); positive rotates to the performer's right.
        let radians=headingDegrees * .pi/180
        let forward=FloorPoint(-sin(radians),-cos(radians))
        let bodyRight=FloorPoint(forward.y,-forward.x)
        let angle=atan2(dx*bodyRight.x+dy*bodyRight.y,dx*forward.x+dy*forward.y)*180 / .pi
        let normalized=(angle+360).truncatingRemainder(dividingBy:360)
        let candidate=Int(floor((normalized+22.5)/45))%8
        if let old=sector {
            let center=Double(old)*45
            let delta=abs((normalized-center+540).truncatingRemainder(dividingBy:360)-180)
            if delta > 22.5+settings.headingHysteresisDegrees { sector=candidate }
        } else { sector=candidate }
        let names=["앞","오른쪽 앞","오른쪽","오른쪽 뒤","뒤","왼쪽 뒤","왼쪽","왼쪽 앞"]
        let direction=String(format:"%@, %.1f미터.",names[sector ?? candidate],distance)
        if let arrivedIndex {
            lastSpeech=time
            return GuideUpdate(state:state,targetIndex:targetIndex,
                announcement:"\(arrivedIndex)번째 지점 도착. 다음 p\(targetIndex), \(direction)")
        }
        guard time-lastSpeech >= settings.repeatInterval else { return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil) }
        lastSpeech=time
        return GuideUpdate(state:state,targetIndex:targetIndex,announcement:direction)
    }
}
