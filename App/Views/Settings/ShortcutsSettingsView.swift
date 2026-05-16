import SwiftUI
import KeyboardShortcuts

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            ForEach(CommandCategory.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(CommandRegistry.shared.commands.filter { $0.category == category }, id: \.id) { cmd in
                        let name = KeyboardShortcuts.Name(cmd.id)
                        KeyboardShortcuts.Recorder(for: name) {
                            Label(cmd.title, systemImage: cmd.symbol)
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("恢复默认") {
                    for cmd in CommandRegistry.shared.commands {
                        let name = KeyboardShortcuts.Name(cmd.id)
                        KeyboardShortcuts.reset(name)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 600, minHeight: 500)
    }
}
