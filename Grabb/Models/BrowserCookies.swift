import Foundation

enum BrowserCookies: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case none
    case safari
    case brave
    case chrome
    case firefox
    case edge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: "Automatic"
        case .none: "None"
        case .safari: "Safari"
        case .brave: "Brave"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        case .edge: "Edge"
        }
    }

    /// Valor passado a `--cookies-from-browser`.
    var ytDlpName: String? {
        switch self {
        case .auto, .none: nil
        case .safari: "safari"
        case .brave: "brave"
        case .chrome: "chrome"
        case .firefox: "firefox"
        case .edge: "edge"
        }
    }

    /// Navegadores tentados em ordem quando o modo é Automático (só os instalados).
    static var automaticChain: [BrowserCookies] {
        let fm = FileManager.default
        func installed(_ app: String) -> Bool {
            fm.fileExists(atPath: "/Applications/\(app).app")
                || fm.fileExists(atPath: NSHomeDirectory() + "/Applications/\(app).app")
        }
        var chain: [BrowserCookies] = [.safari]
        if installed("Brave Browser") { chain.append(.brave) }
        if installed("Google Chrome") { chain.append(.chrome) }
        if installed("Firefox") { chain.append(.firefox) }
        if installed("Microsoft Edge") { chain.append(.edge) }
        return chain
    }
}
