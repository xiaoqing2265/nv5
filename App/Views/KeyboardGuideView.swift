import SwiftUI

struct KeyboardGuideView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Text("欢迎使用 NV5")
                .font(.title)
            
            Text("NV5 是为键盘而生的笔记应用，这是核心快捷键：")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(spacing: 8) {
                shortcutRow("⌘N", "新建笔记")
                shortcutRow("⌘L", "聚焦搜索栏")
                shortcutRow("⌘⇧P", "命令面板")
                shortcutRow("⌘1-4", "切换焦点区")
                shortcutRow("⌘/", "完整快捷键列表")
            }
            .padding(.top, 8)
            
            Button("开始使用") {
                UserDefaults.standard.set(true, forKey: "hasShownKeyboardGuide")
                dismiss()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(width: 400)
        .padding(32)
    }
    
    private func shortcutRow(_ keys: String, _ action: String) -> some View {
        HStack {
            Text(keys)
                .font(.body.monospaced())
                .foregroundStyle(.blue)
                .frame(width: 80, alignment: .trailing)
            Text(action)
                .foregroundStyle(.primary)
            Spacer()
        }
    }
}
