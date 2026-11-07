import AppKit
import Foundation

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var buildStamp: String {
        guard
            let url = Bundle.main.executableURL,
            let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else {
            return "unknown"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    static var full: String { "\(marketing) (\(build)) — \(buildStamp)" }

    @MainActor
    static func showAboutPanel() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .applicationName: "Grabb",
            .applicationVersion: marketing,
            .version: "Build \(build) — \(buildStamp)",
            .credits: NSAttributedString(
                string: "Downloads videos from a URL with yt-dlp.\nUse it only with content that you have the right to download."
            ),
        ])
    }
}
