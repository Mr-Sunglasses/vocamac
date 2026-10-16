import Foundation

/// Sizes for VocaMac's window and validation of its persisted frame,
/// independent of AppKit windows.
enum SettingsWindowGeometry {
    /// The window opens at this content size.
    static let defaultContentSize = CGSize(width: 1240, height: 800)
    /// The smallest content size: the 1000 × 680 Settings sheet still fits
    /// inside with a margin on every side.
    static let minimumContentSize = CGSize(width: 1080, height: 740)

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
