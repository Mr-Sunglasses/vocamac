// CalmStylesComponents.swift
// VocaMac
//
// Pieces of the Styles page: the style card with its live sample, the
// “Used in” app chips, a wrapping row layout, app icons and the compact
// rows the Styles dialogs use.

import AppKit
import SwiftUI

// MARK: - Style card

/// A style card (Patterns board): a live sample on panel, then the name, a
/// short line and a radio. Selected cards get the 2 pt ink ring.
struct CalmStyleCard: View {
    let style: WritingStyle
    let sample: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(sample.isEmpty ? " " : sample)
                    .font(style.calmSampleIsMonospaced ? .system(size: 13, design: .monospaced) : CalmFont.body)
                    .lineSpacing(5)
                    .foregroundStyle(CalmColor.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 110 - 32, alignment: .topLeading)
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CalmColor.panel))
                    .padding([.horizontal, .top], 12)
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(style.displayName)
                            .font(CalmFont.cardTitle)
                            .foregroundStyle(CalmColor.ink)
                        Text(style.calmTagline)
                            .font(CalmFont.sf(12.5, weight: 400))
                            .lineSpacing(1.5)
                            .foregroundStyle(CalmColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    CalmRadio(isOn: isSelected)
                }
                .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .calmCard(selected: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: CalmMetrics.Radius.panel, style: .continuous))
        }
        .buttonStyle(CalmPlainFocusStyle(radius: CalmMetrics.Radius.panel))
        .focusEffectDisabled()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(style.displayName). \(style.calmTagline). Example: \(sample)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Chips

/// The look of an app chip in “Used in”: h32, px12, r9, panel fill, SF 13.
struct CalmStylesChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CalmStylesChipBody(configuration: configuration)
    }
}

private struct CalmStylesChipBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CalmMetrics.Radius.button, style: .continuous)
        configuration.label
            .font(CalmFont.sf(13, weight: 400))
            .foregroundStyle(CalmColor.ink)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(shape.fill(isHovered && isEnabled ? CalmColor.panel2 : CalmColor.panel))
            .contentShape(shape)
            .calmPressed(configuration.isPressed, scheme: scheme)
            .calmFocusRing(isFocused && isEnabled, radius: CalmMetrics.Radius.button)
            .calmDisabledDimming()
            .onHover { isHovered = $0 }
    }
}

/// A non-interactive chip (“All other apps”).
struct CalmStylesStaticChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(CalmFont.sf(13, weight: 400))
            .foregroundStyle(CalmColor.muted)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: CalmMetrics.Radius.button, style: .continuous).fill(CalmColor.panel))
    }
}

/// A chip's text: the name, then muted notes (“Paused”, another style).
struct CalmStylesChipLabel: View {
    let name: String
    let notes: [String]
    var isDimmed = false

    var body: some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(isDimmed ? CalmColor.muted : CalmColor.ink)
            if !notes.isEmpty {
                Text(notes.joined(separator: " · ")).foregroundStyle(CalmColor.muted)
            }
        }
    }
}

/// The secondary button beside the chips, 32 tall to sit level with them.
struct CalmStylesChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CalmStylesChipButtonBody(configuration: configuration)
    }
}

private struct CalmStylesChipButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var scheme
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CalmMetrics.Radius.button, style: .continuous)
        configuration.label
            .font(CalmFont.button)
            .foregroundStyle(CalmColor.ink)
            .lineLimit(1)
            .padding(.horizontal, CalmMetrics.buttonPadding)
            .frame(height: 32)
            .background(shape.fill(isHovered && isEnabled ? CalmColor.line2 : CalmColor.panel2))
            .contentShape(shape)
            .calmPressed(configuration.isPressed, scheme: scheme)
            .calmFocusRing(isFocused && isEnabled, radius: CalmMetrics.Radius.button)
            .calmDisabledDimming()
            .onHover { isHovered = $0 }
    }
}

/// “+ Add app or website”: a 13-point plus at stroke 2, gap 7.
struct CalmStylesAddLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            CalmIcon(.plus, size: 13, weight: 2)
            Text(title)
        }
    }
}

// MARK: - Wrapping row

/// Lays children out left to right, wrapping onto new lines.
struct CalmStylesFlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - App icon

/// An app's own icon at 28 (r7), or its first letter on panel2 when the
/// app can't be found on this Mac.
struct CalmStylesAppIcon: View {
    let name: String
    let bundleIdentifier: String?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let icon = CalmStylesAppIconCache.icon(for: bundleIdentifier) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(CalmColor.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(CalmColor.panel2))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Icons are cached: the page re-renders on every AppState change, and each
/// lookup is a LaunchServices round trip.
@MainActor
enum CalmStylesAppIconCache {
    private static var icons: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = icons[bundleIdentifier] { return cached }
        guard !missing.contains(bundleIdentifier),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            missing.insert(bundleIdentifier)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleIdentifier] = image
        return image
    }
}

// MARK: - Dialog rows

/// A compact row inside a Styles dialog: title (SF 14/560) and an optional
/// muted note on the left, the control on the right.
struct CalmStylesDialogRow<Control: View>: View {
    let title: String
    var note: String?
    let control: Control

    init(_ title: String, note: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.note = note
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).calmType(.rowTitle).fixedSize(horizontal: false, vertical: true)
                if let note {
                    Text(note)
                        .font(CalmFont.note)
                        .foregroundStyle(CalmColor.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
    }
}

/// A switch row inside a Styles dialog.
struct CalmStylesDialogToggle: View {
    let title: String
    var note: String?
    @Binding var isOn: Bool

    init(_ title: String, note: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.note = note
        _isOn = isOn
    }

    var body: some View {
        CalmStylesDialogRow(title, note: note) {
            CalmSwitch(isOn: $isOn).accessibilityLabel(title)
        }
    }
}

/// “You say … → VocaMac types …” for one style, run through the real engine.
struct CalmStylesExample: View {
    @EnvironmentObject private var appState: AppState
    let style: WritingStyle
    var rules: WritingStyleRules?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(style.shortDescription)
                .font(CalmFont.note)
                .foregroundStyle(CalmColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("“\(style.exampleSentence)”")
                    .font(CalmFont.description)
                    .foregroundStyle(CalmColor.ink2)
                CalmIcon(.arrowRight, size: 13)
                    .foregroundStyle(CalmColor.muted)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
                Text(appState.writingStylePreview(style.exampleSentence, rules: rules ?? style.defaultRules))
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(CalmColor.ink)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CalmColor.panel))
    }
}

/// The “Advanced” disclosure link inside a dialog.
struct CalmStylesDisclosure: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                CalmIcon(isExpanded ? .chevDown : .chevRight, size: 13, weight: 2)
            }
        }
        .calmLink()
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
