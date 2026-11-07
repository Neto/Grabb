import Foundation

enum JobStatus: Equatable, Sendable {
    case fetchingInfo
    case downloading(fraction: Double?, speed: String?, eta: String?)
    case processing(fraction: Double?)
    case completed
    case failed(String)
    case cancelled

    var isActive: Bool {
        switch self {
        case .fetchingInfo, .downloading, .processing: true
        default: false
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: true
        default: false
        }
    }
}

struct DownloadJob: Identifiable, Equatable, Sendable {
    let id: UUID
    var sourceURL: String
    var platform: MediaPlatform
    var quality: VideoQuality
    var status: JobStatus
    var info: VideoInfo?
    var outputURL: URL?
    var statusDetail: String?
    var createdAt: Date
    var finishedAt: Date?

    var title: String {
        info?.title ?? sourceURL
    }

    init(
        id: UUID = UUID(),
        sourceURL: String,
        platform: MediaPlatform,
        quality: VideoQuality,
        status: JobStatus = .fetchingInfo,
        info: VideoInfo? = nil,
        outputURL: URL? = nil,
        createdAt: Date = .now,
        finishedAt: Date? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.platform = platform
        self.quality = quality
        self.status = status
        self.info = info
        self.outputURL = outputURL
        self.statusDetail = nil
        self.createdAt = createdAt
        self.finishedAt = finishedAt
    }
}

struct DownloadProgress: Sendable, Equatable {
    /// nil quando o yt-dlp não sabe o tamanho total (CDN sem Content-Length, comum no Instagram/TikTok).
    var fraction: Double?
    var speed: String?
    var eta: String?
    var isProcessing: Bool
    var destinationPath: String?
    var detail: String? = nil
}
