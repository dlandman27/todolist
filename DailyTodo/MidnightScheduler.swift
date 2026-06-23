import Foundation

/// Fires an action at the next local midnight while the app is in the foreground,
/// then reschedules for the following midnight. Cancelled when the app backgrounds.
/// Covers the "app left open across midnight" case without any background entitlement.
@MainActor
final class MidnightScheduler {
    private var task: Task<Void, Never>?

    /// Start (or restart) the loop. Idempotent — cancels any existing schedule first.
    func start(_ action: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor in
            while !Task.isCancelled {
                let now = Date()
                let nextMidnight = Calendar.current.nextDate(
                    after: now,
                    matching: DateComponents(hour: 0, minute: 0, second: 0),
                    matchingPolicy: .nextTime
                ) ?? now.addingTimeInterval(86_400)
                let seconds = max(1, nextMidnight.timeIntervalSince(now))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if Task.isCancelled { break }
                action()
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
