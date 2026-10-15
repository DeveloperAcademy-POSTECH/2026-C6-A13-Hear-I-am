import Foundation
import simd

public struct FloorPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x=x; self.y=y }
    public var valid: Bool { x.isFinite && y.isFinite && abs(x) <= 500 && abs(y) <= 500 }
    public func distance(to p: FloorPoint) -> Double { hypot(x-p.x,y-p.y) }
}

/// Temporary floor-plane guides from the first two observed front corners.
/// They indicate direction only; the back edge remains unmeasured until E3 and E4 are captured.
public struct FrontEdgeGuide: Equatable, Sendable {
    public let leftStart: Point3
    public let rightStart: Point3
    public let leftEnd: Point3
    public let rightEnd: Point3
    public let length: Double

    public init(frontLeft: Point3, frontRight: Point3) throws {
        let dx=frontRight.x-frontLeft.x, dz=frontRight.z-frontLeft.z
        let width=hypot(dx,dz)
        guard frontLeft.valid, frontRight.valid, width >= 0.5,
              abs(frontRight.y-frontLeft.y) <= 0.20 else {
            throw LabError.invalid("앞의 두 꼭짓점은 같은 바닥에서 0.5m 이상 떨어져야 합니다.")
        }
        // Front-left -> front-right as seen from the audience. Clockwise in AR X/Z points backstage.
        let inwardX=dz/width, inwardZ = -dx/width
        let floor=(frontLeft.y+frontRight.y)/2
        length=max(3,min(12,width*1.2))
        leftStart=Point3(frontLeft.x,floor,frontLeft.z)
        rightStart=Point3(frontRight.x,floor,frontRight.z)
        leftEnd=Point3(frontLeft.x+inwardX*length,floor,frontLeft.z+inwardZ*length)
        rightEnd=Point3(frontRight.x+inwardX*length,floor,frontRight.z+inwardZ*length)
    }
}

/// Corners are front-left, front-right, back-right, back-left as seen from the audience.
/// Coordinates are AR world metres, with the floor in world X/Z and world Y vertical.
public struct StageArea: Codable, Equatable, Sendable {
    public let corners: [Point3]
    public let frontLeft: Point3
    public let right: FloorPoint
    public let back: FloorPoint
    public let width: Double
    public let depth: Double
    public let floorHeight: Double
    public let maxResidual: Double
    public init(corners: [Point3]) throws {
        guard corners.count == 4, corners.allSatisfy(\.valid) else { throw LabError.invalid("무대 꼭짓점 네 개가 필요합니다.") }
        let a=corners[0], b=corners[1], c=corners[2], d=corners[3]
        let height=corners.map(\.y).reduce(0,+)/4
        guard corners.allSatisfy({abs($0.y-height) <= 0.10}) else { throw LabError.invalid("네 꼭짓점이 같은 바닥 평면에 있지 않습니다.") }
        func unit(_ x: Double,_ y: Double) -> FloorPoint? { let n=hypot(x,y); return n > 0.5 ? FloorPoint(x/n,y/n) : nil }
        guard let u=unit(b.x-a.x,b.z-a.z) else { throw LabError.invalid("앞 변이 너무 짧습니다.") }
        let v=FloorPoint(u.y,-u.x)
        func dot(_ p: Point3,_ axis: FloorPoint) -> Double { (p.x-a.x)*axis.x+(p.z-a.z)*axis.y }
        let frontWidth=dot(b,u), backWidth=dot(c,u)-dot(d,u)
        let leftDepth=dot(d,v), rightDepth=dot(c,v)-dot(b,v)
        let w=(frontWidth+backWidth)/2, h=(leftDepth+rightDepth)/2
        guard w > 0.5, h > 0.5, leftDepth > 0, rightDepth > 0,
              abs(backWidth-frontWidth) <= max(0.12,0.08*w),
              abs(leftDepth-rightDepth) <= max(0.12,0.08*h) else {
            throw LabError.invalid("선택 순서가 교차하거나 직사각형의 대변 길이가 다릅니다.")
        }
        let local=[FloorPoint(0,0),FloorPoint(dot(b,u),dot(b,v)),FloorPoint(dot(c,u),dot(c,v)),FloorPoint(dot(d,u),dot(d,v))]
        let expected=[FloorPoint(0,0),FloorPoint(w,0),FloorPoint(w,h),FloorPoint(0,h)]
        let residual=zip(local,expected).map {$0.distance(to:$1)}.max() ?? .infinity
        guard residual <= max(0.12,0.04*min(w,h)) else { throw LabError.invalid("직각 또는 꼭짓점 오차가 큽니다. 점을 다시 선택하세요.") }
        self.corners=corners; frontLeft=a; right=u; back=v; width=w; depth=h
        floorHeight=height; maxResidual=residual
    }
    public func validate() throws {
        let rebuilt=try StageArea(corners:corners)
        guard frontLeft == rebuilt.frontLeft,
              abs(right.x-rebuilt.right.x)<1e-8, abs(right.y-rebuilt.right.y)<1e-8,
              abs(back.x-rebuilt.back.x)<1e-8, abs(back.y-rebuilt.back.y)<1e-8,
              abs(width-rebuilt.width)<1e-8, abs(depth-rebuilt.depth)<1e-8,
              abs(floorHeight-rebuilt.floorHeight)<1e-8,
              abs(maxResidual-rebuilt.maxResidual)<1e-8 else {
            throw LabError.invalid("저장된 무대 E가 원본 꼭짓점과 일치하지 않습니다.")
        }
    }
    public func floor(_ p: Point3) -> FloorPoint {
        FloorPoint((p.x-frontLeft.x)*right.x+(p.z-frontLeft.z)*right.y,
                   (p.x-frontLeft.x)*back.x+(p.z-frontLeft.z)*back.y)
    }
    public func world(_ p: FloorPoint) -> Point3 {
        Point3(frontLeft.x+p.x*right.x+p.y*back.x,floorHeight,
               frontLeft.z+p.x*right.y+p.y*back.y)
    }
    public func contains(_ p: FloorPoint, margin: Double = 0) -> Bool {
        margin >= 0 && p.valid && p.x >= margin && p.y >= margin &&
        p.x <= width-margin && p.y <= depth-margin
    }
    /// Outward from the front edge toward the audience, in AR world space.
    public var stageFront: FloorPoint { FloorPoint(-back.x,-back.y) }
}

public enum ObstacleKind: String, Codable, CaseIterable, Sendable { case stairs, box, other, platform }
public enum PassagePolicy: String, Codable, Sendable { case prohibited, passable }
public struct StageObstacle: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var kind: ObstacleKind
    public var passage: PassagePolicy
    public var vertices: [FloorPoint]
    public init(id: UUID = UUID(), name: String, kind: ObstacleKind, passage: PassagePolicy = .prohibited, vertices: [FloorPoint]) throws {
        self.id=id; self.name=name; self.kind=kind; self.passage=passage; self.vertices=vertices
        try validate()
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,
              (3...8).contains(vertices.count), vertices.allSatisfy(\.valid),
              abs(Self.area(vertices)) >= 0.02 else { throw LabError.invalid("장애물 영역에 유효한 꼭짓점 3~8개가 필요합니다.") }
        for i in vertices.indices {
            for j in vertices.indices where j > i+1 && !(i == 0 && j == vertices.count-1) {
                if Self.intersects(vertices[i],vertices[(i+1)%vertices.count],vertices[j],vertices[(j+1)%vertices.count]) {
                    throw LabError.invalid("장애물 영역이 자기 교차합니다.")
                }
            }
        }
    }
    private static func area(_ p: [FloorPoint]) -> Double {
        p.indices.reduce(0) { $0+p[$1].x*p[($1+1)%p.count].y-p[($1+1)%p.count].x*p[$1].y }/2
    }
    private static func cross(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint) -> Double {
        (b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x)
    }
    static func intersects(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint,_ d: FloorPoint) -> Bool {
        let e=1e-9
        let ab1=cross(a,b,c), ab2=cross(a,b,d), cd1=cross(c,d,a), cd2=cross(c,d,b)
        if ab1*ab2 < -e && cd1*cd2 < -e { return true }
        func on(_ p: FloorPoint,_ q: FloorPoint,_ r: FloorPoint) -> Bool {
            abs(cross(p,q,r)) <= e && r.x >= min(p.x,q.x)-e && r.x <= max(p.x,q.x)+e &&
            r.y >= min(p.y,q.y)-e && r.y <= max(p.y,q.y)+e
        }
        return on(a,b,c) || on(a,b,d) || on(c,d,a) || on(c,d,b)
    }
    public func contains(_ p: FloorPoint) -> Bool {
        var inside=false
        for i in vertices.indices {
            let a=vertices[i], b=vertices[(i+1)%vertices.count]
            if Self.distancePointSegment(p,a,b) < 1e-8 { return true }
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x-a.x)*(p.y-a.y)/(b.y-a.y)+a.x { inside.toggle() }
        }
        return inside
    }
    private static func distancePointSegment(_ p: FloorPoint,_ a: FloorPoint,_ b: FloorPoint) -> Double {
        let dx=b.x-a.x, dy=b.y-a.y, n=dx*dx+dy*dy
        let t=n > 0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/n)) : 0
        return hypot(p.x-a.x-t*dx,p.y-a.y-t*dy)
    }
    private static func segmentDistance(_ a: FloorPoint,_ b: FloorPoint,_ c: FloorPoint,_ d: FloorPoint) -> Double {
        if intersects(a,b,c,d) { return 0 }
        return min(distancePointSegment(a,c,d),distancePointSegment(b,c,d),
                   distancePointSegment(c,a,b),distancePointSegment(d,a,b))
    }
    public func overlaps(_ a: FloorPoint,_ b: FloorPoint, clearance: Double) -> Bool {
        if contains(a) || contains(b) { return true }
        return vertices.indices.contains { i in
            Self.segmentDistance(a,b,vertices[i],vertices[(i+1)%vertices.count]) <= clearance+1e-9
        }
    }
}

public struct StageRoute: Codable, Equatable, Sendable {
    public let version: Int
    public var area: StageArea
    /// p0 followed by p1...p5, all in stage floor metres.
    public var points: [FloorPoint]
    public var obstacles: [StageObstacle]
    public init(area: StageArea, points: [FloorPoint], obstacles: [StageObstacle], allowsOutsideEndpoints: Bool = false) throws {
        version=allowsOutsideEndpoints ? 2 : 1; self.area=area; self.points=points; self.obstacles=obstacles
        try validate()
    }
    public func validate() throws {
        try area.validate()
        guard [1,2].contains(version), ((version == 2 ? 3 : 2)...6).contains(points.count), points.allSatisfy(\.valid),
              Set(obstacles.map(\.id)).count == obstacles.count else { throw LabError.invalid("경로 버전, 순서 또는 점 개수가 유효하지 않습니다.") }
        for o in obstacles { try o.validate(); guard o.vertices.allSatisfy({area.contains($0)}) else { throw LabError.invalid("장애물이 무대 밖에 있습니다.") } }
    }
    public func conflicts(boundaryMargin: Double, obstacleClearance: Double) -> [String] {
        guard boundaryMargin >= 0, obstacleClearance >= 0 else { return ["여유 거리 설정 오류"] }
        var result=[String]()
        for i in points.indices where !(version == 2 && (i == 0 || i == points.count-1)) && !area.contains(points[i],margin:boundaryMargin) {
            result.append("p\(i)가 무대 경계 여유 밖입니다")
        }
        if points.count > 1 {
            for i in 0..<(points.count-1) {
                let a=points[i], b=points[i+1]
                if a.distance(to:b) < 0.05 { result.append("p\(i)→p\(i+1) 선분이 너무 짧습니다") }
                for o in obstacles where o.passage == .prohibited && o.overlaps(a,b,clearance:obstacleClearance) {
                    result.append("p\(i)→p\(i+1)이 \(o.name) 여유 영역과 겹칩니다")
                }
            }
        }
        return result
    }
}

public struct GuideSettings: Codable, Equatable, Sendable {
    public var arrivalRadius=0.35
    public var arrivalDwell=0.8
    public var startRadius=0.45
    public var frontToleranceDegrees=20.0
    public var boundaryMargin=0.30
    public var obstacleClearance=0.35
    public var repeatInterval=3.0
    public var headingHysteresisDegrees=6.0
    public init() {}
    public func validate() throws {
        let values=[arrivalRadius,arrivalDwell,startRadius,frontToleranceDegrees,
                    boundaryMargin,obstacleClearance,repeatInterval,headingHysteresisDegrees]
        guard values.allSatisfy({$0.isFinite}),
              (0.1...1.5).contains(arrivalRadius), (0.1...10).contains(arrivalDwell),
              (0.1...2).contains(startRadius), (1...90).contains(frontToleranceDegrees),
              (0...2).contains(boundaryMargin), (0...2).contains(obstacleClearance),
              (0.5...30).contains(repeatInterval), (0...20).contains(headingHysteresisDegrees) else {
            throw LabError.invalid("실험 설정값이 허용 범위를 벗어났습니다.")
        }
    }
}
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
