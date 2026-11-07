import AVFoundation
import CoreVideo
import Foundation
import VideoToolbox

/// Upscale after download.
/// macOS 26 or later: Apple machine learning super resolution (VideoToolbox). Needs a source up to 1920x1080.
/// Earlier macOS, or a source that is too large: ffmpeg Lanczos scaling.
enum Upscaler {
    enum Method: Sendable {
        case appleML
        case lanczos

        var label: String {
            switch self {
            case .appleML: "Apple ML"
            case .lanczos: "Lanczos"
            }
        }
    }

    enum UpscaleError: LocalizedError {
        case unreadable
        case modelDownloadFailed(String)
        case processingFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: "The video downloaded, but Grabb could not read it for upscaling."
            case .modelDownloadFailed(let message): "The upscale model could not be downloaded. \(message)"
            case .processingFailed(let message): "The upscale failed. \(message)"
            }
        }
    }

    /// Method for a source whose shorter side is `shortSide` pixels. The ML processor accepts
    /// at most 1080 pixels on the short side of a landscape video.
    static func method(forShortSide shortSide: Int) -> Method {
        if #available(macOS 26.0, *), VTSuperResolutionScalerConfiguration.isSupported, shortSide <= 1080 {
            return .appleML
        }
        return .lanczos
    }

    // MARK: - Entry point

    static func upscale(
        _ url: URL,
        toShortSide target: Int,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let probe = try await YTDLPClient.probeMedia(url)
        guard let width = probe.width, let height = probe.height, width > 0, height > 0 else {
            throw UpscaleError.unreadable
        }
        let shortSide = min(width, height)
        if shortSide >= target { return url }

        let fps = probe.fps ?? 30
        var intermediate: URL?
        var method = method(forShortSide: shortSide)
        defer { if let intermediate { try? FileManager.default.removeItem(at: intermediate) } }

        if method == .appleML, #available(macOS 26.0, *) {
            do {
                intermediate = try await MLUpscaler.run(
                    source: url,
                    width: width,
                    height: height,
                    target: target,
                    fps: fps,
                    duration: probe.duration,
                    onProgress: onProgress
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                DiagnosticLog.write("ML upscale failed, using Lanczos: \(error)")
                method = .lanczos
            }
        }

        return try await finalPass(
            original: url,
            video: intermediate,
            width: width,
            height: height,
            target: target,
            fps: fps,
            duration: probe.duration,
            method: method,
            onProgress: onProgress
        )
    }

    // MARK: - ffmpeg pass (scale, encode and mux audio)

    private static func bitrate(shortSide: Int, fps: Double) -> Int {
        let base: Int
        switch shortSide {
        case ..<800: base = 6_000_000
        case ..<1200: base = 10_000_000
        case ..<1700: base = 20_000_000
        default: base = 40_000_000
        }
        return fps > 40 ? Int(Double(base) * 1.5) : base
    }

    private static func finalPass(
        original: URL,
        video: URL?,
        width: Int,
        height: Int,
        target: Int,
        fps: Double,
        duration: Double?,
        method: Method,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        guard let ffmpeg = BinaryLocator.findFFmpeg() else { throw YTDLPError.ffmpegMissing }
        let temp = original.deletingLastPathComponent()
            .appendingPathComponent(".\(original.deletingPathExtension().lastPathComponent).grabb-up.mp4")
        try? FileManager.default.removeItem(at: temp)

        let landscape = width >= height
        let scaleFilter = landscape ? "scale=-2:\(target):flags=lanczos" : "scale=\(target):-2:flags=lanczos"

        // With a ML intermediate, check whether its short side already equals the target.
        var needsScale = true
        var inputs = ["-i", original.path]
        var maps = ["-map", "0:v:0", "-map", "0:a:0?"]
        if let video {
            let mlProbe = try? await YTDLPClient.probeMedia(video)
            if let w = mlProbe?.width, let h = mlProbe?.height, min(w, h) == target { needsScale = false }
            inputs = ["-i", video.path, "-i", original.path]
            maps = ["-map", "0:v:0", "-map", "1:a:0?"]
        }

        let detail = method == .appleML ? "Finishing upscale…" : "Upscaling with Lanczos…"
        let encodeVideo = ["-vf", scaleFilter, "-c:v", "h264_videotoolbox", "-b:v", "\(bitrate(shortSide: target, fps: fps))", "-allow_sw", "1", "-tag:v", "avc1"]
        let softwareVideo = ["-vf", scaleFilter, "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]
        let copyVideo = ["-c:v", "copy"]

        func run(video: [String]) async throws -> YTDLPClientRunResult {
            try await YTDLPClient.run(
                binary: ffmpeg,
                arguments: ["-y"] + inputs + maps + video + ["-c:a", "copy", "-movflags", "+faststart", "-progress", "pipe:1", "-nostats", temp.path],
                timeout: nil,
                onLine: { line in
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("out_time_us="), let duration, duration > 0,
                          let value = Double(trimmed.dropFirst("out_time_us=".count)) else { return }
                    onProgress(
                        DownloadProgress(
                            fraction: min(max(value / (duration * 1_000_000), 0), 1),
                            speed: nil,
                            eta: nil,
                            isProcessing: true,
                            destinationPath: temp.path,
                            detail: detail
                        )
                    )
                }
            )
        }

        var result = try await run(video: needsScale ? encodeVideo : copyVideo)
        if result.status != 0, needsScale {
            result = try await run(video: softwareVideo)
        }
        if result.status != 0 {
            try? FileManager.default.removeItem(at: temp)
            throw UpscaleError.processingFailed("ffmpeg stopped with status \(result.status).")
        }

        let replacement = original.deletingPathExtension().appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: replacement.path) {
            try FileManager.default.removeItem(at: replacement)
        }
        try FileManager.default.moveItem(at: temp, to: replacement)
        if original != replacement, FileManager.default.fileExists(atPath: original.path) {
            try? FileManager.default.removeItem(at: original)
        }
        return replacement
    }
}

// MARK: - Apple ML super resolution (macOS 26 or later)

@available(macOS 26.0, *)
private enum MLUpscaler {
    /// Writes a video only file whose frames are enlarged by the ML processor. Returns its URL.
    static func run(
        source: URL,
        width: Int,
        height: Int,
        target: Int,
        fps: Double,
        duration: Double?,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let shortSide = min(width, height)
        let factors = (VTSuperResolutionScalerConfiguration.__supportedScaleFactors).map(\.intValue).sorted()
        guard let maxFactor = factors.last else { throw Upscaler.UpscaleError.processingFailed("No scale factor.") }
        let factor = factors.first { shortSide * $0 >= target } ?? maxFactor

        guard let config = VTSuperResolutionScalerConfiguration(
            frameWidth: width,
            frameHeight: height,
            scaleFactor: factor,
            inputType: .video,
            usePrecomputedFlow: false,
            qualityPrioritization: .normal,
            revision: VTSuperResolutionScalerConfiguration.defaultRevision
        ) else {
            throw Upscaler.UpscaleError.processingFailed("The processor does not accept \(width)x\(height).")
        }

        try await ensureModel(config, onProgress: onProgress)

        let outWidth = width * factor
        let outHeight = height * factor
        let temp = source.deletingLastPathComponent()
            .appendingPathComponent(".\(source.deletingPathExtension().lastPathComponent).grabb-ml.mp4")
        try? FileManager.default.removeItem(at: temp)

        // Reader
        let asset = AVURLAsset(url: source)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw Upscaler.UpscaleError.unreadable
        }
        let transform = try await track.load(.preferredTransform)
        let reader = try AVAssetReader(asset: asset)
        let formats = config.__frameSupportedPixelFormats.map(\.uint32Value)
        guard let format = formats.first else { throw Upscaler.UpscaleError.processingFailed("No pixel format.") }
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: format]
        )
        readerOutput.alwaysCopiesSampleData = false
        reader.add(readerOutput)

        // Writer
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        let bitrate = min(Int(Double(outWidth * outHeight) * max(fps, 24) * 0.12), 80_000_000)
        let writerInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: outWidth,
                AVVideoHeightKey: outHeight,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
            ]
        )
        writerInput.transform = transform
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: nil)
        writer.add(writerInput)

        // Destination pool
        var poolAttributes = config.destinationPixelBufferAttributes
        poolAttributes[kCVPixelBufferWidthKey as String] = outWidth
        poolAttributes[kCVPixelBufferHeightKey as String] = outHeight
        if poolAttributes[kCVPixelBufferPixelFormatTypeKey as String] == nil {
            poolAttributes[kCVPixelBufferPixelFormatTypeKey as String] = format
        }
        var poolOut: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, poolAttributes as CFDictionary, &poolOut)
        guard let pool = poolOut else { throw Upscaler.UpscaleError.processingFailed("No buffer pool.") }

        let processor = VTFrameProcessor()
        try processor.startSession(configuration: config)
        defer { processor.endSession() }

        guard reader.startReading() else {
            throw Upscaler.UpscaleError.processingFailed(reader.error?.localizedDescription ?? "Reader failed.")
        }
        guard writer.startWriting() else {
            throw Upscaler.UpscaleError.processingFailed(writer.error?.localizedDescription ?? "Writer failed.")
        }
        writer.startSession(atSourceTime: .zero)

        var previousSource: VTFrameProcessorFrame?
        var previousOutput: VTFrameProcessorFrame?
        var firstPTS: CMTime?

        while let sample = readerOutput.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let sourceBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if firstPTS == nil { firstPTS = pts }
            let relative = CMTimeSubtract(pts, firstPTS ?? .zero)

            var destBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destBuffer)
            guard let destBuffer else { throw Upscaler.UpscaleError.processingFailed("No output buffer.") }

            guard
                let sourceFrame = VTFrameProcessorFrame(buffer: sourceBuffer, presentationTimeStamp: pts),
                let destFrame = VTFrameProcessorFrame(buffer: destBuffer, presentationTimeStamp: pts),
                let parameters = VTSuperResolutionScalerParameters(
                    sourceFrame: sourceFrame,
                    previousFrame: previousSource,
                    previousOutputFrame: previousOutput,
                    opticalFlow: nil,
                    submissionMode: .sequential,
                    destinationFrame: destFrame
                )
            else {
                throw Upscaler.UpscaleError.processingFailed("Frame setup failed.")
            }

            _ = try await processor.process(parameters: parameters)

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(4))
            }
            if !adaptor.append(destBuffer, withPresentationTime: relative) {
                throw Upscaler.UpscaleError.processingFailed(writer.error?.localizedDescription ?? "Write failed.")
            }
            previousSource = sourceFrame
            previousOutput = destFrame

            if let duration, duration > 0 {
                onProgress(
                    DownloadProgress(
                        fraction: min(max(relative.seconds / duration, 0), 1) * 0.9,
                        speed: nil,
                        eta: nil,
                        isProcessing: true,
                        destinationPath: temp.path,
                        detail: "Upscaling with Apple ML…"
                    )
                )
            }
        }

        if reader.status == .failed {
            throw Upscaler.UpscaleError.processingFailed(reader.error?.localizedDescription ?? "Read failed.")
        }
        writerInput.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed {
            throw Upscaler.UpscaleError.processingFailed(writer.error?.localizedDescription ?? "Write failed.")
        }
        return temp
    }

    private static func ensureModel(
        _ config: VTSuperResolutionScalerConfiguration,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws {
        if config.configurationModelStatus == .ready { return }

        let poll = Task {
            while !Task.isCancelled {
                onProgress(
                    DownloadProgress(
                        fraction: Double(config.configurationModelPercentageAvailable),
                        speed: nil,
                        eta: nil,
                        isProcessing: true,
                        destinationPath: nil,
                        detail: "Downloading the upscale model…"
                    )
                )
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        defer { poll.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            config.downloadConfigurationModel { error in
                if let error {
                    continuation.resume(throwing: Upscaler.UpscaleError.modelDownloadFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
