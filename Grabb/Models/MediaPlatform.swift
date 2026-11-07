import Foundation

enum MediaPlatform: String, Codable, CaseIterable, Identifiable, Sendable {
    case youtube
    case instagram
    case tiktok
    case vimeo
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .youtube: "YouTube"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .vimeo: "Vimeo"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .vimeo: "play.circle.fill"
        case .other: "link"
        }
    }

    static func detect(from rawURL: String) -> MediaPlatform {
        let lowered = rawURL.lowercased()
        guard let host = URL(string: lowered)?.host else {
            if lowered.contains("youtu.be") || lowered.contains("youtube") { return .youtube }
            if lowered.contains("instagram") { return .instagram }
            if lowered.contains("tiktok") { return .tiktok }
            if lowered.contains("vimeo") { return .vimeo }
            return .other
        }
        if host == "youtu.be" || host.hasSuffix(".youtube.com") || host == "youtube.com"
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
            || host == "music.youtube.com" {
            return .youtube
        }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return .instagram
        }
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") || host == "vm.tiktok.com" {
            return .tiktok
        }
        if host == "vimeo.com" || host.hasSuffix(".vimeo.com") {
            return .vimeo
        }
        return .other
    }
}

enum URLExtractor {
    /// Primeiro http(s) encontrado no texto (útil ao colar com título junto).
    static func firstHTTPURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), url.host != nil {
            return trimmed
        }
        let types = NSTextCheckingResult.CheckingType.link.rawValue
        guard let detector = try? NSDataDetector(types: types) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let match = detector.firstMatch(in: trimmed, options: [], range: range)
        guard let match, let range = Range(match.range, in: trimmed) else { return nil }
        let found = String(trimmed[range])
        guard found.lowercased().hasPrefix("http") else { return nil }
        return found
    }

    static func allHTTPURLs(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .compactMap { firstHTTPURL(in: String($0)) }
    }
}
