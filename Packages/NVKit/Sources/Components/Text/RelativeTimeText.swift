import SwiftUI

public struct RelativeTimeText: View {
    public let date: Date
    public var style: Date.RelativeFormatStyle = .init(presentation: .named)
    @State private var refreshTrigger = 0

    public init(_ date: Date) { self.date = date }

    public var body: some View {
        Text(date.formatted(style))
            .id(refreshTrigger)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    refreshTrigger &+= 1
                }
            }
    }
}

#Preview("RelativeTimeText") {
    RelativeTimeText(Date().addingTimeInterval(-120))
        .padding()
}