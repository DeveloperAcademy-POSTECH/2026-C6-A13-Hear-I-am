import Foundation
import HearIAmCore

/// Stepping away after guidance stopped for an obstacle or for leaving the route (decided 10/17).
/// Nobody can press a button during a performance, so guidance resumes on its own once it is safe.
struct EscapeState {
    static let safeSeconds=1.0, quietAfter=10.0, repeatEvery=5.0
    let reason: GuidePauseReason
    let startedAt: Double
    var lastSpoken: Double
    var safeSince: Double?
    var quiet=false
}
