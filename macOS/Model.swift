import AppKit
import AuthenticationServices
import Observation
import TodoistCore
import UserNotifications

@Observable @MainActor
final class AppModel {
    let pomodoro: Pomodoro
    var tasks: [TodoistTask] = []
    var projects: [String: String] = [:]
    var selectedTaskId: String?
    var search = ""
    var error: String?
    var loading = false
    /// Increments every second while a session runs, so views re-read time-derived values.
    private(set) var tick = 0
    /// When the automatic break will start after a finished focus session.
    private(set) var breakAt: Date?

    // MARK: - Settings (UserDefaults-backed)

    /// The pasted personal token, or the OAuth access token. Writing it replaces any OAuth pair.
    var token: String {
        get { auth?.accessToken ?? "" }
        set { guard newValue != token else { return }; auth = newValue.isEmpty ? nil : TodoistAuth(accessToken: newValue); lastSaved = Date() }
    }

    /// Single source of truth for credentials: writing it persists and rebuilds the client.
    private var auth: TodoistAuth? {
        didSet { TokenStore.auth = auth; client = auth.map { TodoistClient(token: $0.accessToken) } }
    }
    var isConnected: Bool { auth != nil }
    var isOAuth: Bool { auth?.isOAuth ?? false }
    var filter: String       { didSet { guard filter != oldValue else { return }; save(filter, "filter") } }
    var workMinutes: Double  { didSet { guard workMinutes != oldValue else { return }; save(workMinutes, "workMinutes") } }
    var breakMinutes: Double { didSet { guard breakMinutes != oldValue else { return }; save(breakMinutes, "breakMinutes") } }
    var autoBreak: Bool      { didSet { guard autoBreak != oldValue else { return }; save(autoBreak, "autoBreak") } }
    var sound: Bool          { didSet { guard sound != oldValue else { return }; save(sound, "sound") } }
    var notifications: Bool  { didSet { guard notifications != oldValue else { return }; save(notifications, "notifications") } }
    var logComment: Bool     { didSet { guard logComment != oldValue else { return }; save(logComment, "logComment") } }
    var compactCard: Bool    { didSet { guard compactCard != oldValue else { return }; save(compactCard, "compactCard"); panel?.setContentSize(FloatingView.size(compact: compactCard)) } }
    var allSpaces: Bool      { didSet { guard allSpaces != oldValue else { return }; save(allSpaces, "allSpaces"); panel?.applySpaces(allSpaces) } }

    /// Bumped on every settings write so the Settings window can flash "Saved".
    private(set) var lastSaved: Date?
    private func save(_ value: Any, _ key: String) { d.set(value, forKey: key); lastSaved = Date() }

    private let d = UserDefaults.standard
    private var client: TodoistClient?
    private var panel: FloatingPanel?
    private var ticker: Timer?
    private var autoBreakTask: Task<Void, Never>?
    private var lastLoad: Date?

    init() {
        d.register(defaults: ["filter": "today", "workMinutes": 25.0, "breakMinutes": 5.0, "autoBreak": true,
                              "sound": true, "notifications": true, "logComment": true, "compactCard": false, "allSpaces": true])
        filter = d.string(forKey: "filter")!
        workMinutes = d.double(forKey: "workMinutes"); breakMinutes = d.double(forKey: "breakMinutes")
        autoBreak = d.bool(forKey: "autoBreak"); sound = d.bool(forKey: "sound"); notifications = d.bool(forKey: "notifications")
        logComment = d.bool(forKey: "logComment"); compactCard = d.bool(forKey: "compactCard"); allSpaces = d.bool(forKey: "allSpaces")
        pomodoro = Pomodoro(workMinutes: d.double(forKey: "workMinutes"), breakMinutes: d.double(forKey: "breakMinutes"))
        auth = TokenStore.auth                                    // didSet does not fire from init
        client = auth.map { TodoistClient(token: $0.accessToken) }
    }

    var visibleTasks: [TodoistTask] {
        tasks.filter { $0.matches(filter, today: today) && (search.isEmpty || $0.content.localizedCaseInsensitiveContains(search)) }
    }
    func isOverdue(_ task: TodoistTask) -> Bool { task.matches("overdue", today: today) }
    func count(_ filter: String) -> Int { tasks.filter { $0.matches(filter, today: today) }.count }
    private var today: String { Date().formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()) }
    var selectedTask: TodoistTask? { tasks.first { $0.id == selectedTaskId } }

    /// "Project · Label · Label" for a task, empty when there is neither.
    func meta(_ task: TodoistTask?) -> String {
        guard let task else { return "" }
        return ([task.projectId.flatMap { projects[$0] }] + task.labels).compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: - Todoist

    /// Reloads the list. `ifOlderThan` skips the fetch when the last successful load is newer than that,
    /// so reopening the menu twice in a row does not hit the API twice.
    /// Every Todoist call goes through here, so the expiry check and refresh live in exactly one place.
    private func api() async -> TodoistClient? {
        guard let current = auth else { error = "Connect Todoist in Settings."; return nil }
        if current.isExpired {
            do { auth = try await TodoistOAuth.refresh(current) }   // rotates: the new pair replaces the old
            catch { self.error = "Todoist sign-in expired. Reconnect in Settings."; return nil }
        }
        return client
    }

    /// Runs the OAuth flow and stores the resulting pair. A cancelled sign-in is not an error.
    func connect() async {
        do { auth = try await TodoistOAuth.connect(); error = nil; lastSaved = Date(); lastLoad = nil; await loadTasks() }
        catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin { }
        catch { self.error = error.localizedDescription }
    }

    func disconnect() {
        auth = nil; tasks = []; projects = [:]; selectedTaskId = nil; lastLoad = nil; error = nil; lastSaved = Date()
    }

    func loadTasks(ifOlderThan seconds: TimeInterval = 0) async {
        if let lastLoad, Date().timeIntervalSince(lastLoad) < seconds { return }
        guard let client = await api() else { return }
        loading = true; defer { loading = false }
        do {
            async let t = client.tasks(filter: "overdue | 7 days") // one fetch, bucketed locally so every preset shows its count
            async let p = client.projects()
            (tasks, projects) = try await (t, p); error = nil; lastLoad = Date()
            await stopIfRunningTaskFinished(client)
        } catch { self.error = error.localizedDescription }
    }

    /// A session whose task was completed in Todoist should not keep counting down.
    /// The list is the whole universe of startable tasks, so a running task missing from a fresh
    /// fetch is either done or rescheduled out of the window — one probe tells those apart.
    private func stopIfRunningTaskFinished(_ client: TodoistClient) async {
        guard let running = pomodoro.task, !tasks.contains(where: { $0.id == running.id }) else { return }
        guard (try? await client.isClosed(taskId: running.id)) == true else { return }
        stop()
    }

    func complete() async {
        guard let task = pomodoro.task, let client = await api() else { return }
        do { try await client.close(taskId: task.id); tasks.removeAll { $0.id == task.id }; stop() }
        catch { self.error = error.localizedDescription }
    }

    // MARK: - Session

    func startSelected() { if let t = selectedTask { start(t) } }

    func start(_ task: TodoistTask) {
        pomodoro.workDuration = workMinutes * 60
        pomodoro.breakDuration = breakMinutes * 60
        pomodoro.start(task)
        showPanel()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickNow() }
        }
        if notifications { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    }

    func startBreak() {
        autoBreakTask?.cancel(); breakAt = nil
        pomodoro.startBreak()
    }

    func stop() {
        autoBreakTask?.cancel(); breakAt = nil
        ticker?.invalidate(); ticker = nil
        pomodoro.stop()
        panel?.close(); panel = nil
    }

    var secondsUntilBreak: Int? { breakAt.map { max(0, Int($0.timeIntervalSinceNow.rounded(.up))) } }

    private func tickNow() {
        tick &+= 1
        switch pomodoro.tick() {
        case .work: workFinished()
        case .rest:
            notify("Break over", "Back to work?")
            log("☕ \(Int(pomodoro.total / 60)) min break")
            stop()
        default: break
        }
    }

    private func workFinished() {
        let task = pomodoro.task
        let minutes = Int(pomodoro.total / 60)
        notify("Pomodoro done", task?.content ?? "")
        if sound { NSSound(named: "Glass")?.play() }
        log("🍅 \(minutes) min focus")
        guard autoBreak else { return }
        breakAt = Date().addingTimeInterval(10)
        autoBreakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.startBreak()
        }
    }

    /// Posts a comment on the current task when "Log a comment" is on.
    private func log(_ content: String) {
        guard logComment, let task = pomodoro.task else { return }
        Task { guard let client = await api() else { return }
               do { try await client.comment(taskId: task.id, content: content) }
               catch { self.error = error.localizedDescription } }
    }

    private func notify(_ title: String, _ body: String) {
        guard notifications else { return }
        let c = UNMutableNotificationContent()
        c.title = title; c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    private func showPanel() {
        if panel == nil { panel = FloatingPanel(model: self) }
        panel?.orderFrontRegardless()
    }
}
