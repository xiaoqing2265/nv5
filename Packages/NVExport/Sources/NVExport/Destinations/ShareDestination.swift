import AppKit

@MainActor
public enum ShareDestination {

    /// 在指定 NSView 附近弹出系统分享菜单
    public static func share(
        _ content: ExportContent,
        format: ExportFormat,
        from view: NSView,
        edge: NSRectEdge = .minY
    ) {
        let items = sharingItems(for: content, format: format)
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: .zero, of: view, preferredEdge: edge)
    }

    private static func sharingItems(for content: ExportContent, format: ExportFormat) -> [Any] {
        switch content {
        case .text(let s): return [s]
        case .rtfData(let d):
            // RTF 需要写到临时文件以便分享
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("NV5-Share-\(UUID().uuidString)")
                .appendingPathExtension(format.fileExtension)
            try? d.write(to: tmp)
            return [tmp]
        }
    }
}