import AppKit
import MacalCore
import UserNotifications

/// Square badge of a video provider, for the notification thumbnail: the
/// provider's color with a white mark. Drawn in code, not copied logos.
enum ProviderBadge {
    static let size: CGFloat = 128

    static func color(_ provider: MeetingLink.Provider) -> NSColor {
        switch provider {
        case .zoom: NSColor(srgbRed: 0.18, green: 0.55, blue: 1.00, alpha: 1)
        case .meet: NSColor(srgbRed: 0.00, green: 0.62, blue: 0.33, alpha: 1)
        case .teams: NSColor(srgbRed: 0.36, green: 0.37, blue: 0.78, alpha: 1)
        case .webex: NSColor(srgbRed: 0.00, green: 0.55, blue: 0.68, alpha: 1)
        case .around: NSColor(srgbRed: 0.93, green: 0.33, blue: 0.38, alpha: 1)
        case .whereby: NSColor(srgbRed: 0.98, green: 0.58, blue: 0.13, alpha: 1)
        case .other: NSColor(srgbRed: 0.45, green: 0.47, blue: 0.52, alpha: 1)
        }
    }

    static func image(_ provider: MeetingLink.Provider) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color(provider).setFill()
            NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
            if provider == .teams {
                // A bold "T", the usual mark of Teams.
                let font = NSFont.systemFont(ofSize: size * 0.62, weight: .heavy)
                let text = NSAttributedString(string: "T", attributes: [.font: font, .foregroundColor: NSColor.white])
                let w = text.size().width
                text.draw(at: NSPoint(x: rect.midX - w / 2, y: rect.midY - font.capHeight / 2 + font.descender))
            } else {
                let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
                    .applying(.init(paletteColors: [.white]))
                if let symbol = NSImage(systemSymbolName: "video.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(config) {
                    let s = symbol.size
                    symbol.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2,
                                           width: s.width, height: s.height))
                }
            }
            return true
        }
    }

    /// A fresh PNG for each notification: the system moves the file into
    /// its own store once the notification is added.
    static func attachment(_ provider: MeetingLink.Provider) -> UNNotificationAttachment? {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image(provider).draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macal-\(provider.rawValue)-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: provider.rawValue, url: url, options: nil)
        } catch {
            NSLog("Macal: notification badge: %@", "\(error)")
            return nil
        }
    }
}
