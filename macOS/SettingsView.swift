import SwiftUI
import TodoistCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Todoist") {
                SecureField("API token", text: $model.token)
                LabeledContent("Get a token") {
                    linkButton("Settings → Integrations → Developer", "https://app.todoist.com/app/settings/integrations/developer")
                }
                HStack(alignment: .center) {   // LabeledContent aligns on text baseline, which drops the segments ~2 pt
                    Text("Default filter"); Spacer()
                    Picker("", selection: $model.filter) {
                        ForEach(TodoistTask.filters, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
            }
            Section("Session") {
                MinutesField("Work length", value: $model.workMinutes, range: 1...120, step: 5)
                MinutesField("Break length", value: $model.breakMinutes, range: 1...60, step: 1)
                Toggle(isOn: $model.autoBreak) {
                    Text("Start break automatically")
                    Text("10 seconds after the focus session ends")
                }
            }
            Section("When a session ends") {
                Toggle("Play sound", isOn: $model.sound)
                Toggle("Show notification", isOn: $model.notifications)
                Toggle(isOn: $model.logComment) {
                    Text("Log a comment on the task")
                    Text("“🍅 25 min focus” and “☕ 5 min break”")
                }
            }
            Section("Floating card") {
                HStack(alignment: .center) {
                    Text("Card size"); Spacer()
                    Picker("", selection: $model.compactCard) {
                        Text("Wide").tag(false); Text("Compact").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                }
                Toggle("Show on all Spaces", isOn: $model.allSpaces)
            }
            Section("About") {
                LabeledContent("Pour", value: "Version \(version)")
                LabeledContent("Source") { linkButton("github.com/iammayron/pour", "https://github.com/iammayron/pour") }
                LabeledContent("Made by") { linkButton("mayronalves.com", "https://mayronalves.com") }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .scrollDisabled(true)
        .frame(width: 480, height: 900)
        .overlay(alignment: .top) { SavedToast(lastSaved: model.lastSaved) }
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private func linkButton(_ title: String, _ url: String) -> some View {
        Button(title) { NSWorkspace.shared.open(URL(string: url)!) }.buttonStyle(.link)
    }
}

/// "Saved" pill that fades in at the top after any change and fades out 1.5 s later.
struct SavedToast: View {
    let lastSaved: Date?
    @State private var visible = false
    @State private var hide: Task<Void, Never>?

    var body: some View {
        Label("Saved", systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.green)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.green.opacity(0.35), lineWidth: 1))
            .padding(.top, 12)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: visible)
            .allowsHitTesting(false)
            .onChange(of: lastSaved) {
                guard lastSaved != nil else { return }
                visible = true
                hide?.cancel()
                hide = Task { try? await Task.sleep(for: .seconds(1.5)); if !Task.isCancelled { visible = false } }
            }
    }
}

/// Number field with a stepper, as in the design: `[ 25 ] min ▴▾`.
struct MinutesField: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    init(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) {
        self.label = label; _value = value; self.range = range; self.step = step
    }

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .onSubmit { value = min(max(value, range.lowerBound), range.upperBound) }
                Text("min").foregroundStyle(.secondary)
                Stepper("", value: $value, in: range, step: step).labelsHidden()
            }
        }
    }
}
