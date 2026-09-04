import SwiftUI
import TodoistCore

@main
struct PourApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // POUR_DEMO=1 starts a fake session at launch so the card can be screenshotted without a token.
        if ProcessInfo.processInfo.environment["POUR_DEMO"] != nil {
            let m = AppModel(); _model = State(initialValue: m)
            m.start(TodoistTask(id: "demo", content: "Write the release notes for 0.1", priority: 4, labels: ["Creative Memories"]))
            if ProcessInfo.processInfo.environment["POUR_DEMO"] == "settings" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            PickerView().environment(model)
        } label: {
            MenuBarLabel().environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(model)
        }
    }
}

/// Menu bar label rendered as ONE template image, so spacing and vertical alignment are ours.
/// (MenuBarExtra flattens a SwiftUI label to image + title and ignores layout modifiers.)
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.pomodoro
        let _ = model.tick
        Image(nsImage: render(p))
    }

    private func render(_ p: Pomodoro) -> NSImage {
        let showTime = p.isRunning && p.phase != .workDone
        let view = HStack(spacing: 7) {
            if p.phase == .rest {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 13, weight: .medium))
            } else {
                glass(level: p.isRunning ? max(0.08, p.level) : 0.5)
            }
            if showTime {
                Text(timeString(p.remaining)).font(.system(size: 13, weight: .medium)).monospacedDigit()
            }
        }
        .frame(height: 18)
        .foregroundStyle(.black)
        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        img.isTemplate = true
        return img
    }

    private func glass(level: Double) -> some View {
        ZStack {
            Circle().strokeBorder(lineWidth: 1.5)
            WaveShape(level: level, phase: 0, amplitude: 1, wavelength: 9).fill().clipShape(Circle().inset(by: 1.5))
        }
        .frame(width: 16, height: 16)
    }
}

/// "1 h 40 m", or "40 m" under the hour.
func hoursMinutes(_ seconds: TimeInterval) -> String {
    let m = Int(seconds / 60)
    return m >= 60 ? "\(m / 60) h \(m % 60) m" : "\(m) m"
}

func timeString(_ s: TimeInterval) -> String {
    let s = Int(s.rounded(.up))
    return String(format: "%02d:%02d", s / 60, s % 60)
}

/// Opens the Todoist desktop app, falling back to the web app when the `todoist://` scheme
/// isn't registered (app not installed).
func openTodoist(_ task: TodoistTask? = nil) {
    let path = task.map { "task?id=\($0.id)" } ?? ""
    if NSWorkspace.shared.open(URL(string: "todoist://\(path)")!) { return }
    let web = task.map { "https://app.todoist.com/app/task/\($0.id)" } ?? "https://app.todoist.com/app"
    NSWorkspace.shared.open(URL(string: web)!)
}
