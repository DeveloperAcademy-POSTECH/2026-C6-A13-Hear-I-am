import Foundation
import HearIAmCore

/// Observe only: recording must not alter the develop branch's guidance or signal decisions.
extension GuidanceViewModel {
    func captureReplay(force: Bool = false) {
        guard started,run != nil,phase != .finishing,phase != .completed else {return}
        let status: GuidanceReplayStatus
        switch phase {
        case .guiding: status = .guiding
        case .paused:
            switch guide?.pauseReason {
            case .offRoute: status = .offRoute
            case .outsideStage: status = .outsideStage
            case .obstacleProximity: status = .obstacle
            default: status = .paused
            }
        default: status = .recovering
        }
        let pose=freshPose()
        run?.capture(position:pose?.point,heading:pose?.heading,targetIndex:targetIndex,
            status:pose == nil ? .untracked : status,uptime:ProcessInfo.processInfo.systemUptime,force:force)
    }
}
