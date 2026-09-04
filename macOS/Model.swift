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
    var longBreakMinutes: Double { didSet { guard longBreakMinutes != oldValue else { return }; save(longBreakMinutes, "longBreakMinutes") } }
    var roundsBeforeLongBreak: Int { didSet { guard roundsBeforeLongBreak != oldValue else { return }; save(roundsBeforeLongBreak, "roundsBeforeLongBreak"); refreshCounters() } }
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

    /// The session being recorded right now. Independent of `pomodoro.task` by design.
    private var live: Session?
    /// Focus rounds since the last long break, and today's focus time. Derived from the log, cached
    /// because the card reads them every second and the log only changes when a session ends.
    private(set) var roundsDone = 0
    private(set) var focusedTodayLogged: TimeInterval = 0

    private static let json = (
        encoder: { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }(),
        decoder: { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    )
    /// What is written to defaults on every tick so a session survives quitting the app.
    private struct LiveState: Codable { var pomodoro: Pomodoro.Snapshot; var session: Session }

    init() {
        d.register(defaults: ["filter": "today", "workMinutes": 25.0, "breakMinutes": 5.0, "longBreakMinutes": 15.0,
                              "roundsBeforeLongBreak": 4, "autoBreak": true,
                              "sound": true, "notifications": true, "logComment": true, "compactCard": false, "allSpaces": true])
        filter = d.string(forKey: "filter")!
        workMinutes = d.double(forKey: "workMinutes"); breakMinutes = d.double(forKey: "breakMinutes")
        longBreakMinutes = d.double(forKey: "longBreakMinutes"); roundsBeforeLongBreak = d.integer(forKey: "roundsBeforeLongBreak")
        autoBreak = d.bool(forKey: "autoBreak"); sound = d.bool(forKey: "sound"); notifications = d.bool(forKey: "notifications")
        logComment = d.bool(forKey: "logComment"); compactCard = d.bool(forKey: "compactCard"); allSpaces = d.bool(forKey: "allSpaces")
        pomodoro = Pomodoro(workMinutes: d.double(forKey: "workMinutes"), breakMinutes: d.double(forKey: "breakMinutes"),
                            longBreakMinutes: d.double(forKey: "longBreakMinutes"))
        auth = TokenStore.auth                                    // didSet does not fire from init
        client = auth.map { TodoistClient(token: $0.accessToken) }
        refreshCounters()
        restoreLive()
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
            await dropTaskIfFinishedElsewhere(client)
        } catch { self.error = error.localizedDescription }
    }

    /// A task completed in Todoist should leave the slot, not end the session — the clock is the
    /// session's, not the task's. The list is the whole universe of startable tasks, so a running
    /// task missing from a fresh fetch is either done or rescheduled out of the window; one probe
    /// tells those apart.
    private func dropTaskIfFinishedElsewhere(_ client: TodoistClient) async {
        guard let running = pomodoro.task, !tasks.contains(where: { $0.id == running.id }) else { return }
        guard (try? await client.isClosed(taskId: running.id)) == true else { return }
        attach(nil)
    }

    /// Closes the task in Todoist and empties the slot. The session keeps running: finishing a task
    /// with time left on the clock is the point.
    func complete() async {
        guard let task = pomodoro.task, let client = await api() else { return }
        do { try await client.close(taskId: task.id); tasks.removeAll { $0.id == task.id }; attach(nil) }
        catch { self.error = error.localizedDescription }
    }

    // MARK: - Session

    func startSelected() { start(selectedTask) }

    /// Begins a focus session. The task is optional and can change at any point after this.
    func start(_ task: TodoistTask? = nil) {
        pomodoro.workDuration = workMinutes * 60
        pomodoro.breakDuration = breakMinutes * 60
        pomodoro.longBreakDuration = longBreakMinutes * 60
        pomodoro.task = nil
        live = Session(kind: .focus, start: Date(), planned: workMinutes * 60)
        pomodoro.start()
        attach(task)                       // opens the first segment, if there is a task
        showPanel(); startTicker()
        if notifications { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
    }

    /// Points the running session at a task, or at nothing. Never touches the clock — this is the
    /// whole reason a session outlives the task it started on.
    func attach(_ task: TodoistTask?) {
        let now = Date()
        closeSegment(at: now)
        pomodoro.task = task
        if let task, live?.kind == .focus {
            live?.segments.append(Session.Segment(taskId: task.id, content: task.content, start: now))
        }
        saveLive()
    }

    func startBreak() {
        autoBreakTask?.cancel(); breakAt = nil
        let long = roundsDone >= roundsBeforeLongBreak
        live = Session(kind: long ? .longBreak : .shortBreak, start: Date(),
                       planned: (long ? longBreakMinutes : breakMinutes) * 60)
        pomodoro.startBreak(long: long)
        saveLive()
    }

    func stop() {
        autoBreakTask?.cancel(); breakAt = nil
        ticker?.invalidate(); ticker = nil
        finishLive()
        pomodoro.stop()
        d.removeObject(forKey: "live")
        panel?.close(); panel = nil
    }

    /// Ends the break early and opens the next round, without closing the card.
    func skipBreak() {
        finishLive()
        pomodoro.stop()
        start()
    }

    var secondsUntilBreak: Int? { breakAt.map { max(0, Int($0.timeIntervalSinceNow.rounded(.up))) } }
    /// The last task the running session worked on, for the card's empty-slot line.
    var lastSegment: Session.Segment? { live?.segments.last }
    var nextBreakIsLong: Bool { roundsDone >= roundsBeforeLongBreak }
    /// 1-based round the card names: the one running, or the one just finished.
    var round: Int { pomodoro.phase == .work ? min(roundsBeforeLongBreak, roundsDone + 1) : max(1, roundsDone) }
    /// Today's focus time, the running session included so the card ticks.
    var focusedToday: TimeInterval {
        focusedTodayLogged + (pomodoro.phase == .work ? (live?.seconds ?? 0) : 0)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickNow() }
        }
    }

    private func tickNow() {
        tick &+= 1
        switch pomodoro.tick() {
        case .work: workFinished()
        case .rest:
            notify("Break over", "Back to work?")
            stop()                         // finishLive writes the break to the log
        default: saveLive()
        }
    }

    private func workFinished() {
        let task = pomodoro.task
        finishLive()                       // logs the round before the break decision reads the log
        notify("Pomodoro done", task?.content ?? "")
        if sound { NSSound(named: "Glass")?.play() }
        guard autoBreak else { saveLive(); return }
        breakAt = Date().addingTimeInterval(10)
        autoBreakTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            self?.startBreak()
        }
    }

    // MARK: - Recording

    private func closeSegment(at date: Date = Date()) {
        guard var session = live, var last = session.segments.last, last.end == nil else { return }
        last.end = date
        session.segments[session.segments.count - 1] = last
        live = session
    }

    /// Closes the in-flight session, writes it to the log and refreshes the derived counters.
    private func finishLive(at date: Date = Date()) {
        closeSegment(at: date)
        guard var session = live else { return }
        live = nil
        session.end = date
        if pomodoro.total > 0 { session.planned = pomodoro.total }   // "+5 min" belongs in the record
        SessionLog.append(session)
        refreshCounters()
        if session.kind == .focus { logSegments(session) }
    }

    private func refreshCounters() {
        let log = SessionLog.all()
        roundsDone = SessionLog.roundsSinceLongBreak(log)
        focusedTodayLogged = SessionLog.today(log).filter { $0.kind == .focus }.reduce(0) { $0 + $1.seconds }
    }

    /// One comment per task the round touched, each with its own minutes. Segments under a minute are
    /// a mis-click, not work, and would only litter the task with "0 min focus".
    private func logSegments(_ session: Session) {
        guard logComment else { return }
        for segment in session.segments where segment.seconds >= 60 {
            let body = "🍅 \(Int(segment.seconds / 60)) min focus"
            Task { guard let client = await api() else { return }
                   do { try await client.comment(taskId: segment.taskId, content: body) }
                   catch { self.error = error.localizedDescription } }
        }
    }

    // MARK: - Surviving a quit

    private func saveLive() {
        guard let live, pomodoro.isRunning else { d.removeObject(forKey: "live"); return }
        d.set(try? Self.json.encoder.encode(LiveState(pomodoro: pomodoro.snapshot, session: live)), forKey: "live")
    }

    private func restoreLive() {
        guard let data = d.data(forKey: "live"),
              let state = try? Self.json.decoder.decode(LiveState.self, from: data) else { return }
        live = state.session
        pomodoro.restore(state.pomodoro)
        // Ran out while Pour was closed: settle the record at the time it actually ended, rather
        // than resuming a clock that is already dead.
        if let end = state.pomodoro.endDate, end <= Date() {
            finishLive(at: end)
            pomodoro.stop()
            d.removeObject(forKey: "live")
            return
        }
        showPanel(); startTicker()
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
