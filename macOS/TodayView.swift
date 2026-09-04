import SwiftUI
import TodoistCore

/// The session log, rendered. Reading it is also how the app decides whether the next break is a
/// short or a long one, so this view and that decision can never disagree.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    let back: () -> Void
    @State private var sessions: [Session] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { back() } label: { Image(systemName: "chevron.left") }
                Text("Today").font(.title3.weight(.semibold))
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.caption).foregroundStyle(.secondary)
            }

            summary

            if sessions.isEmpty {
                Text("Nothing recorded yet today.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sessions) { row($0) }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            HStack {
                Text("sessions.json · Application Support").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Button("Back to tasks") { back() }
            }
        }
        .task { sessions = SessionLog.today() }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hoursMinutes(focused))
                    .font(.system(size: 24, weight: .light, design: .rounded).monospacedDigit())
                Text("Focused").font(.caption2).textCase(.uppercase).foregroundStyle(.secondary)
            }
            Divider().frame(height: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    RoundDots(done: model.roundsDone, of: model.roundsBeforeLongBreak, current: nil)
                    Text(rounds == 1 ? "1 round" : "\(rounds) rounds").font(.caption)
                }
                Text(breakdown).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func row(_ s: Session) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(clock(s.start)) – \(clock(s.end ?? s.start))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .frame(width: 88, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(color(s.kind)).frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(name(s.kind)) · \(Int(s.seconds / 60)) min")
                    .font(.caption.weight(.semibold))
                ForEach(Array(s.segments.enumerated()), id: \.offset) { _, segment in
                    line(segment.content, seconds: segment.seconds)
                }
                // The minutes a round ran with an empty slot. Shown rather than quietly dropped:
                // it is the honest cost of letting the session outlive the task.
                if s.kind == .focus, s.untracked >= 60 {
                    line("Untracked", seconds: s.untracked).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func line(_ text: String, seconds: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Text(text).font(.caption).lineLimit(1)
            Spacer(minLength: 0)
            Text("\(Int(seconds / 60)) m").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var focused: TimeInterval { sessions.filter { $0.kind == .focus }.reduce(0) { $0 + $1.seconds } }
    private var rounds: Int { sessions.filter { $0.kind == .focus }.count }

    private var breakdown: String {
        let short = sessions.filter { $0.kind == .shortBreak }.count
        let long = sessions.filter { $0.kind == .longBreak }.count
        let tasks = Set(sessions.flatMap { $0.segments.map(\.taskId) }).count
        return "\(short) short · \(long) long break\(long == 1 ? "" : "s") · \(tasks) task\(tasks == 1 ? "" : "s")"
    }

    private func clock(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }
    private func name(_ k: Session.Kind) -> String {
        switch k { case .focus: "Focus"; case .shortBreak: "Short break"; case .longBreak: "Long break" }
    }
    private func color(_ k: Session.Kind) -> Color {
        switch k { case .focus: .accentColor; case .shortBreak: .green.opacity(0.7); case .longBreak: .green }
    }
}
