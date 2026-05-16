import AppKit
import SwiftUI

@MainActor
final class PaletteWindowManager {
    static let shared = PaletteWindowManager()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var observerTokens: [NSObjectProtocol] = []
    private var focusCoordinator: FocusCoordinator?

    private init() {}

    func show(coordinator: AppCoordinator, focusCoordinator: FocusCoordinator) {
        if let panel = panel, panel.isVisible {
            hide()
            focusCoordinator.showPalette = false
            return
        }

        self.focusCoordinator = focusCoordinator

        let paletteView = CommandPaletteView()
            .environment(coordinator)
            .environment(focusCoordinator)

        let hosting = NSHostingView(rootView: AnyView(paletteView))
        hostingView = hosting

        let contentSize = NSSize(width: 600, height: 480)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelFrame = NSRect(
            x: (screenFrame.width - contentSize.width) / 2 + screenFrame.origin.x,
            y: screenFrame.origin.y + screenFrame.height * 0.70,
            width: contentSize.width,
            height: contentSize.height
        )
        panel.setFrame(panelFrame, display: true)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.panel = panel

        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let window = notification.object as? NSWindow,
                      window != self.panel else { return }
                if window.title.contains("NV5") || window == NSApp.mainWindow {
                    self.hide()
                    self.focusCoordinator?.showPalette = false
                }
            }
        }
        observerTokens.append(token)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            if let tf = hosting.findFirstResponder() as? NSTextField {
                tf.selectText(nil)
            }
        }
    }

    func hide() {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observerTokens.removeAll()
        panel?.close()
        panel = nil
        hostingView = nil
    }
}

extension NSView {
    func findFirstResponder() -> NSResponder? {
        if let window = self.window, let responder = window.firstResponder {
            return responder
        }
        for subview in subviews {
            if let found = subview.findFirstResponder() {
                return found
            }
        }
        return nil
    }
}
