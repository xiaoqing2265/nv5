import SwiftUI
import KeyboardShortcuts

struct MenuShortcutLabel: View {
    let text: String
    let shortcutName: KeyboardShortcuts.Name

    var body: some View {
        if let shortcut = KeyboardShortcuts.getShortcut(for: shortcutName) {
            Text("\(text)  \(shortcut.description)")
        } else {
            Text(text)
        }
    }
}
