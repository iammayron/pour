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
