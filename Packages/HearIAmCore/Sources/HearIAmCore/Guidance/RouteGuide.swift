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
    public var canAutomaticallyRecover: Bool { state == .paused && (pauseReason == .outsideStage || pauseReason == .sampleGap || pauseReason == .unclearHeading) }
    public let route: StageRoute
    public let settings: GuideSettings
    /// Opt in for the portrait guidance flow. The legacy experiment keeps its original rules.
    public let usesRouteCorridor: Bool
    /// Whether stepping off the corridor, outside the stage or near an obstacle pauses guidance (#74).
    public let pausesForPositionIssues: Bool
    /// How far from the active segment counts as off the route. It was 0.6 m until 10/19; in two runs
    /// that day all five off-route stops came from overshooting a point and stopped 0.60–0.87 m from the
    /// line. Stepping off the stage and coming near an object still stop at once.
    public static let corridorRadius = 1.0
    private var arrivedSince: Double?
    private var lastTime: Double?
    private var lastSpeech: Double = -.infinity
    private var reentrySince: Double?
    private var lastReentryTime: Double?
    private var sector: Int?
    public init(route: StageRoute, settings: GuideSettings, usesRouteCorridor: Bool = false, pausesForPositionIssues: Bool = true) {
        self.route=route; self.settings=settings; self.usesRouteCorridor=usesRouteCorridor; self.pausesForPositionIssues=pausesForPositionIssues
    }
    public func ready(position: FloorPoint, headingDegrees: Double, trackingValid: Bool) -> Bool {
        guard route.version == 1 || usesRouteCorridor, trackingValid, position.valid, headingDegrees.isFinite,
              (try? route.validate()) != nil, !usesRouteCorridor || (try? settings.validate()) != nil,
              position.distance(to:route.points[0]) <= settings.startRadius,
              !usesRouteCorridor || !pausesForPositionIssues || positionIssue(position) == nil else { return false }
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
    public mutating func pauseForUnclearHeading() { pause(reason:.unclearHeading) }
    private mutating func pause(reason: GuidePauseReason) {
        guard state == .guiding else { return }
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
        (!pausesForPositionIssues || (usesRouteCorridor ? positionIssue(position) == nil : route.area.contains(position,margin:settings.boundaryMargin))) &&
        route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty
    }
    /// Only the active entry/exit segment may extend outside the stage. This is not obstacle detection.
    public func positionIssue(_ position: FloorPoint) -> GuidePauseReason? {
        guard position.valid, route.points.indices.contains(targetIndex), targetIndex > 0 else { return .invalidSample }
        let externalSegment=route.version == 2 && (targetIndex == 1 || targetIndex == route.points.count-1)
        if !route.area.contains(position) && !externalSegment { return .outsideStage }
        let a=route.points[targetIndex-1], b=route.points[targetIndex]
        if position.distance(toSegmentFrom:a,to:b) > Self.corridorRadius { return .offRoute }
        // Chairs and stairs never stop guidance (#72); their open sides still shape the route when it is drawn.
        if route.obstacles.contains(where: { !$0.isStep && $0.blocksTravel(from:position,to:b,clearance:settings.obstacleClearance) }) {
            return .obstacleProximity
        }
        return nil
    }
    public func cue(position: FloorPoint, headingDegrees: Double) -> GuidanceCue? {
        guard route.points.indices.contains(targetIndex) else { return nil }
        return GuidanceCue(position:position,goal:route.points[targetIndex],headingDegrees:headingDegrees,sector:sector)
    }
    /// Recoverable pauses resume after one second of fresh, verified in-bounds samples and a valid heading.
    @discardableResult public mutating func observeAutomaticRecovery(time: Double, position: FloorPoint, headingDegrees: Double, trackingValid: Bool) -> Bool {
        guard !usesRouteCorridor, canAutomaticallyRecover else { return false }
        guard time.isFinite, position.valid, headingDegrees.isFinite, trackingValid,
              route.area.contains(position,margin:settings.boundaryMargin),
              lastReentryTime.map({time > $0 && time-$0 <= 0.5}) ?? true else {
            reentrySince=nil; lastReentryTime=nil; return false
        }
        lastReentryTime=time
        guard let since=reentrySince else { reentrySince=time; return false }
        guard time-since >= 1.0 else { return false }
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
        let issue = !pausesForPositionIssues ? nil : (usesRouteCorridor ? positionIssue(position) : (route.area.contains(position) ? nil : GuidePauseReason.outsideStage))
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
        let angle=StageHeading.bearing(from:position,to:goal,headingDegrees:headingDegrees)
        let normalized=(angle+360).truncatingRemainder(dividingBy:360)
        let candidate=StageHeading.sector(angle)
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
