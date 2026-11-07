import SwiftUI
import AppKit

/// The Grabb logo (white glyph) on an indigo rounded square.
/// Used in the bottom right corner of the app window and of the tutorial mock window.
struct LogoMark: View {
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let url = Bundle.main.url(forResource: "GrabbLogo", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .padding(size * 0.3)
        .background(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous).fill(GrabbTheme.indigo))
        .overlay(RoundedRectangle(cornerRadius: size * 0.42, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        .accessibilityHidden(true)
    }
}
