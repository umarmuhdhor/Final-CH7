import Foundation

extension Error {
    /// A task or URL request that was cancelled (view gone, refresh replaced): not a failure to show.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let error = self as? URLError, error.code == .cancelled { return true }
        return false
    }
}
