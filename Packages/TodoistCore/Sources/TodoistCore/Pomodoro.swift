import Foundation
import Observation

/// Pomodoro state machine. Time is derived from `endDate`, so it survives sleep.
@Observable
public final class Pomodoro {
    public enum Phase: Equatable, Sendable { case idle, work, workDone, rest }

    public private(set) var phase: Phase = .idle
    public private(set) var task: TodoistTask?
    public private(set) var total: TimeInterval = 0
    public private(set) var endDate: Date?
    /// Remaining seconds while paused; nil when running.
    public private(set) var pausedRemaining: TimeInterval?

    public var workDuration: TimeInterval
    public var breakDuration: TimeInterval
    public var now: () -> Date = Date.init

    public init(workMinutes: Double = 25, breakMinutes: Double = 5) {
        workDuration = workMinutes * 60
        breakDuration = breakMinutes * 60
    }

    public var isPaused: Bool { pausedRemaining != nil }
    public var isRunning: Bool { phase != .idle }

    public var remaining: TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(now()))
    }

    /// 0…1 water level: fills during work, drains during rest, full when done.
    public var level: Double {
        guard total > 0 else { return 0 }
        let progress = 1 - remaining / total
        switch phase {
        case .idle: return 0
        case .work: return progress
        case .workDone: return 1
        case .rest: return 1 - progress
        }
    }

    public func start(_ task: TodoistTask) {
        self.task = task
        begin(.work, duration: workDuration)
    }

    public func startBreak() { begin(.rest, duration: breakDuration) }

    public func stop() {
        phase = .idle; task = nil; endDate = nil; pausedRemaining = nil; total = 0
    }

    public func togglePause() {
        guard phase == .work || phase == .rest else { return }
        if let r = pausedRemaining {
            endDate = now().addingTimeInterval(r); pausedRemaining = nil
        } else {
            pausedRemaining = remaining; endDate = nil
        }
    }

    public func extend(by seconds: TimeInterval) {
        guard phase == .work || phase == .rest else { return }
        total += seconds
        if let r = pausedRemaining { pausedRemaining = r + seconds } else { endDate = endDate?.addingTimeInterval(seconds) }
    }

    /// Call on each tick. Returns the phase that just finished, if any.
    @discardableResult
    public func tick() -> Phase? {
        guard !isPaused, endDate != nil, remaining == 0 else { return nil }
        switch phase {
        case .work: phase = .workDone; endDate = nil; return .work
        case .rest: stop(); return .rest
        default: return nil
        }
    }

    private func begin(_ p: Phase, duration: TimeInterval) {
        phase = p; total = duration; pausedRemaining = nil
        endDate = now().addingTimeInterval(duration)
    }
}
