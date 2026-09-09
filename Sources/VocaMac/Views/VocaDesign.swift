import SwiftUI

/// Shared, adaptive surfaces for the app. System text colors retain contrast in both appearances.
enum VocaDesign {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.47, green: 0.85, blue: 0.74, alpha: 1)
            : BrandAssets.brandGreen
    })
    /// Fill for prominent buttons. The mint accent is tuned for icons and
    /// selection on a dark surface; white button text needs a deeper green to
    /// stay legible, so prominent fills use this instead.
    static let accentSolid = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.090, green: 0.470, blue: 0.380, alpha: 1)
            : BrandAssets.brandGreen
    })

    /// Success and "ready" states. The brand is already green, so a second
    /// system green next to it reads as two different greens rather than one
    /// meaning.
    static var success: Color { accent }
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.10)
}

/// Consistent card treatment without overriding native control behavior.
/// A 3.5% primary fill nearly vanishes on the dark window background, so the
/// hairline carries the card edge in both appearances.
struct VocaCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(VocaDesign.line))
    }
}

extension View {
    func vocaCard() -> some View { modifier(VocaCard()) }
}

struct VocaPageHeader: View {
    let title: String
    let subtitle: String
    var horizontalPadding: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 25, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 20)
    }
}

struct VocaGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label.font(.headline)
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vocaCard()
    }
}

extension View {
    @ViewBuilder
    func vocaGlassButton() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Native sidebar vibrancy for onboarding and older macOS releases.
struct VocaSidebarMaterial: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeNSView(context: Context) -> NSVisualEffectView {
        NSVisualEffectView()
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.wantsLayer = true
        view.layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
    }
}

/// Compact settings groups with a consistent heading and bounded row spacing.
///
/// The heading sits above the card so hand-built pages match the `Section`
/// headers that `Form(.grouped)` draws on the pages still using a `Form`.
struct VocaSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 8)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .vocaCard()
        }
    }
}

/// Scroll container shared by the hand-built settings pages so their content
/// insets match the `Form(.grouped)` pages either side of them in the sidebar.
struct VocaSettingsPageContent<Content: View>: View {
    var spacing: CGFloat = 20
    @ViewBuilder let content: Content

    init(spacing: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}
