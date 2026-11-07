import Foundation

@main
struct CookieSettingsTests {
    @MainActor
    static func main() {
        let suite = "Grabb.CookieSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // The existing Brave choice moves to Stories; videos stop extracting browser cookies.
        defaults.set("brave", forKey: "cookiesBrowser")
        defaults.set(true, forKey: "diagnosticLogging")
        let settings = AppSettings(defaults: defaults)
        #if DEBUG
        assert(settings.diagnosticLogging)
        #else
        assert(!settings.diagnosticLogging)
        assert(!defaults.bool(forKey: "diagnosticLogging"))
        assert(defaults.bool(forKey: "releaseDiagnosticsInitialized"))
        // Diagnostics can still be deliberately enabled later; startup must not reset it again.
        settings.diagnosticLogging = true
        assert(AppSettings(defaults: defaults).diagnosticLogging)
        #endif
        assert(settings.videoCookiesBrowser == .none)
        assert(settings.storyCookiesBrowser == .brave)
        let story = "https://www.instagram.com/stories/example/123/"
        let highlight = "https://www.instagram.com/stories/highlights/123/"
        let videos = [
            "https://www.youtube.com/watch?v=example",
            "https://youtu.be/example",
            "https://www.instagram.com/reel/example/",
            "https://www.instagram.com/p/example/",
            "https://www.tiktok.com/@example/video/123",
            "https://vimeo.com/123",
            "https://instagram.com.example.org/stories/example/123/",
        ]
        for url in videos { assert(settings.cookies(for: url) == .none) }
        for url in [story, highlight] { assert(settings.cookies(for: url) == .brave) }
        settings.storyCookiesBrowser = .safari
        assert(settings.cookies(for: videos[0]) == .none)
        settings.videoCookiesBrowser = .firefox
        assert(settings.cookies(for: story) == .safari)
        let restored = AppSettings(defaults: defaults)
        assert(restored.videoCookiesBrowser == .firefox && restored.storyCookiesBrowser == .safari)
        defaults.removePersistentDomain(forName: suite)
        defaults.set("auto", forKey: "cookiesBrowser")
        let automaticLegacy = AppSettings(defaults: defaults)
        assert(automaticLegacy.storyCookiesBrowser == .brave)
        assert(automaticLegacy.videoCookiesBrowser == .none)
        assert(YTDLPClient.cookieCandidates(for: .none, preferring: .brave) == [.none])
        print("Cookie settings: migration, persistence, URL routing and browser isolation passed")
    }
}
