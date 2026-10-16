import Foundation

public struct TrialRecord: Codable, Sendable {
    public let sequence: Int
    public let wallTime: Date
    public let uptime: Double
    public let event: String
    public let detail: String
    public let position: Point3?
    public let heading: Double?
    public let tracking: String
    public let verified: Bool
    public let errorMeters: Double?
    public let coordinateSpace: String
    public let mapping: String
    public init(sequence: Int, uptime: Double, event: String, detail: String="",
                position: Point3?=nil, heading: Double?=nil, tracking: String="",
                verified: Bool=false, errorMeters: Double?=nil, coordinateSpace: String="stage", mapping: String="") {
        self.sequence=sequence; wallTime=Date(); self.uptime=uptime; self.event=event; self.detail=detail
        self.position=position; self.heading=heading; self.tracking=tracking
        self.verified=verified; self.errorMeters=errorMeters
        self.coordinateSpace=coordinateSpace; self.mapping=mapping
    }
}
