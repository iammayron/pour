import AppKit
import SwiftUI
import TodoistCore

struct PickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    @State private var showingToday = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            if showingToday {
                TodayView(back: { showingToday = false })
            } else {
                tasks
            }
        }
        .padding(12)
        .frame(width: 400)
        .task { await model.loadTasks() }
        // MenuBarExtra(.window) keeps this view alive between opens, so `.task` fires once.
        // The panel becomes key every time it opens: refresh there so the list is not a stale snapshot.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await model.loadTasks(ifOlderThan: 5) }
        }
    }

    @ViewBuilder
    private var tasks: some View {
        @Bindable var model = model
        Group {
            if model.pomodoro.isRunning { RunningPanel() ; Divider() }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.search).textFieldStyle(.plain)
                Button { Task { await model.loadTasks() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(model.loading).help("Refresh list")
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            // The segmented control has no compressed layout: four labels with counts need ~340pt,
            // so it gets its own row at .small and the popover is wide enough for 3-digit counts.
            Picker("Filter", selection: $model.filter) {
                ForEach(TodoistTask.filters, id: \.self) { f in
                    Text("\(f.capitalized) (\(model.count(f)))").tag(f)
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)

            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }

            List(model.visibleTasks, selection: $model.selectedTaskId) { task in
                HStack(alignment: .firstTextBaseline) {
                    // Todoist: 4 = P1 … 1 = none. The slot stays so names line up across rows.
                    Image(systemName: "flag.fill").font(.system(size: 11))
                        .foregroundStyle(priorityColor(task.priority) ?? .clear)
                    VStack(alignment: .leading, spacing: 2) {
                        TaskName(task.content, subtitle: model.meta(task), priority: task.priority, size: 13, weight: .regular, task: task, richTooltip: false)
                        if !model.meta(task).isEmpty {
                            Text(model.meta(task)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if task.id == model.pomodoro.task?.id {
                        Label("In session", systemImage: "circle.fill")
                            .font(.caption2.weight(.semibold)).imageScale(.small)
                            .foregroundStyle(.tint)
                    } else if let due = task.due {
                        let late = model.isOverdue(task)
                        Text(due.label).font(.caption)
                            .foregroundStyle(late ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .fontWeight(late ? .semibold : .regular)
                    }
                }
                .tag(task.id)
            }
            .listStyle(.plain)
            .background(DoubleClickCatcher { openTodoist(model.selectedTask) })
            .frame(minHeight: 180)
            .overlay {
                if model.visibleTasks.isEmpty && !model.loading {
                    Text("No tasks").foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Selected").font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
                    TaskName(model.selectedTask?.content ?? "Pick a task", subtitle: model.meta(model.selectedTask), priority: model.selectedTask?.priority ?? 1, size: 13, weight: .regular, task: model.selectedTask)
                        .foregroundStyle(model.selectedTask == nil ? .secondary : .primary)
                }
                Spacer()
                // Mid-session this points the running clock at another task; idle it opens a new
                // session, with or without a task selected.
                if model.pomodoro.isRunning {
                    Button { model.attach(model.selectedTask) } label: {
                        Label("Work on this", systemImage: "arrow.left.arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedTask == nil || model.selectedTask?.id == model.pomodoro.task?.id)
                } else {
                    Button { model.startSelected() } label: {
                        Label("Start \(Int(model.workMinutes)) min", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Divider()

            HStack {
                Button { // menu bar apps are not active, so the window would open grayed out
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                Button("Open task", systemImage: "arrow.up.forward.app") { openTodoist(model.selectedTask) }
                    .help(model.selectedTask == nil ? "Open Todoist" : "Open the selected task in Todoist")
                Button { showingToday = true } label: {
                    HStack(spacing: 5) {
                        RoundDots(done: model.roundsDone, of: model.roundsBeforeLongBreak, current: nil)
                        Text("Today")
                    }
                }
                .help("Every session you have run today")
                Spacer()
                Button("Quit", role: .destructive) { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }
}

func priorityColor(_ p: Int) -> Color? {
    switch p { case 4: .red; case 3: .orange; case 2: .blue; default: nil }
}

struct RunningPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.pomodoro
        let _ = model.tick
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title(p)).font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
                RoundDots(done: model.roundsDone, of: model.roundsBeforeLongBreak,
                          current: p.phase == .work ? model.round : nil)
                Spacer()
                Text(p.phase == .rest ? (p.isLongBreak ? "Set complete" : "Long break after round \(model.roundsBeforeLongBreak)")
                                      : "\(hoursMinutes(model.focusedToday)) today")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeString(p.remaining)).font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                VStack(alignment: .leading, spacing: 1) {
                    if let task = p.task {
                        TaskName(task.content, subtitle: model.meta(task), priority: task.priority, size: 13, task: task)
                        if let s = model.lastSegment, s.seconds >= 60 {
                            Text("\(Int(s.seconds / 60)) min on this task").font(.caption2).foregroundStyle(.secondary)
                        }
                    } else {
                        Text(p.phase == .rest ? "Breaks carry no task" : "No task attached — pick one below")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
            }
            ProgressView(value: p.level)
            HStack(spacing: 6) {
                Button(p.isPaused ? "Resume" : "Pause", systemImage: p.isPaused ? "play.fill" : "pause.fill") { p.togglePause() }
                    .disabled(p.phase == .workDone)
                Button("5 min", systemImage: "plus") { p.extend(by: 300) }
                Button("Complete", systemImage: "checkmark") { Task { await model.complete() } }
                    .buttonStyle(.borderedProminent).disabled(p.task == nil)
                if p.phase == .rest { Button("Skip", systemImage: "forward.end.fill") { model.skipBreak() } }
                Button("Stop", systemImage: "stop.fill") { model.stop() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func title(_ p: Pomodoro) -> String {
        switch p.phase {
        case .rest:     p.isLongBreak ? "Long break" : "Short break"
        case .workDone: "Round \(model.round) done"
        default:        "Round \(model.round) of \(model.roundsBeforeLongBreak)"
        }
    }
}

/// Double-click on a List row, without breaking single-click selection.
///
/// Every SwiftUI tap gesture tried on a row consumed the mouse-down that selects it, gesture on the
/// label or on the List alike. This watches the same events and always hands them back, so AppKit
/// still delivers the click to the List.
/// ponytail: an AppKit escape hatch; delete it if SwiftUI ever ships a row double-click action.
struct DoubleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView { CatchView() }

    func updateNSView(_ view: NSView, context: Context) { (view as? CatchView)?.action = action }

    final class CatchView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        /// Never a hit target: the click belongs to the row underneath.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window === self.window, event.clickCount == 2,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action?()
                return event   // handing the event back is the whole point
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { removeMonitor() }
    }
}
