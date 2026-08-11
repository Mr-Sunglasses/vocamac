import AppKit
import CoreGraphics
import Foundation

let width: CGFloat = 1200
let height: CGFloat = 630

let image = NSImage(size: NSSize(width: width, height: height))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    print("Failed to get context"); exit(1)
}

// Colors
let bgPrimary = NSColor.white
let bgSecondary = NSColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1.0)
let textPrimary = NSColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0)
let textSecondary = NSColor(red: 0.431, green: 0.431, blue: 0.451, alpha: 1.0)
let accent = NSColor(red: 0.0, green: 0.443, blue: 0.890, alpha: 1.0)
let green = NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 1.0)
let borderColor = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.08)
let btnBg = NSColor(red: 0.114, green: 0.114, blue: 0.122, alpha: 1.0)
let btnText = NSColor.white
let orangeColor = NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)

// Background
bgPrimary.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Subtle gradient glow
let gradientColors = [
    NSColor(red: 0.161, green: 0.592, blue: 1.0, alpha: 0.05).cgColor,
    NSColor.white.withAlphaComponent(0.0).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradientColors, locations: [0.0, 1.0]) {
    context.drawRadialGradient(gradient, startCenter: CGPoint(x: 200, y: height - 200), startRadius: 0,
        endCenter: CGPoint(x: 200, y: height - 200), endRadius: 500, options: [])
}

// Helpers
func ty(_ topY: CGFloat, h: CGFloat = 20) -> CGFloat { height - topY - h }

func textSize(_ text: String, font: NSFont) -> NSSize {
    let attrs: [NSAttributedString.Key: Any] = [.font: font]
    let str = NSAttributedString(string: text, attributes: attrs)
    return str.boundingRect(with: NSSize(width: 1000, height: 300), options: [.usesLineFragmentOrigin]).size
}

func drawText(_ text: String, x: CGFloat, topY: CGFloat, font: NSFont, color: NSColor, maxWidth: CGFloat? = nil) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: text, attributes: attrs)
    let bound = str.boundingRect(with: NSSize(width: maxWidth ?? width, height: 300), options: [.usesLineFragmentOrigin])
    if let mw = maxWidth {
        str.draw(with: NSRect(x: x, y: ty(topY, h: bound.height), width: mw, height: bound.height), options: [.usesLineFragmentOrigin])
    } else {
        str.draw(at: NSPoint(x: x, y: ty(topY, h: bound.height)))
    }
}

// Draw text centered inside a rect (both horiz and vert)
func drawCenteredText(_ text: String, inRect rect: (x: CGFloat, topY: CGFloat, w: CGFloat, h: CGFloat), font: NSFont, color: NSColor) {
    let size = textSize(text, font: font)
    let textX = rect.x + (rect.w - size.width) / 2
    let textTopY = rect.topY + (rect.h - size.height) / 2
    drawText(text, x: textX, topY: textTopY, font: font, color: color)
}

func drawBoldText(_ text: String, boldPart: String, x: CGFloat, topY: CGFloat, font: NSFont, boldFont: NSFont, color: NSColor) {
    let str = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    if let range = text.range(of: boldPart) {
        let nsRange = NSRange(range, in: text)
        str.addAttribute(.font, value: boldFont, range: nsRange)
    }
    let bound = str.boundingRect(with: NSSize(width: width, height: 300), options: [.usesLineFragmentOrigin])
    str.draw(at: NSPoint(x: x, y: ty(topY, h: bound.height)))
}

func drawRR(x: CGFloat, topY: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, fill: NSColor, border: NSColor? = nil) {
    let rect = NSRect(x: x, y: ty(topY, h: h), width: w, height: h)
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    fill.setFill(); path.fill()
    if let b = border { b.setStroke(); path.lineWidth = 1; path.stroke() }
}

// ===== LAYOUT =====
let pad: CGFloat = 56
let leftX: CGFloat = pad

// ===== LEFT SIDE (vertically centered) =====

// Calculate total left content height to center vertically
let logoSize: CGFloat = 65
let leftContentHeight: CGFloat = logoSize + 30 + 38 + 34 + 142 + 36 + 52  // logo + gaps + tagline + bullets + cta
let leftTopY: CGFloat = (height - leftContentHeight) / 2

// Logo + Title inline
let logoPath = "web/static/brand/voca-logo-512.png"
if let logoImage = NSImage(contentsOfFile: logoPath) {
    let logoRect = NSRect(x: leftX, y: ty(leftTopY + 2, h: logoSize), width: logoSize * 0.75, height: logoSize)
    logoImage.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}
let titleX = leftX + logoSize * 0.75 + 10
drawText("VocaMac", x: titleX, topY: leftTopY + 4, font: .systemFont(ofSize: 60, weight: .bold), color: textPrimary)

// Tagline
let taglineY = leftTopY + 95
drawText("Dictate Privately. Locally. Instantly.", x: leftX, topY: taglineY, font: .systemFont(ofSize: 32, weight: .semibold), color: textPrimary)

// Condensed bullet points with bold key phrases
let bulletY = taglineY + 66
let bulletRegFont = NSFont.systemFont(ofSize: 20, weight: .regular)
let bulletBoldFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
drawBoldText("✦  100% Offline — nothing leaves your Mac", boldPart: "100% Offline", x: leftX, topY: bulletY, font: bulletRegFont, boldFont: bulletBoldFont, color: textSecondary)
drawBoldText("✦  Any App — types wherever your cursor is", boldPart: "Any App", x: leftX, topY: bulletY + 36, font: bulletRegFont, boldFont: bulletBoldFont, color: textSecondary)
drawBoldText("✦  Apple Neural Engine + WhisperKit powered", boldPart: "Apple Neural Engine", x: leftX, topY: bulletY + 72, font: bulletRegFont, boldFont: bulletBoldFont, color: textSecondary)
drawBoldText("✦  Free & Open Source (AGPL-3.0)", boldPart: "Free & Open Source", x: leftX, topY: bulletY + 108, font: bulletRegFont, boldFont: bulletBoldFont, color: textSecondary)

// Download CTA button — text centered
let ctaY = bulletY + 152
let ctaW: CGFloat = 320
let ctaH: CGFloat = 52
drawRR(x: leftX, topY: ctaY, w: ctaW, h: ctaH, r: 10, fill: btnBg)
// GitHub logo in button (white on transparent)
let ghLogoPath = "/tmp/github-mark-white.png"
if let ghLogo = NSImage(contentsOfFile: ghLogoPath) {
    let ghSize: CGFloat = 26
    let ghX = leftX + 30
    let ghY = ctaY + (ctaH - ghSize) / 2
    let ghRect = NSRect(x: ghX, y: ty(ghY, h: ghSize), width: ghSize, height: ghSize)
    ghLogo.draw(in: ghRect, from: .zero, operation: .sourceOver, fraction: 1.0)
}
drawCenteredText("   Download on GitHub", inRect: (leftX, ctaY, ctaW, ctaH), font: .systemFont(ofSize: 18, weight: .semibold), color: btnText)

// URL — larger, underlined
context.setStrokeColor(accent.cgColor)
context.setLineWidth(1.5)
context.strokePath()

// ===== FEATURE CARDS =====
struct FC { let emoji: String; let title: String; let sub: String; let tag: String; let tagColor: NSColor; let tagBg: NSColor; let tagBorder: NSColor }

let features = [
    FC(emoji: "🔒", title: "100% Local Processing", sub: "No cloud, no subscriptions, no data leaves your Mac",
       tag: "PRIVATE", tagColor: green,
       tagBg: NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 0.12),
       tagBorder: NSColor(red: 0.133, green: 0.773, blue: 0.369, alpha: 0.3)),
    FC(emoji: "🖱️", title: "System-Wide Dictation", sub: "Types wherever your cursor is, in every app",
       tag: "ANY APP", tagColor: accent,
       tagBg: NSColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 0.12),
       tagBorder: NSColor(red: 0.231, green: 0.510, blue: 0.965, alpha: 0.3)),
    FC(emoji: "💻", title: "Apple Silicon Native", sub: "CoreML + Neural Engine acceleration",
       tag: "M-SERIES", tagColor: textSecondary,
       tagBg: NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.05),
       tagBorder: borderColor),
    FC(emoji: "🎙️", title: "Push-to-Talk", sub: "Hold hotkey, speak, release. Instant results.",
       tag: "INSTANT", tagColor: orangeColor,
       tagBg: NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.12),
       tagBorder: NSColor(red: 1.0, green: 0.584, blue: 0.0, alpha: 0.3)),
]

let cw: CGFloat = 500
let cx: CGFloat = width - pad - cw
let ch: CGFloat = 104
let cardCount = CGFloat(features.count)
let cs: CGFloat = (height - 2 * pad - cardCount * ch) / (cardCount - 1)

for (i, f) in features.enumerated() {
    let ct = pad + CGFloat(i) * (ch + cs)
    drawRR(x: cx, topY: ct, w: cw, h: ch, r: 14, fill: bgSecondary, border: borderColor)
    
    // Emoji — vertically centered
    let emojiSize = textSize(f.emoji, font: .systemFont(ofSize: 30))
    let emojiTopY = ct + (ch - emojiSize.height) / 2
    drawText(f.emoji, x: cx + 22, topY: emojiTopY, font: .systemFont(ofSize: 30), color: textPrimary)
    
    // Title
    drawText(f.title, x: cx + 68, topY: ct + 20, font: .systemFont(ofSize: 20, weight: .semibold), color: textPrimary)
    
    // Subtitle
    drawText(f.sub, x: cx + 68, topY: ct + 50, font: .systemFont(ofSize: 14, weight: .regular), color: textSecondary, maxWidth: cw - 160)
    
    // Tag pill — text centered inside
    let tagFont = NSFont.systemFont(ofSize: 10, weight: .bold)
    let tagTextSize = textSize(f.tag, font: tagFont)
    let tagPadH: CGFloat = 18
    let tagW = tagTextSize.width + tagPadH
    let tagH: CGFloat = 22
    let tagX = cx + cw - tagW - 14
    let tagTopY = ct + 14
    drawRR(x: tagX, topY: tagTopY, w: tagW, h: tagH, r: 6, fill: f.tagBg, border: f.tagBorder)
    drawCenteredText(f.tag, inRect: (tagX, tagTopY, tagW, tagH), font: tagFont, color: f.tagColor)
}

image.unlockFocus()

// Export
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    print("Failed to export"); exit(1)
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "og-image.png"
try! png.write(to: URL(fileURLWithPath: out))
print("Generated: \(out) (\(Int(width))x\(Int(height)))")
