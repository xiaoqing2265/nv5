import AppKit
import SwiftUI

@MainActor
final class PaletteWindowManager {
    static let shared = PaletteWindowManager()

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var observerTokens: [NSObjectProtocol] = []
    private var focusCoordinator: FocusCoordinator?
    private var localMonitor: Any?

    private init() {}

    func show(coordinator: AppCoordinator, focusCoordinator: FocusCoordinator) {
        if let panel = panel, panel.isVisible {
            hide()
            return
        }

        OverlayManager.shared.open(.commandPalette)
        self.focusCoordinator = focusCoordinator

        let paletteView = CommandPaletteView()
            .environment(coordinator)
            .environment(focusCoordinator)
            .environment(OverlayManager.shared)

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

        // Monitor mouse clicks to hide palette when clicking outside
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self = self, let panel = self.panel else { return event }
            // Click inside panel → pass through
            if event.window == panel { return event }
            // Click outside panel → hide and pass through to underlying view
            self.hide()
            return event
        }

        // Explicitly focus the palette's text field
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            if let hosting = self.hostingView,
               let tf = hosting.subviews.first(where: { $0 is NSTextField }) as? NSTextField {
                hosting.window?.makeFirstResponder(tf)
            }
        }
    }

    func hide() {
        OverlayManager.shared.close(.commandPalette)
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observerTokens.removeAll()
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
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
