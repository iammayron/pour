import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Todoist") {
                SecureField("API token", text: $model.token)
                Link("Get a token: Settings → Integrations → Developer",
                     destination: URL(string: "https://app.todoist.com/app/settings/integrations/developer")!)
                    .font(.caption)
                Picker("Default filter", selection: $model.filter) {
                    Text("Today").tag("today"); Text("Overdue").tag("overdue"); Text("7 days").tag("7 days")
                }
            }
            Section("Session") {
                Stepper("Work length: \(Int(model.workMinutes)) min", value: $model.workMinutes, in: 1...120, step: 5)
                Stepper("Break length: \(Int(model.breakMinutes)) min", value: $model.breakMinutes, in: 1...60)
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
                    Text("“🍅 25 min focus”")
                }
            }
            Section("Floating card") {
                Picker("Card size", selection: $model.compactCard) {
                    Text("Wide").tag(false); Text("Compact").tag(true)
                }
                .pickerStyle(.segmented)
                Toggle("Show on all Spaces", isOn: $model.allSpaces)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
