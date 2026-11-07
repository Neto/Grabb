import Foundation

/// Um link já baixado. Fica salvo em disco para permitir baixar de novo.
struct HistoryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var sourceURL: String
    var title: String
    var platform: MediaPlatform
    var quality: VideoQuality
    var uploader: String?
    var thumbnailURL: URL?
    var outputPath: String?
    var firstDownloadedAt: Date
    var lastDownloadedAt: Date
    var downloadCount: Int

    var fileExists: Bool {
        guard let outputPath else { return false }
        return FileManager.default.fileExists(atPath: outputPath)
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case downloads
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .history: "History"
        }
    }
}
