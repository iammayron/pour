import SwiftUI
import TodoistCore

struct FloatingView: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let p = model.pomodoro
        let _ = model.tick
        let water: Color = p.phase == .rest ? .green : .blue
        let compact = model.compactCard
        TimelineView(.animation(paused: p.isPaused || p.phase == .workDone)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                WaveShape(level: p.level, phase: t * 0.6, amplitude: 6, wavelength: 140).fill(water.opacity(0.35))
                WaveShape(level: p.level, phase: t * 0.9 + 2, amplitude: 4, wavelength: 90).fill(water.opacity(0.55))
                if compact { compactContent(p) } else { wideContent(p) }
            }
        }
        .frame(width: compact ? 340 : 300, height: compact ? 56 : 100)
        .glassCard(cornerRadius: compact ? 28 : 16)
        .contentShape(Rectangle())   // right-click anywhere, not only on text and water
        .onHover { hovering = $0 }
        .contextMenu {
            Button("+5 minutes") { p.extend(by: 300) }
            Button("Complete task") { Task { await model.complete() } }
            Picker("Card size", selection: Bindable(model).compactCard) {
                Text("Wide").tag(false)
                Text("Compact").tag(true)
            }
            Divider()
            Button("Stop") { model.stop() }
        }
    }

    // MARK: Wide (Layout 2)

    @ViewBuilder
    private func wideContent(_ p: Pomodoro) -> some View {
        HStack(spacing: 12) {
            if p.phase == .workDone {
                RoundButton(icon: "checkmark", size: 36, filled: true, tint: .green) { Task { await model.complete() } }
                VStack(alignment: .leading, spacing: 6) {
                    caption("Done · \(Int(p.total / 60)) min")
                    Text(p.task?.content ?? "").help(p.task?.content ?? "").font(.system(size: 11, weight: .semibold)).lineLimit(1)
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
                    .opacity(controlOpacity)
                Text(timeString(p.remaining))
                    .font(.system(size: 28, weight: .light, design: .rounded).monospacedDigit())
                    .opacity(p.isPaused ? 0.45 : 1)
                Divider().frame(height: 36)
                VStack(alignment: .leading, spacing: 3) {
                    caption(p.phase == .rest ? "Break" : p.isPaused ? "Paused" : "Focus")
                    Text(p.task?.content ?? "").help(p.task?.content ?? "").font(.system(size: 11, weight: .semibold)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RoundButton(icon: "checkmark", size: 28) { Task { await model.complete() } }
                    .opacity(controlOpacity)
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
                    .opacity(controlOpacity)
                Text(p.task?.content ?? "").help(p.task?.content ?? "").font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Text(timeString(p.remaining))
                    .font(.system(size: 22, weight: .light, design: .rounded).monospacedDigit())
                    .opacity(p.isPaused ? 0.45 : 1)
                RoundButton(icon: "checkmark", size: 28) { Task { await model.complete() } }
                    .opacity(controlOpacity)
            }
        }
        .padding(.horizontal, 12)
    }

    private var controlOpacity: Double { hovering ? 1 : 0.65 }

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

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(filled ? Color.white : Color.primary)
                .frame(width: size, height: size)
                .background(filled ? AnyShapeStyle(tint) : AnyShapeStyle(.primary.opacity(0.08)), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
