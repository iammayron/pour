import Foundation

public struct TodoistError: LocalizedError {
    public let status: Int
    public let body: String
    public var errorDescription: String? { "Todoist HTTP \(status): \(body)" }
}

/// Minimal Todoist API v1 client. Personal API token auth.
/// ponytail: no retries, no offline cache; add when the app is used on flaky networks.
public actor TodoistClient {
    private let token: String
    private let base = URL(string: "https://api.todoist.com/api/v1")!
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public func tasks(filter: String = "today") async throws -> [TodoistTask] {
        try await allPages("tasks/filter", query: [URLQueryItem(name: "query", value: filter)])
    }

    /// id → name for every project.
    public func projects() async throws -> [String: String] {
        let list: [TodoistProject] = try await allPages("projects")
        return Dictionary(list.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private struct Page<T: Decodable>: Decodable { let results: [T]; let next_cursor: String? }

    private func allPages<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> [T] {
        var all: [T] = []
        var cursor: String? = nil
        repeat {
            var items = query
            if let cursor { items.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: Page<T> = try await send("GET", path, query: items)
            all += page.results
            cursor = page.next_cursor
        } while cursor != nil
        return all
    }

    /// Whether the task is completed or gone, used to tell "finished elsewhere" from "rescheduled out of view".
    /// A deleted task still answers 200 with `is_deleted`, and one deleted without being ticked has no
    /// `completed_at`, so all three fields are checked.
    public func isClosed(taskId: String) async throws -> Bool {
        struct Probe: Decodable { let completed_at: String?; let checked: Bool?; let is_deleted: Bool? }
        do {
            let probe: Probe = try await send("GET", "tasks/\(taskId)")
            return probe.completed_at != nil || probe.checked == true || probe.is_deleted == true
        } catch let e as TodoistError where e.status == 404 {
            return true   // purged
        }
    }

    public func close(taskId: String) async throws {
        let _: Empty = try await send("POST", "tasks/\(taskId)/close")
    }

    public func comment(taskId: String, content: String) async throws {
        struct Body: Encodable { let task_id: String; let content: String }
        let _: Empty = try await send("POST", "comments", body: Body(task_id: taskId, content: content))
    }

    // MARK: - plumbing

    private struct Empty: Decodable { init() {} ; init(from decoder: Decoder) throws {} }

    private func send<T: Decodable>(_ method: String, _ path: String,
                                    query: [URLQueryItem] = [], body: (any Encodable)? = nil) async throws -> T {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw TodoistError(status: status, body: String(decoding: data, as: UTF8.self))
        }
        if data.isEmpty || T.self == Empty.self { return Empty() as! T }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
