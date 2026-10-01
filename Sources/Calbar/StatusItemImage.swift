import AppKit
import CalbarCore

extension CapsuleStyle {
    var color: NSColor {
        switch self {
        case .accent: .controlAccentColor
        case .soon: .systemOrange
        case .urgent: .systemRed
        }
    }

    /// Color for text on a white or light background. systemOrange is
    /// about 2.2:1 against white, too faint for a 12 pt title, so the text
    /// uses a darker orange (about 3.3:1) while the border and the glyph
    /// keep systemOrange. Red and the accent are dark enough as they are.
    var textColor: NSColor {
        switch self {
        case .soon: Self.darkOrange
        case .accent, .urgent: color
        }
    }

    static let darkOrange = NSColor(srgbRed: 0.85, green: 0.45, blue: 0, alpha: 1)
}

/// Image of the single Calbar status item. With a joinable meeting: one
/// white capsule, outlined in the urgency color, holding the camera, the
/// title, "+N", a thin separator and the calendar glyph, all in that
/// color, so the link reads as part of the Calbar icon. Otherwise the
/// plain glyph of `StatusBarImage`.
enum StatusItemImage {
    /// What the capsule shows, nil when no meeting with a link is due.
    struct Join: Equatable {
        let title: String
        let extraCount: Int
        let style: CapsuleStyle
    }

    /// `joinZoneWidth` is the width, from the image's left edge, where a
    /// click joins the meeting; 0 for the plain glyph.
    static func make(badge: MenuBarBadge, join: Join?, dark: Bool) -> (image: NSImage, joinZoneWidth: CGFloat) {
        guard let join else { return (StatusBarImage.make(badge, dark: dark), 0) }
        return capsule(join, text: badge.text, progress: badge.progress)
    }

    static let height: CGFloat = 18
    static let maxTitleWidth: CGFloat = 160

    private static let leading: CGFloat = 7
    private static let trailing: CGFloat = 4
    private static let gap: CGFloat = 4
    private static let chipPadding: CGFloat = 4
    private static let separatorGap: CGFloat = 5
    /// Calendar page inside the capsule, a bit smaller than the standalone
    /// one so it keeps a margin from the capsule's edges.
    private static let glyphSize = NSSize(width: 14.5, height: 13)

    private static func capsule(_ join: Join, text: String, progress: Double?) -> (image: NSImage, joinZoneWidth: CGFloat) {
        let color = join.style.color
        let textColor = join.style.textColor
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let chipFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let symbol = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        let symbolSize = symbol?.size ?? .zero

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let titleText = NSAttributedString(string: join.title, attributes: [
            .font: font, .foregroundColor: textColor, .paragraphStyle: paragraph,
        ])
        let titleWidth = min(ceil(titleText.size().width), maxTitleWidth)

        let chipText = join.extraCount > 0
            ? NSAttributedString(string: "+\(join.extraCount)", attributes: [
                .font: chipFont, .foregroundColor: textColor,
            ])
            : nil
        let chipWidth = chipText.map { ceil($0.size().width) + 2 * chipPadding } ?? 0

        // Left to right: camera, title, chip, separator, glyph.
        let symbolX = leading
        let titleX = symbolX + symbolSize.width + gap
        let chipX = titleX + titleWidth + gap
        let separatorX = (chipText == nil ? titleX + titleWidth : chipX + chipWidth) + separatorGap
        let glyphX = separatorX + 1 + separatorGap - 0.5
        let width = ceil(glyphX + glyphSize.width + trailing + 0.5)

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            // White everywhere, so the colored content reads the same on
            // light and dark menu bars; the thin border keeps the capsule's
            // edge visible on a light bar.
            let capsule = NSBezierPath(roundedRect: rect, xRadius: 5.5, yRadius: 5.5)
            NSColor.white.setFill()
            capsule.fill()
            let edge = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            edge.lineWidth = 1
            color.withAlphaComponent(0.7).setStroke()
            edge.stroke()

            if let symbol {
                symbol.draw(in: NSRect(x: symbolX, y: rect.midY - symbolSize.height / 2,
                                       width: symbolSize.width, height: symbolSize.height))
            }

            // Centered on the cap height, like the badge digits.
            let lineHeight = ceil(font.ascender - font.descender)
            let titleY = rect.midY - font.capHeight / 2 + font.descender
            titleText.draw(with: NSRect(x: titleX, y: titleY, width: titleWidth, height: lineHeight),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

            if let chipText {
                let chip = NSRect(x: chipX, y: rect.midY - 6.5, width: chipWidth, height: 13)
                color.withAlphaComponent(0.15).setFill()
                NSBezierPath(roundedRect: chip, xRadius: 4, yRadius: 4).fill()
                let chipY = rect.midY - chipFont.capHeight / 2 + chipFont.descender
                chipText.draw(at: NSPoint(x: chip.minX + chipPadding, y: chipY))
            }

            color.withAlphaComponent(0.35).setFill()
            NSRect(x: separatorX, y: rect.midY - 6, width: 1, height: 12).fill()

            let body = NSRect(x: glyphX, y: rect.midY - glyphSize.height / 2,
                              width: glyphSize.width, height: glyphSize.height)
            // Same drawing as the standalone colored glyph.
            CalendarGlyph.draw(text, in: body, ink: .colored(color), progress: progress)
            return true
        }
        image.isTemplate = false
        return (image, separatorX + 0.5)
    }
}
