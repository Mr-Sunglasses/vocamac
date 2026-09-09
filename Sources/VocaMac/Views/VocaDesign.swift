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
            .padding(18)
            .background(VocaDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(VocaDesign.line))
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
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
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
