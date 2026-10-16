import Foundation

/// Sizes for VocaMac's window and validation of its persisted frame,
/// independent of AppKit windows.
enum SettingsWindowGeometry {
    /// The window opens at this content size.
    static let defaultContentSize = CGSize(width: 1240, height: 800)
    /// The smallest content size: the 1000 × 680 Settings sheet still fits
    /// inside with a margin on every side.
    static let minimumContentSize = CGSize(width: 1080, height: 740)
    /// Where the v3 window remembers its frame. A new name, so frames saved
    /// by the old Settings window (often 1080 × 740) don't carry over and
    /// everyone starts at the default size.
    static let frameAutosaveName = "VocaMac.Window.v3"
    /// Frames the old Settings window saved; never read.
    static let retiredFrameAutosaveNames = ["VocaMac.Settings"]
    /// Room kept free around a window that opens on a small screen.
    static let screenMargin: CGFloat = 40

    /// The size the window opens at on a screen with this visible frame:
    /// the default, shrunk to leave a margin on a small screen, but never
    /// below the minimum.
    static func openingContentSize(forVisibleFrame screen: CGRect?) -> CGSize {
        guard let screen, screen.width > 0, screen.height > 0 else { return defaultContentSize }
        return CGSize(
            width: max(minimumContentSize.width, min(defaultContentSize.width, screen.width - screenMargin * 2)),
            height: max(minimumContentSize.height, min(defaultContentSize.height, screen.height - screenMargin * 2))
        )
    }

    /// Whether a saved frame is unusable: collapsed, smaller than the
    /// minimum (e.g. the old 860 × 620 Settings window), or off every screen.
    static func needsReset(_ frame: CGRect, screens: [CGRect]) -> Bool {
        guard frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              frame.width >= minimumContentSize.width,
              frame.height >= minimumContentSize.height else { return true }
        return !screens.contains { screen in
            let visible = frame.intersection(screen)
            return visible.width >= 200 && visible.height >= 100
                && frame.maxY <= screen.maxY + 40 && frame.maxY >= screen.minY + 100
        }
    }
}
