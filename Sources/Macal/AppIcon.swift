import SwiftUI
import AppKit

/// The app icon, drawn in SwiftUI: calendar glyph, blue gradient.
struct AppIconView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.38, green: 0.62, blue: 0.98),
                    Color(red: 0.16, green: 0.36, blue: 0.84)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 230, style: .continuous))

            Image(systemName: "calendar")
                .font(.system(size: 520, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum AppIcon {
    /// Render the app icon as an NSImage and assign it to the running process.
    /// Visible in Notification Center, Cmd+Tab, Spotlight, etc.
    @MainActor
    static func install() {
        if let img = renderNSImage() {
            NSApplication.shared.applicationIconImage = img
        }
    }

    /// Render the app icon at 1024×1024 and save it as a PNG.
    /// Used by `make-app.sh` to generate the bundle's .icns.
    @MainActor
    static func writePNG(to path: String) -> Bool {
        guard let img = renderNSImage(),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private static func renderNSImage() -> NSImage? {
        let renderer = ImageRenderer(content: AppIconView())
        renderer.scale = 1
        return renderer.nsImage
    }
}
