import Foundation

/// A counter shared between the main thread, which moves it on, and background queues, which
/// check it before starting work that may no longer be wanted.
final class GenerationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func set(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func matches(_ token: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value == token
    }
}
