import UIKit
import HearIAmCore

/// Experiment log bookkeeping for the current session.
extension ARSessionController {
    func beginLog(source: String) {
        if let failure=logger.begin(metadata:[
            "source":source,"scanID":scanID.uuidString,"sessionID":token.uuidString,
            "device":UIDevice.current.model,"os":UIDevice.current.systemVersion,
            "appVersion":Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "checkpointToleranceMeters":String(checkpointTolerance),"maxSampleAgeSeconds":"0.5",
            "arrivalRadiusMeters":String(settings.arrivalRadius),"arrivalDwellSeconds":String(settings.arrivalDwell),
            "startRadiusMeters":String(settings.startRadius),"frontToleranceDegrees":String(settings.frontToleranceDegrees),
            "coordinates":"X audience-right from front-left; Y backstage; Z up; heading clockwise from stage-front",
            "positionMeaning":"phone horizontal projection; not foot or ground truth"]) {
            errorMessage=failure; return
        }
        event("session_start",detail:source)
    }
    func event(_ name: String, detail: String="", position: Point3?=nil, heading: Double?=nil,
               error: Double?=nil, time: Double?=nil) {
        logger.record(name,detail:detail,position:position,heading:heading,error:error,time:time ?? now,
            context:.init(tracking:latest?.tracking ?? tracking,verified:gate.isReady(now:now),mapping:latest?.mapping ?? mapping))
    }
    func stopLog() {
        guard logger.isOpen else { return }
        event("session_end")
        logger.close { [weak self] message in self?.errorMessage=message }
    }
}
