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
    /// Explicit point facing takes priority over a chair/stairs facing edge.
    public private(set) var facingPointIndex: Int?
    public static let facingToleranceDegrees = 15.0
    private var facingGate=DepartureGate()
    public private(set) var holdRemaining: Double = 0
    public var isHolding: Bool { holdRemaining > 0 }
    public private(set) var pauseReason: GuidePauseReason?
    /// An opt-in rehearsal detour uses the original point identifiers and never rewrites the saved route.
    public private(set) var rehearsalReturnDestinationIndex: Int?
    /// A dwell-confirmed return destination waits here until explicit forward continuation.
    public private(set) var rehearsalReturnArrivalIndex: Int?
    public var isReturningForRehearsal: Bool {
        rehearsalReturnDestinationIndex != nil && rehearsalReturnArrivalIndex == nil
    }
    /// The active segment may run backwards during rehearsal; consumers must not assume targetIndex - 1.
    public var activeSegmentStartIndex: Int {
        rehearsalReturnDestinationIndex == nil ? targetIndex - 1 : targetIndex + 1
    }
    public var canAutomaticallyRecover: Bool { state == .paused && (pauseReason == .outsideStage || pauseReason == .sampleGap || pauseReason == .unclearHeading) }
    public let route: StageRoute
    public let settings: GuideSettings
    /// Opt in for the portrait guidance flow. The legacy experiment keeps its original rules.
    public let usesRouteCorridor: Bool
    /// Whether stepping off the corridor, outside the stage or near an obstacle pauses guidance (#74).
    public let pausesForPositionIssues: Bool
    /// Only temporary start approaches use this boundary; saved performance routes keep their original rules.
    public let approachFootprint: ScannedFootprint?
    private var pathIsValid: Bool {
        if let footprint=approachFootprint {
            return route.travelConflicts(obstacleClearance:settings.obstacleClearance).isEmpty &&
                zip(route.points,route.points.dropFirst()).allSatisfy { footprint.covers(from:$0.0,to:$0.1) }
        }
        return route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty
    }
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
    public init(route: StageRoute, settings: GuideSettings, usesRouteCorridor: Bool = false, pausesForPositionIssues: Bool = true, approachFootprint: ScannedFootprint? = nil) {
        self.route=route; self.settings=settings; self.usesRouteCorridor=usesRouteCorridor; self.pausesForPositionIssues=pausesForPositionIssues;self.approachFootprint=approachFootprint
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
            pathIsValid
    }
    @discardableResult public mutating func start(position: FloorPoint, headingDegrees: Double, trackingValid: Bool) -> Bool {
        guard state == .idle, ready(position:position,headingDegrees:headingDegrees,trackingValid:trackingValid) else { return false }
        state = .guiding; targetIndex=1; facingPointIndex=route.facing(at:0) == nil ? nil : 0; facingGate.reset(); holdRemaining=0; arrivedSince=nil; lastTime=nil; lastSpeech = -.infinity; sector=nil; pauseReason=nil
        return true
    }
    public mutating func pause() { pause(reason:.manual) }
    public mutating func pauseForUnclearHeading() { pause(reason:.unclearHeading) }
    private mutating func pause(reason: GuidePauseReason) {
        guard state == .guiding else { return }
        state = .paused; facingGate.reset(); pauseReason=reason; arrivedSince=nil; reentrySince=nil; lastReentryTime=nil
    }
    @discardableResult public mutating func resume(position: FloorPoint, trackingValid: Bool) -> Bool {
        guard canResume(position:position,trackingValid:trackingValid) else { return false }
        state = .guiding; pauseReason=nil; arrivedSince=nil; lastTime=nil; lastSpeech = -.infinity
        reentrySince=nil; lastReentryTime=nil; sector=nil
        return true
    }
    public func canResume(position: FloorPoint, trackingValid: Bool) -> Bool {
        state == .paused && rehearsalReturnArrivalIndex == nil && trackingValid && position.valid &&
        (!pausesForPositionIssues || (usesRouteCorridor ? positionIssue(position) == nil : route.area.contains(position,margin:settings.boundaryMargin))) &&
        pathIsValid
    }
    /// P numbers name ordinary waypoints; chair/stair milestones also occupy route indices.
    public func rehearsalPointIndex(number: Int) -> Int? {
        guard number > 0 else {return nil}
        return route.points.indices.first {route.pointLabel(at:$0).caseInsensitiveCompare("P\(number)") == .orderedSame}
    }
    /// Begins a rehearsal-only return along previously completed, contiguous route segments.
    /// The caller must supply a fresh verified pose, stop competing speech, and explicitly opt in.
    /// Every reverse leg is checked using current develop obstacle rules; chairs and stairs remain freely approachable.
    public mutating func beginRehearsalReturn(to index: Int, position: FloorPoint,
                                             headingDegrees: Double, trackingValid: Bool) throws {
        guard usesRouteCorridor, state == .guiding || state == .paused,
              rehearsalReturnDestinationIndex == nil,
              (try? route.validate()) != nil, (try? settings.validate()) != nil,
              route.conflicts(boundaryMargin:settings.boundaryMargin,obstacleClearance:settings.obstacleClearance).isEmpty else {
            throw RehearsalReturnError.unavailable
        }
        guard trackingValid, position.valid, headingDegrees.isFinite else {
            throw RehearsalReturnError.trackingUnavailable
        }
        guard index > 0, index < route.points.count-1, index < targetIndex else {
            throw RehearsalReturnError.unvisitedDestination
        }
        if let issue=positionIssue(position) { throw RehearsalReturnError.positionUnsafe(issue) }
        let firstIndex=targetIndex-1
        var legStart=position
        for destination in stride(from:firstIndex,through:index,by:-1) {
            let legEnd=route.points[destination]
            if let obstacle=route.obstacles.first(where: {
                $0.blocksTravel(from:legStart,to:legEnd,clearance:settings.obstacleClearance)
            }) { throw RehearsalReturnError.blockedByObstacle(obstacle.name) }
            legStart=legEnd
        }
        // All validation happens before mutation so a rejected request preserves the current target.
        rehearsalReturnDestinationIndex=index; rehearsalReturnArrivalIndex=nil; targetIndex=firstIndex
        state = .guiding; pauseReason=nil; holdRemaining=0; arrivedSince=nil; lastTime=nil
        lastSpeech = -.infinity; sector=nil; reentrySince=nil; lastReentryTime=nil
    }
    public func canResumeForwardAfterRehearsalReturn(position: FloorPoint, trackingValid: Bool) -> Bool {
        guard state == .paused, let arrived=rehearsalReturnArrivalIndex,
              rehearsalReturnDestinationIndex == arrived, trackingValid, position.valid,
              position.distance(to:route.points[arrived]) <= settings.startRadius else { return false }
        var forward=self
        forward.rehearsalReturnDestinationIndex=nil; forward.rehearsalReturnArrivalIndex=nil
        forward.targetIndex=arrived+1
        return forward.canResume(position:position,trackingValid:trackingValid)
    }
    /// A return is not completion of the original run. Explicit continuation restores the next saved point.
    @discardableResult public mutating func resumeForwardAfterRehearsalReturn(position: FloorPoint, trackingValid: Bool) -> Bool {
        guard canResumeForwardAfterRehearsalReturn(position:position,trackingValid:trackingValid),
              let arrived=rehearsalReturnArrivalIndex else { return false }
        rehearsalReturnDestinationIndex=nil; rehearsalReturnArrivalIndex=nil; targetIndex=arrived+1
        return resume(position:position,trackingValid:trackingValid)
    }

    /// Only the active entry/exit segment may extend outside the stage. This is not obstacle detection.
    public func positionIssue(_ position: FloorPoint) -> GuidePauseReason? {
        guard position.valid, route.points.indices.contains(targetIndex), targetIndex > 0,
              route.points.indices.contains(activeSegmentStartIndex) else { return .invalidSample }
        let lowerIndex=min(activeSegmentStartIndex,targetIndex), upperIndex=max(activeSegmentStartIndex,targetIndex)
        let externalSegment=route.version == 2 &&
            (lowerIndex == 0 && upperIndex == 1 || lowerIndex == route.points.count-2 && upperIndex == route.points.count-1)
        if let footprint=approachFootprint {
            if !footprint.covers(from:position,to:route.points[targetIndex]) { return .outsideStage }
        } else if !route.area.contains(position) && !externalSegment { return .outsideStage }
        let a=route.points[activeSegmentStartIndex], b=route.points[targetIndex]
        if position.distance(toSegmentFrom:a,to:b) > Self.corridorRadius { return .offRoute }
        // Chairs and stairs never stop guidance (#72); their open sides still shape the route when it is drawn.
        if route.obstacles.contains(where: { !$0.isStep && $0.blocksTravel(from:position,to:b,clearance:settings.obstacleClearance) }) {
            return .obstacleProximity
        }
        return nil
    }
    public func cue(position: FloorPoint, headingDegrees: Double) -> GuidanceCue? {
        guard facingPointIndex == nil, !isHolding, route.points.indices.contains(targetIndex) else { return nil }
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
    public mutating func observe(time: Double, position: FloorPoint, headingDegrees: Double, trackingValid: Bool, allowsTargetAdvance: Bool = true, allowsFacingCompletion: Bool = true) -> GuideUpdate {
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
        let elapsed=lastTime.map {time-$0} ?? 0
        lastTime=time
        if let index=facingPointIndex, let facing=route.facing(at:index) {
            let eligible=allowsFacingCompletion && position.distance(to:route.points[index]) <= (index == 0 ? settings.startRadius : settings.arrivalRadius) && abs(facing.bearing(headingDegrees:headingDegrees)) <= Self.facingToleranceDegrees
            if facingGate.observe(time:time,eligible:eligible) {
                facingPointIndex=nil;facingGate.reset();arrivedSince=nil
                holdRemaining=Double(route.holdSeconds(at:index))
                if index == route.points.count-1 { state = .completed }
            }
            return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil)
        }
        if isHolding {
            holdRemaining=max(0,holdRemaining-elapsed)
            arrivedSince=nil
            if isHolding { return GuideUpdate(state:state,targetIndex:targetIndex,announcement:nil) }
            lastSpeech=time; sector=nil
            // Do not count dwell or advance again on the hold-expiry frame.
            return GuideUpdate(state:state,targetIndex:targetIndex,announcement:cue(position:position,headingDegrees:headingDegrees)?.speech)
        }
        var goal=route.points[targetIndex], distance=position.distance(to:goal)
        var arrivedIndex: Int?
        if allowsTargetAdvance && distance <= settings.arrivalRadius {
            if arrivedSince == nil { arrivedSince=time }
            if let since=arrivedSince, time-since >= settings.arrivalDwell {
                if let returnDestination=rehearsalReturnDestinationIndex {
                    if targetIndex == returnDestination {
                        rehearsalReturnArrivalIndex=targetIndex
                        pause(reason:.manual)
                        return GuideUpdate(state:state,targetIndex:targetIndex,
                            announcement:"\(route.pointLabel(at:targetIndex)) 지점에 도착했습니다. 계속하려면 계속이라고 말씀해주세요.")
                    }
                    arrivedIndex=targetIndex
                    targetIndex -= 1; arrivedSince=nil; sector=nil
                } else {
                    if route.facing(at:targetIndex) != nil {
                        let index=targetIndex
                        facingPointIndex=index;facingGate.reset();arrivedSince=nil;sector=nil
                        if index < route.points.count-1 { targetIndex += 1 }
                        return GuideUpdate(state:state,targetIndex:targetIndex,announcement:"\(route.pointLabel(at:index)) 도착.")
                    }
                    if targetIndex == route.points.count-1 {
                        state = .completed
                        return GuideUpdate(state:state,targetIndex:targetIndex,announcement:GuidanceCopy.completed)
                    }
                    arrivedIndex=targetIndex
                    holdRemaining=Double(route.holdSeconds(at:targetIndex))
                    targetIndex += 1; arrivedSince=nil; sector=nil
                }
                goal=route.points[targetIndex]; distance=position.distance(to:goal)
            }
        } else { arrivedSince=nil }
        if isHolding, let arrivedIndex {
            lastSpeech=time
            return GuideUpdate(state:state,targetIndex:targetIndex,announcement:"\(arrivedIndex)번째 지점 도착.")
        }
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
