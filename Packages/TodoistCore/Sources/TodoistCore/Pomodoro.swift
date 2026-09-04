import Foundation
import Observation

/// Pomodoro state machine. Time is derived from `endDate`, so it survives sleep.
///
/// The clock is deliberately independent of the task: `task` is a slot the session points at, and
/// writing it never touches `endDate`. That is what lets a task be completed, swapped or left empty
/// while the same session keeps running.
@Observable
public final class Pomodoro {
    public enum Phase: String, Codable, Equatable, Sendable { case idle, work, workDone, rest }

    public private(set) var phase: Phase = .idle
    /// The task the session is currently pointed at. Assigning it is free of side effects.
    public var task: TodoistTask?
    public private(set) var total: TimeInterval = 0
    public private(set) var endDate: Date?
    /// Remaining seconds while paused; nil when running.
    public private(set) var pausedRemaining: TimeInterval?

    /// True while the current rest is a long break, so the card can say so.
    public private(set) var isLongBreak = false

    public var workDuration: TimeInterval
    public var breakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var now: () -> Date = Date.init

    public init(workMinutes: Double = 25, breakMinutes: Double = 5, longBreakMinutes: Double = 15) {
        workDuration = workMinutes * 60
        breakDuration = breakMinutes * 60
        longBreakDuration = longBreakMinutes * 60
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

    /// Starts a focus session. Whatever is in `task` stays there; nothing needs to be in it.
    public func start() { begin(.work, duration: workDuration) }

    /// Breaks carry no task — they belong to the session, not to whatever you were working on.
    public func startBreak(long: Bool = false) {
        task = nil
        isLongBreak = long
        begin(.rest, duration: long ? longBreakDuration : breakDuration)
    }

    public func stop() {
        phase = .idle; task = nil; endDate = nil; pausedRemaining = nil; total = 0; isLongBreak = false
    }

    // MARK: - Surviving a relaunch

    /// Everything needed to rebuild a live session in a new process. `remaining` reads from `endDate`,
    /// so a restored session is exactly as far along as it would have been had the app stayed open.
    public struct Snapshot: Codable, Sendable {
        public var phase: Phase
        public var task: TodoistTask?
        public var total: TimeInterval
        public var endDate: Date?
        public var pausedRemaining: TimeInterval?
        public var isLongBreak: Bool
    }

    public var snapshot: Snapshot {
        Snapshot(phase: phase, task: task, total: total, endDate: endDate,
                 pausedRemaining: pausedRemaining, isLongBreak: isLongBreak)
    }

    public func restore(_ s: Snapshot) {
        phase = s.phase; task = s.task; total = s.total
        endDate = s.endDate; pausedRemaining = s.pausedRemaining; isLongBreak = s.isLongBreak
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
