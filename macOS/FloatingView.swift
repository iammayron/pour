import SwiftUI
import TodoistCore

struct FloatingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.pomodoro
        let _ = model.tick
        let water: Color = p.phase == .rest ? .green : .blue
        let compact = model.compactCard
        ZStack {
            TimelineView(.animation(paused: p.isPaused || p.phase == .workDone)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                ZStack {   // two sibling shapes without a ZStack get stacked vertically
                    WaveShape(level: p.level, phase: t * 0.6, amplitude: 6, wavelength: 140).fill(water.opacity(0.35))
                    WaveShape(level: p.level, phase: t * 0.9 + 2, amplitude: 4, wavelength: 90).fill(water.opacity(0.55))
                }
            }
            if compact { compactContent(p) } else { wideContent(p) }
        }
        .frame(width: Self.size(compact: compact).width, height: Self.size(compact: compact).height)
        .glassCard(cornerRadius: compact ? 28 : 16)
        .contentShape(Rectangle())   // right-click anywhere, not only on text and water
        .contextMenu {
            Button("+5 minutes") { p.extend(by: 300) }
            Button("Complete task") { Task { await model.complete() } }
            Button("Open in Todoist") { openTodoist(p.task) }
            Picker("Card size", selection: Bindable(model).compactCard) {
                Text("Wide").tag(false)
                Text("Compact").tag(true)
            }
            Divider()
            Button("Stop") { model.stop() }
        }
    }

    static func size(compact: Bool) -> CGSize { compact ? CGSize(width: 340, height: 56) : CGSize(width: 300, height: 100) }

    // MARK: Wide (Layout 2)

    @ViewBuilder
    private func wideContent(_ p: Pomodoro) -> some View {
        HStack(spacing: 12) {
            if p.phase == .workDone {
                RoundButton(icon: "checkmark", size: 36, filled: true, tint: .green) { Task { await model.complete() } }
                VStack(alignment: .leading, spacing: 6) {
                    caption("Done · \(Int(p.total / 60)) min")
                    TaskName(p.task?.content ?? "", subtitle: model.meta(p.task), priority: p.task?.priority ?? 1, size: 11, lines: 1, task: p.task)
                    HStack(spacing: 6) {
                        Button(model.secondsUntilBreak.map { "Break in \($0) s" } ?? "Break") { model.startBreak() }
                            .buttonStyle(Pill(prominent: true))
                        Button("+5 min") { p.extend(by: 300) }.buttonStyle(Pill())
                        Button("Stop") { model.stop() }.buttonStyle(Pill())
                    }
                }
                Spacer(minLength: 0)
            } else {
                RoundButton(icon: p.isPaused ? "play.fill" : "pause.fill", size: 32, filled: p.isPaused) { p.togglePause() }
                Text(timeString(p.remaining))
                    .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                    .opacity(p.isPaused ? 0.45 : 1)
                Divider().frame(height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    caption(p.phase == .rest ? "Break" : p.isPaused ? "Paused" : "Focus")
                    TaskName(p.task?.content ?? "", subtitle: model.meta(p.task), priority: p.task?.priority ?? 1, size: 11, lines: model.meta(p.task).isEmpty ? 2 : 1, task: p.task)
                    if !model.meta(p.task).isEmpty {
                        Text(model.meta(p.task)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundButton(icon: "checkmark", size: 28, tint: .green) { Task { await model.complete() } }
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: Compact (Layout 3)

    @ViewBuilder
    private func compactContent(_ p: Pomodoro) -> some View {
        HStack(spacing: 10) {
            if p.phase == .workDone {
                RoundButton(icon: "checkmark", size: 32, filled: true, tint: .green) { Task { await model.complete() } }
                Text("Done").font(.system(size: 12, weight: .medium))
                Spacer(minLength: 0)
                Button(model.secondsUntilBreak.map { "Break in \($0) s" } ?? "Break") { model.startBreak() }
                    .buttonStyle(Pill(prominent: true))
                Button("Stop") { model.stop() }.buttonStyle(Pill())
            } else {
                RoundButton(icon: p.isPaused ? "play.fill" : "pause.fill", size: 28, filled: p.isPaused) { p.togglePause() }
                TaskName(p.task?.content ?? "", subtitle: model.meta(p.task), priority: p.task?.priority ?? 1, size: 12, weight: .medium, lines: 1, task: p.task)
                Spacer(minLength: 0)
                Text(timeString(p.remaining))
                    .font(.system(size: 22, weight: .light, design: .rounded).monospacedDigit())
                    .opacity(p.isPaused ? 0.45 : 1)
                RoundButton(icon: "checkmark", size: 28, tint: .green) { Task { await model.complete() } }
            }
        }
        .padding(.horizontal, 12)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.system(size: 9, weight: .medium)).textCase(.uppercase).tracking(0.6).foregroundStyle(.secondary)
    }
}

extension View {
    /// Liquid Glass on macOS 26+, translucent material before that.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        // The system glass rim fades when the panel is not key; draw our own so the edge is always there.
        let rim = shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12)],
                                                    startPoint: .top, endPoint: .bottom), lineWidth: 0.5)
        if #available(macOS 26, *) {
            self.clipShape(shape).glassEffect(.regular.interactive(), in: shape).overlay(rim)
        } else {
            self.background(.ultraThinMaterial, in: shape).clipShape(shape).overlay(rim)
        }
    }
}

/// Task name that shows its full text in a popover above (arrow down) after hovering for half a second.
/// Hover tracks the whole label box, not the glyphs. Double-click opens the task in Todoist.
struct TaskName: View {
    let text: String
    var subtitle = ""
    var priority = 1
    var size: CGFloat = 11
    var weight: Font.Weight = .semibold
    var lines: Int = 1
    var task: TodoistTask?
    @State private var showTip = false
    @State private var hoverTask: Task<Void, Never>?

    init(_ text: String, subtitle: String = "", priority: Int = 1, size: CGFloat = 11, weight: Font.Weight = .semibold, lines: Int = 1, task: TodoistTask? = nil) {
        self.text = text; self.subtitle = subtitle; self.priority = priority; self.size = size; self.weight = weight; self.lines = lines; self.task = task
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight))
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard let task else { return }
                showTip = false
                openTodoist(task)
            })
            .help(task == nil ? "" : "Double-click to open in Todoist")
            .onHover { inside in
                hoverTask?.cancel()
                if inside {
                    hoverTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { showTip = true } }
                } else {
                    showTip = false
                }
            }
            .popover(isPresented: $showTip, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text).font(.callout)
                    HStack(spacing: 6) {
                        if let c = priorityColor(priority) {
                            Image(systemName: "flag.fill").foregroundStyle(c)
                        }
                        if !subtitle.isEmpty { Text(subtitle).foregroundStyle(.secondary) }
                    }
                    .font(.caption)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(10)
            }
    }
}

/// Capsule button that stays readable on top of the water. Prominent = solid white, others translucent white.
struct Pill: ButtonStyle {
    var prominent = false
    func makeBody(configuration c: Configuration) -> some View {
        c.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.primary)
            .background(Color.white.opacity(prominent ? 0.92 : 0.35), in: Capsule())
            .opacity(c.isPressed ? 0.7 : 1)
    }
}

struct RoundButton: View {
    let icon: String
    var size: CGFloat = 32
    var filled = false
    var tint: Color = .accentColor
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(filled ? Color.white : hovering ? tint : Color.primary)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(tint.opacity(hovering ? 0.85 : 1))
                            : hovering ? AnyShapeStyle(tint.opacity(0.35)) : AnyShapeStyle(.primary.opacity(0.14)), in: Circle())
                .overlay(Circle().strokeBorder(filled ? Color.clear : hovering ? tint.opacity(0.5) : Color.primary.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PressScale())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Plain button that shrinks slightly while pressed.
struct PressScale: ButtonStyle {
    func makeBody(configuration c: Configuration) -> some View {
        c.label.scaleEffect(c.isPressed ? 0.92 : 1).animation(.easeOut(duration: 0.1), value: c.isPressed)
    }
}
