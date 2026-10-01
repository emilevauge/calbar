import AppKit
import CalbarCore

/// Menu bar glyph: a small calendar page (outline plus header band) with the
/// countdown inside. Every state keeps that shape, only the color changes.
/// - normal countdown: template image so macOS tints it for light and dark
///   menu bars. Empty page for `.none`.
/// - warning: filled template glyph with "!" punched out.
/// - soon (join window): orange outline, band and digits.
/// - imminent (1 min or less): red outline, band and digits.
/// - in a meeting (live or not): page filling up left to right with the
///   meeting, minutes left in it, and a red glow around it, like an "on
///   air" sign. The glow needs color, so the page is drawn in the menu bar
///   ink (black or white) rather than as a template.
/// Colored states are not templates. With a joinable meeting the glyph
/// sits inside the capsule drawn by `StatusItemImage` instead.
enum StatusBarImage {
    /// `dark`: the menu bar is dark, for the ink of the glowing page.
    static func make(_ badge: MenuBarBadge, dark: Bool) -> NSImage {
        switch badge {
        case .live, .inMeeting:
            return onAir(badge, ink: dark ? .white : .black)
        default:
            break
        }
        let color: NSColor? = switch badge {
        case .countdown(_, .soon): .systemOrange
        case .countdown(_, .imminent): .systemRed
        case .countdown(_, .normal), .live, .inMeeting, .warning, .none: nil
        }
        let ink: CalendarGlyph.Ink
        if let color {
            ink = .colored(color)
        } else if case .warning = badge {
            ink = .punched
        } else {
            ink = .template
        }
        let image = NSImage(size: NSSize(width: 20, height: 18), flipped: false) { _ in
            CalendarGlyph.draw(badge.text, in: CalendarGlyph.standardBody, ink: ink, progress: badge.progress)
        }
        image.isTemplate = color == nil
        return image
    }

    /// Room for the glow on each side of the page.
    static let glowMargin: CGFloat = 2

    private static func onAir(_ badge: MenuBarBadge, ink: NSColor) -> NSImage {
        let size = NSSize(width: 20 + 2 * glowMargin, height: 18)
        let body = CalendarGlyph.standardBody.offsetBy(dx: glowMargin, dy: 0)
        let image = NSImage(size: size, flipped: false) { _ in
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.systemRed.withAlphaComponent(0.95)
            shadow.shadowBlurRadius = 3.2
            shadow.shadowOffset = .zero
            shadow.set()
            let ring = NSBezierPath(roundedRect: body.insetBy(dx: -0.6, dy: -0.6), xRadius: 3.6, yRadius: 3.6)
            ring.lineWidth = 1.4
            NSColor.systemRed.setStroke()
            // Twice: one pass of the shadow is too faint at this size.
            ring.stroke()
            ring.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return CalendarGlyph.draw(badge.text, in: body, ink: .ink(ink), progress: badge.progress)
        }
        image.isTemplate = false
        return image
    }
}

/// Drawing of the calendar page, shared by the plain glyph and the capsule.
enum CalendarGlyph {
    enum Ink {
        /// Black outline, band and text, for a template image.
        case template
        /// Filled black page with the text punched out, for a template image.
        case punched
        /// Colored outline, band and text, no background.
        case colored(NSColor)
        /// Like `.template`, in a given color, for a non-template image.
        case ink(NSColor)
    }

    /// Page rectangle in the 20 x 18 pt standalone image.
    static let standardBody = NSRect(x: 2, y: 1.5, width: 16, height: 14.5)

    /// Draws into the current graphics context. `body` sets the scale: the
    /// radius, band and font follow its height. `progress`, from 0 to 1,
    /// fills the page under the band from the left, in a light tint of the
    /// ink, behind the text.
    @discardableResult
    static func draw(_ text: String, in body: NSRect, ink: Ink, progress: Double? = nil) -> Bool {
        let scale = body.height / standardBody.height
        let outline = NSBezierPath(roundedRect: body, xRadius: 3.2 * scale, yRadius: 3.2 * scale)
        let color: NSColor = switch ink {
        case .template, .punched: .black
        case .colored(let c), .ink(let c): c
        }

        var textArea = body
        if let progress, progress > 0 {
            if case .punched = ink {} else {
                NSGraphicsContext.saveGraphicsState()
                outline.addClip()
                color.withAlphaComponent(0.28).setFill()
                NSRect(x: body.minX, y: body.minY, width: body.width * min(progress, 1), height: body.height).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        if case .punched = ink {
            color.setFill()
            outline.fill()
        } else {
            color.set()
            // A slightly heavier stroke keeps the colored page visible
            // without a background.
            if case .colored = ink {
                outline.lineWidth = 1.6
            } else {
                outline.lineWidth = 1.3
            }
            outline.stroke()
            // Header band of the calendar page.
            let bandHeight = 3.5 * scale
            let band = NSRect(x: body.minX, y: body.maxY - bandHeight, width: body.width, height: bandHeight)
            NSBezierPath(roundedRect: band, xRadius: 1.5 * scale, yRadius: 1.5 * scale).fill()
            textArea.size.height -= bandHeight
        }

        guard !text.isEmpty else { return true }
        // Shrink the font until the text fits with a margin: "2h" is
        // wider than two digits, "12h" wider still.
        let maxWidth = body.width - 4 * scale
        var size = (9.5 * scale * 2).rounded() / 2
        var font: NSFont
        var line: CTLine
        var width: Double
        repeat {
            font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
            line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
            width = CTLineGetTypographicBounds(line, nil, nil, nil)
            size -= 0.5
        } while width > maxWidth && size >= 6
        // Center the digits on their cap height, not on the line box,
        // which adds the descender and puts the digits too high.
        let baseline = textArea.midY - font.capHeight / 2
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        context.saveGState()
        defer { context.restoreGState() }
        if case .punched = ink {
            // Punch the digits out of the filled template glyph.
            context.setBlendMode(.destinationOut)
        }
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: textArea.midX - width / 2, y: baseline)
        CTLineDraw(line, context)
        return true
    }
}
