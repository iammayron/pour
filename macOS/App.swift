import SwiftUI
import TodoistCore

@main
struct TodoistFloatingApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        // TF_DEMO=1 starts a fake session at launch so the card can be screenshotted without a token.
        if ProcessInfo.processInfo.environment["TF_DEMO"] != nil {
            let m = AppModel(); _model = State(initialValue: m)
            m.start(TodoistTask(id: "demo", content: "Write the release notes for 0.1", projectId: nil, priority: 1, due: nil))
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

/// Glass glyph (filling with the session) or a cup during breaks, plus the remaining time.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.pomodoro
        let _ = model.tick
        HStack(spacing: 4) {
            if p.phase == .rest {
                Image(systemName: "cup.and.saucer.fill")
            } else {
                Image(nsImage: glassGlyph(level: p.isRunning ? p.level : 0.5))
            }
            if p.isRunning && p.phase != .workDone {
                Text(timeString(p.remaining)).monospacedDigit()
            }
        }
    }

    private func glassGlyph(level: Double) -> NSImage {
        let view = ZStack {
            Circle().strokeBorder(lineWidth: 1.5)
            WaveShape(level: level, phase: 0, amplitude: 1, wavelength: 9).fill().clipShape(Circle().inset(by: 1.5))
        }
        .frame(width: 16, height: 16)
        .foregroundStyle(.black)
        let r = ImageRenderer(content: view)
        r.scale = 2
        let img = r.nsImage ?? NSImage()
        img.isTemplate = true
        return img
    }
}

func timeString(_ s: TimeInterval) -> String {
    let s = Int(s.rounded(.up))
    return String(format: "%02d:%02d", s / 60, s % 60)
}
