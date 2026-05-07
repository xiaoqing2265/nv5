import SwiftUI

public struct InlinePopover<Trigger: View, Content: View>: View {
    @State private var isShown = false
    let trigger: () -> Trigger
    let content: () -> Content
    let delay: Duration

    public init(
        delay: Duration = .milliseconds(400),
        @ViewBuilder trigger: @escaping () -> Trigger,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.delay = delay
        self.trigger = trigger
        self.content = content
    }

    public var body: some View {
        trigger()
            .onHover { hovering in
                Task {
                    if hovering {
                        try? await Task.sleep(for: delay)
                        isShown = true
                    } else {
                        isShown = false
                    }
                }
            }
            .popover(isPresented: $isShown) {
                content().padding()
            }
    }
}

#Preview("InlinePopover") {
    InlinePopover(trigger: {
        Text("Hover me")
    }, content: {
        Text("Popover content")
    })
    .padding()
}