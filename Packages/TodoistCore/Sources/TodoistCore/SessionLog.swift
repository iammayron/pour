import Foundation

/// A finished focus block or break, and the tasks it touched.
///
/// The log of these is the app's only memory of what happened, so the round counter, the short/long
/// break decision and the Today view are all derived from it. Nothing counts rounds separately, which
/// means nothing can drift out of sync with the record.
public struct Session: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case focus, shortBreak, longBreak }

    /// One stretch of a focus session spent on a single task. A session running with an empty slot has
    /// no segment covering it — that gap is what the Today view shows as untracked rather than losing.
    public struct Segment: Codable, Sendable {
        public var taskId: String
        public var content: String
        public var start: Date
        public var end: Date?

        public init(taskId: String, content: String, start: Date, end: Date? = nil) {
            self.taskId = taskId; self.content = content; self.start = start; self.end = end
        }

        public var seconds: TimeInterval { (end ?? start).timeIntervalSince(start) }
    }

    public var id = UUID()
    public var kind: Kind
    public var start: Date
    public var end: Date?
    /// How long the session was set to run, extensions included. Shorter than `seconds` when stopped early.
    public var planned: TimeInterval
    public var segments: [Segment] = []

    public init(kind: Kind, start: Date, planned: TimeInterval) {
        self.kind = kind; self.start = start; self.planned = planned
    }

    public var seconds: TimeInterval { (end ?? start).timeIntervalSince(start) }
    /// Seconds this session ran with no task in the slot.
    public var untracked: TimeInterval { max(0, seconds - segments.reduce(0) { $0 + $1.seconds }) }
}

/// Every session Pour has run, in ~/Library/Application Support/Pour/sessions.json.
/// The read-only queries take the log as a parameter so they can be tested without touching disk.
public enum SessionLog {
    private static var file: URL { Support.file("sessions.json") }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    public static func all() -> [Session] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? decoder.decode([Session].self, from: data)) ?? []
    }

    /// ponytail: rewrites the whole file per append. Fine into the thousands of sessions; if it ever
    /// hurts, switch the file to one JSON object per line and append instead.
    public static func append(_ session: Session) {
        var log = all()
        log.append(session)
        try? encoder.encode(log).write(to: file, options: .atomic)
    }

    /// Focus sessions completed since the last long break — the pomodoro round counter.
    public static func roundsSinceLongBreak(_ log: [Session] = all()) -> Int {
        log.reversed().prefix { $0.kind != .longBreak }.filter { $0.kind == .focus }.count
    }

    public static func today(_ log: [Session] = all(), now: Date = Date()) -> [Session] {
        log.filter { Calendar.current.isDate($0.start, inSameDayAs: now) }
    }
}
