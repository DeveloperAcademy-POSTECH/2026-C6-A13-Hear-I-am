import Foundation

public struct GuideSettings: Codable, Equatable, Sendable {
    /// How far a route keeps from a blocking object's outline. It was 0.35 m until 10/18; on a 3 × 2.2 m
    /// stage that coloured 17% of the floor around one 0.5 m object, so it now matches the 0.15 m the
    /// performance plan editor already used (#38).
    public static let routeClearance=0.15
    public var arrivalRadius=0.35
    public var arrivalDwell=0.8
    public var startRadius=0.45
    public var frontToleranceDegrees=20.0
    public var boundaryMargin=0.30
    public var obstacleClearance=GuideSettings.routeClearance
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
