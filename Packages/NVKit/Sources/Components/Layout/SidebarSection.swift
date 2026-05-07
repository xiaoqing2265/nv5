import SwiftUI

public struct SidebarSection<Content: View>: View {
    public let title: String?
    public let content: () -> Content

    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        Section {
            content()
        } header: {
            if let title = title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
            }
        }
    }
}

#Preview("SidebarSection") {
    List {
        SidebarSection("Labels") {
            Text("Work")
            Text("Personal")
        }
    }
    .listStyle(.sidebar)
    .frame(width: 200)
}