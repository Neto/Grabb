import Foundation

enum VideoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case best
    case p2160
    case p2160p30
    case p1440
    case p1440p30
    case p1080
    case p720
    case p480
    case audioOnly
    case up720
    case up1080
    case up1440
    case up2160

    var id: String { rawValue }

    var title: String {
        switch self {
        case .best: "Best quality"
        case .p2160: "2160p (4K)"
        case .p2160p30: "2160p 30fps"
        case .p1440: "1440p (2K)"
        case .p1440p30: "1440p 30fps"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .audioOnly: "Audio only (MP3)"
        case .up720: "Upscale to 720p"
        case .up1080: "Upscale to 1080p"
        case .up1440: "Upscale to 1440p"
        case .up2160: "Upscale to 2160p (4K)"
        }
    }

    /// Altura máxima do tier, ou nil para `.best`/`.audioOnly`.
    var height: Int? {
        switch self {
        case .p2160, .p2160p30, .up2160: 2160
        case .p1440, .p1440p30, .up1440: 1440
        case .p1080, .up1080: 1080
        case .p720, .up720: 720
        case .p480: 480
        case .best, .audioOnly: nil
        }
    }

    /// Fps forçado na reconversão pós-download (quando ela for necessária); nil mantém o fps original.
    var targetFPS: Int? {
        switch self {
        case .p2160p30, .p1440p30: 30
        default: nil
        }
    }

    /// Variante "30fps" do tier, se houver.
    private var thirtyFPSVariant: VideoQuality? {
        switch self {
        case .p2160: .p2160p30
        case .p1440: .p1440p30
        default: nil
        }
    }

    /// Seletor do yt-dlp. A resolução manda; o `-S` (ver YTDLPClient) escolhe H.264
    /// quando ele existir naquela resolução, senão cai no melhor disponível e o app reconverte.
    var ytDlpFormat: String {
        switch self {
        case .audioOnly:
            "bestaudio/best"
        case .up720, .up1080, .up1440, .up2160:
            Self.mp4Format(maxHeight: nil)
        default:
            Self.mp4Format(maxHeight: height)
        }
    }

    /// Tag curta pro nome do arquivo — sem isso, baixar o mesmo vídeo em duas qualidades
    /// diferentes gera o mesmo nome; o yt-dlp vê que já existe e pula o download de novo.
    var fileTag: String {
        switch self {
        case .best: "best"
        case .p2160: "2160p"
        case .p2160p30: "2160p30"
        case .p1440: "1440p"
        case .p1440p30: "1440p30"
        case .p1080: "1080p"
        case .p720: "720p"
        case .p480: "480p"
        case .audioOnly: "audio"
        case .up720: "up720"
        case .up1080: "up1080"
        case .up1440: "up1440"
        case .up2160: "up2160"
        }
    }

    var extractsAudio: Bool { self == .audioOnly }

    /// True for the options that enlarge the video after download.
    var isUpscale: Bool {
        switch self {
        case .up720, .up1080, .up1440, .up2160: true
        default: false
        }
    }

    /// Qualities that the settings and the generic fallback list show.
    static var standardCases: [VideoQuality] { allCases.filter { !$0.isUpscale } }

    private static let upscaleTiers: [VideoQuality] = [.up720, .up1080, .up1440, .up2160]

    /// Upscale targets: every tier above the best resolution the video has.
    static func upscaleOptions(forMaxHeight maxHeight: Int) -> [VideoQuality] {
        upscaleTiers.filter { ($0.height ?? 0) > maxHeight }
    }

    var prefersQuickTime: Bool { !extractsAudio }

    /// Pra vídeo vertical (Reels, Stories, TikTok, Shorts), o `height` do yt-dlp é o lado maior
    /// (ex: 1920 numa resolução "1080p" vertical), não bate com os tiers aqui. Tenta por altura
    /// primeiro (vídeo horizontal) e cai pra largura (vídeo vertical) se nada bater.
    private static func mp4Format(maxHeight: Int?) -> String {
        guard let h = maxHeight else { return "bv*+ba/b" }
        return "bv*[height<=\(h)]+ba/b[height<=\(h)]/bv*[width<=\(h)]+ba/b[width<=\(h)]"
    }

    /// Tiers de resolução, da maior para a menor.
    private static let resolutionTiers: [VideoQuality] = [.p2160, .p1440, .p1080, .p720, .p480]

    /// Opções a mostrar no seletor, dado o maior height encontrado e os heights com fps > 30.
    static func options(forMaxHeight maxHeight: Int, highFPSHeights: Set<Int> = []) -> [VideoQuality] {
        var result: [VideoQuality] = [.best]
        for tier in resolutionTiers where (tier.height ?? 0) <= maxHeight {
            result.append(tier)
            if let height = tier.height, highFPSHeights.contains(height), let p30 = tier.thirtyFPSVariant {
                result.append(p30)
            }
        }
        result.append(.audioOnly)
        return result
    }

    /// Tier mais próximo (por baixo) do maior height H.264 encontrado.
    static func bestH264Tier(forHeight height: Int) -> VideoQuality {
        resolutionTiers.first { ($0.height ?? 0) <= height } ?? .p480
    }
}
