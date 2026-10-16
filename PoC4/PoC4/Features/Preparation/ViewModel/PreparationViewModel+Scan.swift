import PoC4Core

/// Step 1 · 스캔
extension PreparationViewModel {
    var canConfirmScan: Bool { session.canConfirmScan }
    /// Called from the confirmation alert. Scanning cannot be revisited afterwards.
    func confirmScan() {
        if session.canConfirmScan { scanConfirmed=true }
        if scanConfirmed {advance()}
    }
}
