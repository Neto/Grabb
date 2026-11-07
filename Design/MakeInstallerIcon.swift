// Gives an installer file (.pkg) the app icon with a green download arrow in the top right corner.
// Usage: swift MakeInstallerIcon.swift <app-icon-1024.png> <file-to-decorate> [preview.png]
// The icon is stored in the file's resource fork. Zip with `ditto -c -k --sequesterRsrc` to keep it
// through a download; Archive Utility restores it when the buyer opens the zip.
import AppKit
import SwiftUI

/// Bold down arrow: shaft and head as one outline, in a 100 x 100 box.
struct DownArrow: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 100
        var p = Path()
        p.move(to: CGPoint(x: 36 * s, y: 6 * s))
        p.addLine(to: CGPoint(x: 64 * s, y: 6 * s))
        p.addLine(to: CGPoint(x: 64 * s, y: 48 * s))
        p.addLine(to: CGPoint(x: 90 * s, y: 48 * s))
        p.addLine(to: CGPoint(x: 50 * s, y: 94 * s))
        p.addLine(to: CGPoint(x: 10 * s, y: 48 * s))
        p.addLine(to: CGPoint(x: 36 * s, y: 48 * s))
        p.closeSubpath()
        return p
    }
}

struct InstallerIcon: View {
    let appIcon: NSImage

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 1024, height: 1024)

            ZStack {
                DownArrow()
                    .stroke(.white, style: StrokeStyle(lineWidth: 30, lineJoin: .round))
                DownArrow()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.36, green: 0.86, blue: 0.45), Color(red: 0.12, green: 0.62, blue: 0.30)],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
            .frame(width: 330, height: 330)
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .padding(.top, 40)
            .padding(.trailing, 40)
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func run() throws {
    let args = CommandLine.arguments
    guard args.count >= 3, let appIcon = NSImage(contentsOfFile: args[1]) else {
        fputs("Usage: MakeInstallerIcon.swift <app-icon-1024.png> <file> [preview.png]\n", stderr)
        exit(1)
    }
    let renderer = ImageRenderer(content: InstallerIcon(appIcon: appIcon))
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("Failed to render the installer icon") }
    let image = NSImage(cgImage: cg, size: NSSize(width: 1024, height: 1024))
    guard NSWorkspace.shared.setIcon(image, forFile: args[2], options: []) else {
        fputs("Could not set the icon on \(args[2])\n", stderr)
        exit(1)
    }
    if args.count >= 4, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) {
        try png.write(to: URL(filePath: args[3]))
    }
}

try MainActor.assumeIsolated { try run() }
