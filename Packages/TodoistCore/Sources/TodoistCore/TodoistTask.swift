import Foundation

public struct TodoistTask: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let content: String
    public let projectId: String?
    public let priority: Int
    public let due: Due?
    public let labels: [String]

    public struct Due: Codable, Hashable, Sendable {
        public let date: String
        public let string: String
        public init(date: String, string: String) { self.date = date; self.string = string }
    }

    public init(id: String, content: String, projectId: String? = nil, priority: Int = 1, due: Due? = nil, labels: [String] = []) {
        self.id = id; self.content = content; self.projectId = projectId; self.priority = priority; self.due = due; self.labels = labels
    }

    enum CodingKeys: String, CodingKey {
        case id, content, priority, due, labels
        case projectId = "project_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = try c.decode(String.self, forKey: .content)
        projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 1
        due = try c.decodeIfPresent(Due.self, forKey: .due)
        labels = try c.decodeIfPresent([String].self, forKey: .labels) ?? []
    }
}

public struct TodoistProject: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
}

public extension TodoistTask {
    /// Presets the picker offers. Tasks come from one `overdue | 7 days` fetch, so "7 days" is
    /// everything not overdue and "upcoming" is everything.
    static let filters = ["upcoming", "today", "overdue", "7 days"]

    /// Whether the task falls in `filter`, given today as yyyy-MM-dd (local calendar).
    func matches(_ filter: String, today: String) -> Bool {
        guard let due else { return filter == "upcoming" }
        let day = String(due.date.prefix(10)) // "2026-09-04" or "2026-09-04T10:00:00"
        switch filter {
        case "today": return day == today
        case "overdue": return day < today
        case "7 days": return day >= today
        default: return true
        }
    }
}

public extension TodoistTask.Due {
    /// Todoist echoes whatever the user typed back in `string` ("tomorrow", "2026-07-20 12:00"),
    /// so rows format `date` instead: "Sep 4", "Sep 4, 12:00", "Jul 20, 2026".
    var label: String {
        guard let d = parsed else { return string }
        var style = Date.FormatStyle().month(.abbreviated).day()
        let cal = Calendar.current
        if cal.component(.year, from: d) != cal.component(.year, from: Date()) { style = style.year() }
        if hasTime { style = style.hour().minute() }
        return d.formatted(style)
    }

    var hasTime: Bool { date.count > 10 }

    /// `date` is "yyyy-MM-dd", a floating "yyyy-MM-ddTHH:mm:ss", or the same with a trailing Z (UTC).
    var parsed: Date? {
        let n = date.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard n.count >= 3 else { return nil }
        var c = DateComponents()
        (c.year, c.month, c.day) = (n[0], n[1], n[2])
        if n.count >= 5 { (c.hour, c.minute) = (n[3], n[4]) }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = date.hasSuffix("Z") ? TimeZone(secondsFromGMT: 0)! : .current
        return cal.date(from: c)
    }
}
