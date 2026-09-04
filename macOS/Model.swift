import AppKit
import Observation
import TodoistCore
import UserNotifications

@Observable @MainActor
final class AppModel {
    let pomodoro: Pomodoro
    var tasks: [TodoistTask] = []
    var selectedTaskId: String?
    var search = ""
    var error: String?
    var loading = false
    /// Increments every second while a session runs, so views re-read time-derived values.
    private(set) var tick = 0
    /// When the automatic break will start after a finished focus session.
    private(set) var breakAt: Date?

    // MARK: - Settings (UserDefaults-backed)

    var token: String {
        didSet { Keychain.token = token; client = token.isEmpty ? nil : TodoistClient(token: token) }
    }
    var filter: String       { didSet { d.set(filter, forKey: "filter") } }
    var workMinutes: Double  { didSet { d.set(workMinutes, forKey: "workMinutes") } }
    var breakMinutes: Double { didSet { d.set(breakMinutes, forKey: "breakMinutes") } }
    var autoBreak: Bool      { didSet { d.set(autoBreak, forKey: "autoBreak") } }
    var sound: Bool          { didSet { d.set(sound, forKey: "sound") } }
    var notifications: Bool  { didSet { d.set(notifications, forKey: "notifications") } }
    var logComment: Bool     { didSet { d.set(logComment, forKey: "logComment") } }
    var compactCard: Bool    { didSet { d.set(compactCard, forKey: "compactCard") } }
    var allSpaces: Bool      { didSet { d.set(allSpaces, forKey: "allSpaces"); panel?.applySpaces(allSpaces) } }

    private let d = UserDefaults.standard
    private var client: TodoistClient?
    private var panel: FloatingPanel?
    private var ticker: Timer?
    private var autoBreakTask: Task<Void, Never>?

    init() {
        d.register(defaults: ["filter": "today", "workMinutes": 25.0, "breakMinutes": 5.0, "autoBreak": true,
                              "sound": true, "notifications": true, "logComment": true, "compactCard": false, "allSpaces": true])
        filter = d.string(forKey: "filter")!
        workMinutes = d.double(forKey: "workMinutes"); breakMinutes = d.double(forKey: "breakMinutes")
        autoBreak = d.bool(forKey: "autoBreak"); sound = d.bool(forKey: "sound"); notifications = d.bool(forKey: "notifications")
        logComment = d.bool(forKey: "logComment"); compactCard = d.bool(forKey: "compactCard"); allSpaces = d.bool(forKey: "allSpaces")
        pomodoro = Pomodoro(workMinutes: d.double(forKey: "workMinutes"), breakMinutes: d.double(forKey: "breakMinutes"))
        // TF_DEMO skips the Keychain so a scripted launch is not blocked by the access prompt.
        token = ProcessInfo.processInfo.environment["TF_DEMO"] == nil ? (Keychain.token ?? "") : ""
        client = token.isEmpty ? nil : TodoistClient(token: token)
    }

    var visibleTasks: [TodoistTask] {
        search.isEmpty ? tasks : tasks.filter { $0.content.localizedCaseInsensitiveContains(search) }
    }
    var selectedTask: TodoistTask? { tasks.first { $0.id == selectedTaskId } }

    // MARK: - Todoist

    func loadTasks() async {
        guard let client else { error = "Add your Todoist API token in Settings."; return }
        loading = true; defer { loading = false }
        do { tasks = try await client.tasks(filter: filter); error = nil }
        catch { self.error = error.localizedDescription }
    }

    func complete() async {
        guard let client, let task = pomodoro.task else { return }
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
        case .rest: notify("Break over", "Back to work?"); stop()
        default: break
        }
    }

    private func workFinished() {
        let task = pomodoro.task
        let minutes = Int(pomodoro.total / 60)
        notify("Pomodoro done", task?.content ?? "")
        if sound { NSSound(named: "Glass")?.play() }
        if logComment, let client, let task {
            Task { do { try await client.comment(taskId: task.id, content: "🍅 \(minutes) min focus") }
                   catch { self.error = error.localizedDescription } }
        }
        guard autoBreak else { return }
        breakAt = Date().addingTimeInterval(10)
        autoBreakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.startBreak()
        }
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
