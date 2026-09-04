import SwiftUI
import TodoistCore

struct PickerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 10) {
            if model.pomodoro.isRunning { RunningPanel() ; Divider() }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $model.search).textFieldStyle(.plain)
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Picker("Filter", selection: $model.filter) {
                    Text("Today").tag("today")
                    Text("Overdue").tag("overdue")
                    Text("7 days").tag("7 days")
                }
                .pickerStyle(.segmented).labelsHidden()
                .onChange(of: model.filter) { Task { await model.loadTasks() } }
                Spacer()
                Button("Refresh list") { Task { await model.loadTasks() } }
                    .controlSize(.small).disabled(model.loading)
            }

            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
            }

            List(model.visibleTasks, selection: $model.selectedTaskId) { task in
                HStack {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                    Text(task.content).lineLimit(1)
                    Spacer()
                    if let due = task.due { Text(due.string).font(.caption).foregroundStyle(.secondary) }
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
                    Text(model.selectedTask?.content ?? "Pick a task").lineLimit(1)
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
                SettingsLink { Image(systemName: "gearshape") }
                Spacer()
                Button("Quit", role: .destructive) { NSApp.terminate(nil) }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(12)
        .frame(width: 340)
        .task { await model.loadTasks() }
    }
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
                Text(p.task?.content ?? "").fontWeight(.semibold).lineLimit(1)
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
