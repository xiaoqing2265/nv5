import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class AccessibilitySettings {
    static let shared = AccessibilitySettings()

    var reduceMotion: Bool = false
    var increaseContrast: Bool = false

    private init() {
        updateSettings()
        setupObservers()
    }

    private func updateSettings() {
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(accessibilitySettingsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @objc private func accessibilitySettingsDidChange() {
        updateSettings()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
