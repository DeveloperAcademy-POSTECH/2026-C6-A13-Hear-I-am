import Foundation
import HearIAmCore

extension GuidanceRecord {
    /// Active guidance time as mm:ss, or h:mm:ss from one hour.
    var activeDurationText: String {
        let value=Int(activeSeconds.rounded(.down))
        return value >= 3600 ? String(format:"%d:%02d:%02d",value/3600,(value/60)%60,value%60) : String(format:"%02d:%02d",value/60,value%60)
    }
}
