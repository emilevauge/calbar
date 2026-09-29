import SwiftUI

/// Google Calendar mark in the style of the SF Symbols around it: page
/// outline, filled header band and "31", all in the current foreground
/// style, so it tints like the other footer and detail icons.
struct GoogleCalendarIcon: View {
    var size: CGFloat = 16

    var body: some View {
        let radius = size * 0.2
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        // Stroke close to an SF Symbol at medium weight.
        let line = max(1, size * 0.09)
        // Whole points keep the band edge sharp at small sizes.
        let bandHeight = max(2, (size * 0.24).rounded())

        let glyph = ZStack(alignment: .top) {
            UnevenRoundedRectangle(
                topLeadingRadius: radius, bottomLeadingRadius: 0,
                bottomTrailingRadius: 0, topTrailingRadius: radius,
                style: .continuous
            )
            .frame(height: bandHeight)
            Text("31")
                .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .kerning(-size * 0.02)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, bandHeight * 0.8)
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(lineWidth: line))

        // One layer: the translucent secondary style would otherwise darken
        // where the band and the outline overlap.
        Rectangle()
            .fill(ForegroundStyle())
            .frame(width: size, height: size)
            .mask(glyph)
            .accessibilityHidden(true)
    }
}
