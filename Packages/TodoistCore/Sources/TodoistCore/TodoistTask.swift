import Foundation

public struct TodoistTask: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let content: String
    public let projectId: String?
    public let priority: Int
    public let due: Due?

    public struct Due: Codable, Hashable, Sendable {
        public let date: String
        public let string: String
        public init(date: String, string: String) { self.date = date; self.string = string }
    }

    public init(id: String, content: String, projectId: String? = nil, priority: Int = 1, due: Due? = nil) {
        self.id = id; self.content = content; self.projectId = projectId; self.priority = priority; self.due = due
    }

    enum CodingKeys: String, CodingKey {
        case id, content, priority, due
        case projectId = "project_id"
    }
}
