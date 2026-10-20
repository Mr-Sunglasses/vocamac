import AppKit
import SwiftUI

private struct SettingsSearchTargetKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingsSearchTarget: String? {
        get { self[SettingsSearchTargetKey.self] }
        set { self[SettingsSearchTargetKey.self] = newValue }
    }
}

/// Stable scroll destinations shared with the search index. Highlighting is
/// temporary and never intercepts clicks or changes the control's AX traits.
private struct SettingsSearchTarget: ViewModifier {
    let ids: [String]
    @Environment(\.settingsSearchTarget) private var selected
    @State private var highlighted = false

    func body(content: Content) -> some View {
        content
            .id(ids[0])
            .accessibilityIdentifier(ids[0])
            // Aliases get anchors of their own over the same frame. Swapping
            // the control's id to the alias would rebuild it and drop its state.
            .background {
                ForEach(ids.dropFirst(), id: \.self) { Color.clear.id($0) }
            }
            // Drawn inside the control's frame: v3 rows run edge to edge
            // in their panel, so an outset ring would spill past it.
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(highlighted ? CalmColor.accentSoft : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(highlighted ? CalmColor.accent : .clear, lineWidth: 2)
                    )
                    .animation(.easeOut(duration: 0.2), value: highlighted)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                if highlighted { SettingsSearchReveal() }
            }
            .task(id: selected) {
                highlighted = selected.map(ids.contains) ?? false
                guard highlighted else { return }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                highlighted = false
            }
    }
}

extension View {
    func settingsTarget(_ id: String, aliases: [String] = []) -> some View {
        modifier(SettingsSearchTarget(ids: [id] + aliases))
    }
}

/// Brings a flashed search target into view through AppKit, after the
/// page's own `ScrollViewReader` had its turn. In the app window a sidebar
/// page's scroll view ignored `scrollTo` after the Settings sheet closed
/// over it (the target flashed off screen), so this centres the control in
/// every scroll view around it that doesn't already show it whole.
private struct SettingsSearchReveal: NSViewRepresentable {
    func makeNSView(context: Context) -> RevealView { RevealView() }
    func updateNSView(_ nsView: RevealView, context: Context) {}

    final class RevealView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // After the page's own scroll (120 ms) and the sheet's fade.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.reveal()
            }
        }

        private func reveal() {
            var view: NSView = self
            while let scrollView = view.enclosingScrollView, let document = scrollView.documentView {
                let clip = scrollView.contentView
                let rect = convert(bounds, to: document)
                let visible = clip.documentVisibleRect
                if !visible.contains(rect) {
                    var origin = clip.bounds.origin
                    origin.y = rect.midY - visible.height / 2
                    let maxY = max(0, document.frame.height - visible.height)
                    origin.y = min(max(origin.y, 0), maxY)
                    if !document.isFlipped { origin.y = maxY - origin.y }
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.25
                        clip.animator().setBoundsOrigin(origin)
                    }
                    scrollView.reflectScrolledClipView(clip)
                }
                view = scrollView
            }
        }
    }
}
