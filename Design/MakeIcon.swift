// Generates the Grabb app icon in the same style as Spin: a thin neon
// download arrow and tray on a dark squircle.
// Usage: swift Design/MakeIcon.swift <output-folder>
// Writes AppIconSource.png (1024 x 1024). Then run scripts/generate_app_icon.swift.
import SwiftUI

/// Download arrow landing in a tray, drawn on the 1024-point icon canvas.
struct DownloadGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // Arrow shaft
        p.move(to: CGPoint(x: 512, y: 318))
        p.addLine(to: CGPoint(x: 512, y: 600))
        // Arrow head
        p.move(to: CGPoint(x: 398, y: 488))
        p.addLine(to: CGPoint(x: 512, y: 602))
        p.addLine(to: CGPoint(x: 626, y: 488))
        // Tray
        p.move(to: CGPoint(x: 330, y: 596))
        p.addLine(to: CGPoint(x: 330, y: 662))
        p.addQuadCurve(to: CGPoint(x: 370, y: 702), control: CGPoint(x: 330, y: 702))
        p.addLine(to: CGPoint(x: 654, y: 702))
        p.addQuadCurve(to: CGPoint(x: 694, y: 662), control: CGPoint(x: 694, y: 702))
        p.addLine(to: CGPoint(x: 694, y: 596))
        return p
    }
}

struct IconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.16), Color(white: 0.05)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .strokeBorder(.white.opacity(0.08), lineWidth: 3)
                .frame(width: 824, height: 824)

            let neon = AngularGradient(
                colors: [.pink, .purple, .blue, .cyan, .green, .yellow, .orange, .pink],
                center: UnitPoint(x: 0.5, y: 0.5)
            )
            let glyph = DownloadGlyph()
            glyph
                .stroke(neon, style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round))
                .blur(radius: 28)
                .opacity(0.9)
            glyph
                .stroke(neon, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                .blur(radius: 6)
            glyph
                .stroke(neon, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            glyph
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 1024, height: 1024)
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }
}

@MainActor
func render() throws {
    let out = URL(filePath: CommandLine.arguments[1])
    let renderer = ImageRenderer(content: IconArt())
    renderer.scale = 1
    guard let image = renderer.cgImage else { fatalError("Failed to render the icon") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("Failed to encode PNG") }
    try png.write(to: out.appending(path: "AppIconSource.png"))
}

try MainActor.assumeIsolated { try render() }
