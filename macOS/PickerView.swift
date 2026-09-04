import SwiftUI
import TodoistCore

struct PickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
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
                        TaskName(task.content, subtitle: model.meta(task), priority: task.priority, size: 13, weight: .regular, task: task)
                        if !model.meta(task).isEmpty {
                            Text(model.meta(task)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if let due = task.due {
                        let late = model.isOverdue(task)
                        Text(due.label).font(.caption)
                            .foregroundStyle(late ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                            .fontWeight(late ? .semibold : .regular)
                    }
                }
                .tag(task.id)
            }
            .listStyle(.plain)
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
                Button { model.startSelected() } label: {
                    Label("Start \(Int(model.workMinutes)) min", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedTask == nil || model.pomodoro.isRunning)
            }

            Divider()

            HStack {
                Button { // menu bar apps are not active, so the window would open grayed out
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: { Image(systemName: "gearshape") }
                Button("Open task", systemImage: "arrow.up.forward.app") { openTodoist(model.selectedTask) }
                    .help(model.selectedTask == nil ? "Open Todoist" : "Open the selected task in Todoist")
                Spacer()
                Button("Quit", role: .destructive) { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(12)
        .frame(width: 400)
        .task { await model.loadTasks() }
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
            Text(p.phase == .rest ? "Running · Break" : p.phase == .workDone ? "Done" : "Running · Focus")
                .font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(timeString(p.remaining)).font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                TaskName(p.task?.content ?? "", subtitle: model.meta(p.task), priority: p.task?.priority ?? 1, size: 13, task: p.task)
            }
            ProgressView(value: p.level)
            HStack(spacing: 6) {
                Button(p.isPaused ? "Resume" : "Pause", systemImage: p.isPaused ? "play.fill" : "pause.fill") { p.togglePause() }
                    .disabled(p.phase == .workDone)
                Button("5 min", systemImage: "plus") { p.extend(by: 300) }
                Button("Complete", systemImage: "checkmark") { Task { await model.complete() } }.buttonStyle(.borderedProminent)
                Button("Stop", systemImage: "stop.fill") { model.stop() }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
