import Foundation

/// Elapsed-time model.
/// Uses system uptime, which does not advance while the Mac sleeps,
/// so a running stopwatch effectively pauses during sleep.
final class Stopwatch {
    private var accumulated: TimeInterval = 0
    private var startedAt: TimeInterval?

    var isRunning: Bool { startedAt != nil }

    var elapsed: TimeInterval {
        accumulated + (startedAt.map { Self.now() - $0 } ?? 0)
    }

    func toggle() {
        if let startedAt {
            accumulated += Self.now() - startedAt
            self.startedAt = nil
        } else {
            startedAt = Self.now()
        }
    }

    func reset() {
        accumulated = 0
        startedAt = nil
    }

    /// "MM:SS" under one hour, "H:MM" from one hour on.
    static func format(_ elapsed: TimeInterval) -> String {
        let total = Int(elapsed)
        if total < 3600 {
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
