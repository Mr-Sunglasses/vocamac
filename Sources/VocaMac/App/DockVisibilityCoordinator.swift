// DockVisibilityCoordinator.swift
// VocaMac
//
// Decides when the Dock icon should appear for a menu-bar-only app.

import AppKit

/// Tracks how many app windows are open so the Dock icon is shown while any
/// of them is on screen and hidden only once the last one closes.
///
/// VocaMac normally runs as an accessory (no Dock icon), but a window cannot
/// take focus in that mode, so opening one flips the app to `.regular`. Each
/// window manager used to flip back to `.accessory` on its own close, which
/// meant closing one window hid the Dock icon while another was still
/// visible — closing the update window with Settings open, for example.
@MainActor
final class DockVisibilityCoordinator {

    static let shared = DockVisibilityCoordinator()

    /// Windows currently on screen.
    private(set) var openWindowCount = 0

    /// Applies the activation policy. Injectable so the counting behaviour
    /// can be tested without a running NSApplication.
    private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void

    /// Grace period before hiding the Dock icon, so a window closing as
    /// another opens does not make the icon flicker.
    private let hideDelay: TimeInterval

    init(
        hideDelay: TimeInterval = 0.5,
        applyPolicy: @escaping @MainActor (NSApplication.ActivationPolicy) -> Void = { policy in
            NSApp.setActivationPolicy(policy)
        }
    ) {
        self.hideDelay = hideDelay
        self.applyPolicy = applyPolicy
    }

    /// Register a window that has just been shown, revealing the Dock icon.
    func windowDidOpen() {
        openWindowCount += 1
        applyPolicy(.regular)
    }

    /// Register a window that has closed. The Dock icon is hidden only when
    /// no windows remain, and only if none has opened during the grace period.
    func windowDidClose() {
        openWindowCount = max(0, openWindowCount - 1)
        guard openWindowCount == 0 else { return }

        let deadline = DispatchTime.now() + hideDelay
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self, self.openWindowCount == 0 else { return }
            self.applyPolicy(.accessory)
        }
    }
}
