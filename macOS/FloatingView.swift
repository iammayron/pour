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
            Menu("Work on") {
                if model.visibleTasks.isEmpty { Text("No tasks") }
                ForEach(model.visibleTasks) { task in
                    Button(task.content) { model.attach(task) }
                }
            }
            Button("Complete task") { Task { await model.complete() } }.disabled(p.task == nil)
            if p.phase == .rest { Button("Skip the break") { model.skipBreak() } }
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

    // MARK: The band

    /// Round dots, phase and today's total. The cycle leads on this card: what round you are in and
    /// how close the long break is stay on screen whether or not a task is attached.
    @ViewBuilder
    private func band(_ p: Pomodoro, padding: CGFloat) -> some View {
        HStack(spacing: 8) {
            RoundDots(done: model.roundsDone, of: model.roundsBeforeLongBreak,
                      current: p.phase == .work ? model.round : nil)
            caption(bandTitle(p))
            Spacer(minLength: 4)
            caption(bandTrailing(p)).foregroundStyle(.secondary.opacity(0.7))
        }
        .padding(.horizontal, padding)
        .frame(height: 24)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }

    private func bandTitle(_ p: Pomodoro) -> String {
        switch p.phase {
        case .rest:     p.isLongBreak ? "Long break" : "Short break"
        case .workDone: "Round \(model.round) done · \(Int(p.total / 60)) min"
        default:        p.isPaused ? "Paused · round \(model.round)" : "Round \(model.round) of \(model.roundsBeforeLongBreak)"
        }
    }

    private func bandTrailing(_ p: Pomodoro) -> String {
        switch p.phase {
        case .rest: p.isLongBreak ? "Set complete" : "Long break after round \(model.roundsBeforeLongBreak)"
        default:    "\(hoursMinutes(model.focusedToday)) today"
        }
    }

    /// The task line, demoted to a caption so it can change or empty without the card looking broken.
    @ViewBuilder
    private func taskLine(_ p: Pomodoro, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if p.phase == .rest {
                Text("Next up").font(.system(size: size, weight: .medium))
                Text("Round \(min(model.roundsBeforeLongBreak, model.roundsDone + 1)) · \(Int(model.workMinutes)) min")
                    .font(.system(size: size - 1)).foregroundStyle(.secondary)
            } else if let task = p.task {
                TaskName(task.content, subtitle: model.meta(task), priority: task.priority,
                         size: size, weight: .medium, lines: 1, task: task)
                Text(model.meta(task)).font(.system(size: size - 1)).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("No task attached").font(.system(size: size, weight: .medium)).foregroundStyle(.secondary)
                Text(lastWorked).font(.system(size: size - 1)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Keeps the minutes already banked visible when the slot empties, so they do not feel lost.
    private var lastWorked: String {
        guard let s = model.lastSegment, s.seconds >= 60 else { return "Pick one to keep the round" }
        return "\(s.content) · \(Int(s.seconds / 60)) m"
    }

    /// The card cannot open the menu bar popover — MenuBarExtra has no programmatic API — so the
    /// empty slot is filled from a menu on the card itself.
    /// ponytail: a menu, not a searchable list. Swap in a popover if the list grows past a screenful.
    @ViewBuilder
    private func pickTaskMenu(size: CGFloat) -> some View {
        Menu {
            if model.visibleTasks.isEmpty { Text("No tasks") }
            ForEach(model.visibleTasks) { task in
                Button(task.content) { model.attach(task) }
            }
        } label: {
            RoundFace(icon: "plus", size: size, dashed: true)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: size, height: size)
    }

    // MARK: Wide

    @ViewBuilder
    private func wideContent(_ p: Pomodoro) -> some View {
        VStack(spacing: 0) {
            band(p, padding: 14)
            if p.phase == .workDone {
                HStack(spacing: 10) {
                    RoundButton(icon: "checkmark", size: 36, filled: true, tint: .green) { Task { await model.complete() } }
                        .disabled(p.task == nil)
                    HStack(spacing: 6) {
                        Button(model.secondsUntilBreak.map { "Break in \($0) s" } ?? (model.nextBreakIsLong ? "Long break" : "Break")) {
                            model.startBreak()
                        }
                        .buttonStyle(Pill(prominent: true))
                        Button("+5 min") { p.extend(by: 300) }.buttonStyle(Pill())
                        Button("Stop") { model.stop() }.buttonStyle(Pill())
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
            } else {
                HStack(spacing: 10) {
                    RoundButton(icon: p.isPaused ? "play.fill" : "pause.fill", size: 32, filled: p.isPaused) { p.togglePause() }
                    // fixedSize: the clock never gives way to the task name, it is the thing you glance at.
                    Text(timeString(p.remaining))
                        .font(.system(size: 30, weight: .light, design: .rounded).monospacedDigit())
                        .fixedSize()
                        .opacity(p.isPaused ? 0.45 : 1)
                    taskLine(p, size: 10)
                    if p.phase == .rest {
                        RoundButton(icon: "forward.end.fill", size: 28) { model.skipBreak() }
                    } else if p.task == nil {
                        pickTaskMenu(size: 28)
                    } else {
                        RoundButton(icon: "checkmark", size: 28, tint: .green) { Task { await model.complete() } }
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)
            }
        }
    }

    // MARK: Compact

    /// No room for a band at 56 pt, so the dots ride directly above the clock — same reading order.
    @ViewBuilder
    private func compactContent(_ p: Pomodoro) -> some View {
        HStack(spacing: 10) {
            if p.phase == .workDone {
                RoundButton(icon: "checkmark", size: 32, filled: true, tint: .green) { Task { await model.complete() } }
                    .disabled(p.task == nil)
                VStack(alignment: .leading, spacing: 2) {
                    RoundDots(done: model.roundsDone, of: model.roundsBeforeLongBreak, current: nil)
                    Text("Round \(model.round) done · \(Int(p.total / 60)) min")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(model.secondsUntilBreak.map { "Break in \($0) s" } ?? (model.nextBreakIsLong ? "Long break" : "Break")) {
                    model.startBreak()
                }
                .buttonStyle(Pill(prominent: true))
                Button("Stop") { model.stop() }.buttonStyle(Pill())
            } else {
                RoundButton(icon: p.isPaused ? "play.fill" : "pause.fill", size: 28, filled: p.isPaused) { p.togglePause() }
                VStack(spacing: 3) {
                    RoundDots(done: model.roundsDone, of: model.roundsBeforeLongBreak,
                              current: p.phase == .work ? model.round : nil)
                    Text(timeString(p.remaining))
                        .font(.system(size: 22, weight: .light, design: .rounded).monospacedDigit())
                        .fixedSize()
                        .opacity(p.isPaused ? 0.45 : 1)
                }
                Divider().frame(height: 26)
                if p.phase == .rest {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.isLongBreak ? "Long break" : "Short break").font(.system(size: 11, weight: .semibold))
                        Text("Next: round \(min(model.roundsBeforeLongBreak, model.roundsDone + 1)) · \(Int(model.workMinutes)) min")
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    RoundButton(icon: "forward.end.fill", size: 28) { model.skipBreak() }
                } else {
                    taskLine(p, size: 11)
                    if p.task == nil {
                        pickTaskMenu(size: 28)
                    } else {
                        RoundButton(icon: "checkmark", size: 28, tint: .green) { Task { await model.complete() } }
                    }
                }
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
/// The popover body, shared by the card and the picker list so the two cannot drift apart.
struct TaskTip: View {
    let text: String
    var subtitle = ""
    var priority = 1

    var body: some View {
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

struct TaskName: View {
    let text: String
    var subtitle = ""
    var priority = 1
    var size: CGFloat = 11
    var weight: Font.Weight = .semibold
    var lines: Int = 1
    var task: TodoistTask?
    /// Off inside a List row: there the full-width contentShape and its tap gesture swallow the
    /// click that should select the row. The popover itself stays in both modes.
    var richTooltip = true
    @State private var showTip = false
    @State private var hoverTask: Task<Void, Never>?

    init(_ text: String, subtitle: String = "", priority: Int = 1, size: CGFloat = 11, weight: Font.Weight = .semibold,
         lines: Int = 1, task: TodoistTask? = nil, richTooltip: Bool = true) {
        self.text = text; self.subtitle = subtitle; self.priority = priority; self.size = size
        self.weight = weight; self.lines = lines; self.task = task; self.richTooltip = richTooltip
    }

    @ViewBuilder
    var body: some View {
        let label = Text(text)
            .font(.system(size: size, weight: weight))
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .leading)

        if richTooltip {
            label
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
                .background(TipPopover(isPresented: $showTip) {
                    TaskTip(text: text, subtitle: subtitle, priority: priority)
                })
        } else {
            // Popover only. Any SwiftUI tap gesture here eats the click that selects the row,
            // with or without a contentShape, so the List's double-click lives in DoubleClickCatcher.
            label
                .onHover { inside in
                    hoverTask?.cancel()
                    if inside {
                        hoverTask = Task { try? await Task.sleep(for: .milliseconds(500)); if !Task.isCancelled { showTip = true } }
                    } else {
                        showTip = false
                    }
                }
                .background(TipPopover(isPresented: $showTip) {
                    TaskTip(text: text, subtitle: subtitle, priority: priority)
                })
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
            RoundFace(icon: icon, size: size, filled: filled, tint: tint, hovering: hovering)
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

/// NSPopover presented directly, because SwiftUI's `.popover` is always transient, and a transient
/// popover swallows the next mouse-down to dismiss itself — the click that would select a row.
/// `.applicationDefined` never auto-closes; the hover handler owns show and hide.
struct TipPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> NSView { PassthroughView() }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(showing: isPresented, from: view, content: content())
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.close() }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Anchor only: the click belongs to whatever is underneath.
    final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    final class Coordinator {
        private var popover: NSPopover?

        func update<C: View>(showing: Bool, from anchor: NSView, content: C) {
            guard showing, anchor.window != nil else { return close() }
            let p = popover ?? make()
            p.contentViewController = NSHostingController(rootView: content)
            if !p.isShown { p.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY) }
        }

        func close() {
            popover?.performClose(nil)
            popover = nil
        }

        private func make() -> NSPopover {
            let p = NSPopover()
            p.behavior = .applicationDefined
            p.animates = false
            popover = p
            return p
        }

        deinit { popover?.performClose(nil) }
    }
}

/// The circle chrome, shared by RoundButton and the pick-a-task menu so the two cannot drift apart.
struct RoundFace: View {
    let icon: String
    var size: CGFloat = 32
    var filled = false
    var tint: Color = .accentColor
    var hovering = false
    /// Dashed and unfilled: an empty slot waiting to be filled, not an action on something.
    var dashed = false

    var body: some View {
        let line: Color = filled ? .clear : hovering ? tint.opacity(0.5) : .primary.opacity(dashed ? 0.34 : 0.18)
        Image(systemName: icon)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(filled ? Color.white : hovering ? tint : dashed ? Color.secondary : Color.primary)
            .frame(width: size, height: size)
            .background(filled ? AnyShapeStyle(tint.opacity(hovering ? 0.85 : 1))
                        : hovering ? AnyShapeStyle(tint.opacity(0.35))
                        : dashed ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.primary.opacity(0.14)), in: Circle())
            .overlay(Circle().strokeBorder(line, style: StrokeStyle(lineWidth: 1, dash: dashed ? [3, 2] : [])))
    }
}

/// One dot per round in the set: filled for done, accented for the one running.
struct RoundDots: View {
    let done: Int
    let of: Int
    var current: Int?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(1, of), id: \.self) { i in
                Circle()
                    .fill(i <= done ? AnyShapeStyle(.primary.opacity(0.8))
                          : i == current ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary.opacity(0.26)))
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Round \(current ?? done) of \(of)")
    }
}
