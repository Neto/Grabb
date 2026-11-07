import Foundation

@Observable
@MainActor
final class AppSettings {
    var diagnosticLogging: Bool {
        didSet { defaults.set(diagnosticLogging, forKey: "diagnosticLogging") }
    }

    var defaultQuality: VideoQuality {
        didSet { defaults.set(defaultQuality.rawValue, forKey: Keys.quality) }
    }

    var videoCookiesBrowser: BrowserCookies {
        didSet { defaults.set(videoCookiesBrowser.rawValue, forKey: Keys.videoCookies) }
    }

    var storyCookiesBrowser: BrowserCookies {
        didSet { defaults.set(storyCookiesBrowser.rawValue, forKey: Keys.storyCookies) }
    }

    var openWhenDone: Bool {
        didSet { defaults.set(openWhenDone, forKey: Keys.openWhenDone) }
    }

    var revealWhenDone: Bool {
        didSet { defaults.set(revealWhenDone, forKey: Keys.revealWhenDone) }
    }

    var customYTDLPPath: String {
        didSet { defaults.set(customYTDLPPath, forKey: Keys.ytDlpPath) }
    }

    /// Pasta de destino. `nil` = Pasta Downloads do usuário.
    var outputFolderPath: String {
        didSet { defaults.set(outputFolderPath, forKey: Keys.outputFolder) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let quality = "defaultQuality"
        static let videoCookies = "videoCookiesBrowser"
        static let storyCookies = "storyCookiesBrowser"
        static let legacyCookies = "cookiesBrowser"
        static let openWhenDone = "openWhenDone"
        static let revealWhenDone = "revealWhenDone"
        static let ytDlpPath = "customYTDLPPath"
        static let outputFolder = "outputFolderPath"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if !DEBUG
        // A primeira Release desliga o verbose herdado dos testes; depois respeita a escolha do usuário.
        if !defaults.bool(forKey: "releaseDiagnosticsInitialized") {
            defaults.set(false, forKey: "diagnosticLogging")
            defaults.set(true, forKey: "releaseDiagnosticsInitialized")
        }
        #endif
        diagnosticLogging = defaults.object(forKey: "diagnosticLogging") as? Bool ?? DiagnosticLog.defaultEnabled
        let qualityRaw = defaults.string(forKey: Keys.quality) ?? VideoQuality.best.rawValue
        defaultQuality = VideoQuality(rawValue: qualityRaw) ?? .best
        videoCookiesBrowser = defaults.string(forKey: Keys.videoCookies).flatMap(BrowserCookies.init(rawValue:)) ?? .none
        let legacy = defaults.string(forKey: Keys.legacyCookies).flatMap(BrowserCookies.init(rawValue:))
        let story = defaults.string(forKey: Keys.storyCookies).flatMap(BrowserCookies.init(rawValue:)) ?? legacy ?? .brave
        storyCookiesBrowser = story.ytDlpName != nil ? story : .brave
        openWhenDone = defaults.object(forKey: Keys.openWhenDone) as? Bool ?? false
        revealWhenDone = defaults.object(forKey: Keys.revealWhenDone) as? Bool ?? true
        customYTDLPPath = defaults.string(forKey: Keys.ytDlpPath) ?? ""
        outputFolderPath = defaults.string(forKey: Keys.outputFolder) ?? ""
        // Migra a seleção antiga para Stories; vídeos começam sem extrair cookies.
        defaults.set(videoCookiesBrowser.rawValue, forKey: Keys.videoCookies)
        defaults.set(storyCookiesBrowser.rawValue, forKey: Keys.storyCookies)
    }

    func cookies(for url: String) -> BrowserCookies {
        YTDLPClient.isInstagramStoryURL(url) ? storyCookiesBrowser : videoCookiesBrowser
    }

    var resolvedOutputFolder: URL {
        if !outputFolderPath.isEmpty {
            return URL(fileURLWithPath: outputFolderPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Downloads", isDirectory: true)
    }
}
