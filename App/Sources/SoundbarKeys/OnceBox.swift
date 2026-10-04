import Foundation

/// Resumes a continuation exactly once and runs a cleanup (main actor only).
@MainActor
final class OnceBox<T> {
    private var continuation: CheckedContinuation<T, Never>?
    private let cleanup: () -> Void

    init(_ continuation: CheckedContinuation<T, Never>, cleanup: @escaping () -> Void) {
        self.continuation = continuation
        self.cleanup = cleanup
    }

    func finish(_ value: T) {
        guard let c = continuation else { return }
        continuation = nil
        cleanup()
        c.resume(returning: value)
    }
}
