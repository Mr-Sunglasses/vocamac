import SwiftUI

/// Shared, adaptive surfaces for the app. System text colors retain contrast in both appearances.
enum VocaDesign {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.47, green: 0.85, blue: 0.74, alpha: 1)
            : BrandAssets.brandGreen
    })
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let line = Color.primary.opacity(0.10)
}

/// Consistent card treatment without overriding native control behavior.
struct VocaCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

extension View {
    func vocaCard() -> some View { modifier(VocaCard()) }
}

struct VocaPageHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 25, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// Native buttons keep keyboard focus, disabled states, and accessibility semantics.
struct VocaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .background(VocaDesign.accent.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 10))
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

/// Glass belongs to navigation and actions; settings content stays on solid surfaces.
struct VocaGlassSurface: ViewModifier {
    var selected = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(selected ? VocaDesign.accent.opacity(0.18) : VocaDesign.surface,
                               in: RoundedRectangle(cornerRadius: 12))
        } else if #available(macOS 26.0, *) {
            content.glassEffect(.regular.tint(selected ? VocaDesign.accent.opacity(0.18) : .clear),
                                in: RoundedRectangle(cornerRadius: 12))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .background(selected ? VocaDesign.accent.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

extension View {
    func vocaGlass(selected: Bool = false) -> some View {
        modifier(VocaGlassSurface(selected: selected))
    }

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
struct VocaSettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .vocaCard()
    }
}
