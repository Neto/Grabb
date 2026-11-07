import Foundation

enum YTDLPError: LocalizedError, Sendable {
    case binaryMissing
    case ffmpegMissing
    case invalidURL
    case cancelled
    case badJSON
    case timeout
    case failed(status: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            "The download components are missing from this app. Reinstall Grabb."
        case .ffmpegMissing:
            "The video converter is missing from this app. Reinstall Grabb."
        case .invalidURL:
            "Invalid URL."
        case .cancelled:
            "Download canceled."
        case .badJSON:
            "Could not read the video information."
        case .timeout:
            "yt-dlp took too long to respond. Try again."
        case .failed(_, let message):
            message
        }
    }
}

enum YTDLPClient: Sendable {
    private static let infoJSONFields =
        "%(.{id,title,thumbnail,duration,uploader,channel,webpage_url,original_url,extractor,extractor_key,formats})j"

    static let loginMessage =
        "This link needs a login. Sign in to your account in Safari or Chrome (Grabb uses the browser cookies automatically). Then try again."
    static let permissionMessage =
        "Grabb could not read the browser cookies. Open System Settings > Privacy & Security > Full Disk Access, turn on Grabb, and try again."

    /// Carrega cookies com o mesmo helper do download, mas usa um extrator local sem rede.
    static func checkInstagramSession(customBinary: String, cookies: BrowserCookies) async throws -> String {
        guard let browser = cookies.ytDlpName else {
            return "Select a browser in General → Cookies for Instagram Stories."
        }
        guard let plugins = Bundle.main.url(forResource: "Diagnostics", withExtension: nil) else {
            throw YTDLPError.failed(status: -1, message: "Local diagnostics component is missing.")
        }
        let result = try await run(
            binary: requireBinary(customPath: customBinary),
            arguments: [
                "--ignore-config", "--no-update", "--no-colors", "--verbose",
                "--no-plugin-dirs", "--plugin-dirs", plugins.path,
                "--use-extractors", "grabb:session",
                "--simulate", "--retries", "0", "--extractor-retries", "0",
                "--cookies-from-browser", browser,
                "grabb:instagram-session",
            ],
            timeout: .seconds(45),
            onLine: { _ in }
        )
        guard result.status == 0 else {
            throw YTDLPError.failed(status: result.status, message: "Local cookie check failed. See the new diagnostic log.")
        }
        let lines = result.log.split(whereSeparator: \.isNewline)
            .filter { $0.contains("[session-check]") }
            .map { line in
                String(line[line.range(of: "[session-check]")!.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        guard !lines.isEmpty else {
            throw YTDLPError.failed(status: -1, message: "Local diagnostics did not return a session report.")
        }
        return lines.joined(separator: "\n")
    }

    /// `preferring`: navegador que funcionou da última vez — tentado primeiro no modo
    /// Automático, pra não repetir a cadeia inteira (none/safari/chrome/firefox/edge) sempre.
    static func cookieCandidates(for cookies: BrowserCookies, preferring preferred: BrowserCookies? = nil) -> [BrowserCookies] {
        guard cookies == .auto else { return [cookies] }
        var chain = [.none] + BrowserCookies.automaticChain
        if let preferred, let index = chain.firstIndex(of: preferred), index != 0 {
            chain.remove(at: index)
            chain.insert(preferred, at: 0)
        }
        return chain
    }

    private static func needsAnotherBrowser(_ error: YTDLPError) -> Bool {
        if case .failed(_, let message) = error {
            return message == loginMessage || message == permissionMessage
        }
        return false
    }

    /// Prefere o erro de permissão (acionável); senão o primeiro.
    private static func pickError(_ errors: [Error]) -> Error {
        for case let error as YTDLPError in errors {
            if case .failed(_, let message) = error, message == permissionMessage { return error }
        }
        return errors.first ?? YTDLPError.invalidURL
    }

    static func fetchInfo(
        url: String,
        customBinary: String,
        cookies: BrowserCookies,
        preferringCookies preferred: BrowserCookies? = nil,
        onLine: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> VideoInfo {
        var errors: [Error] = []
        for candidate in candidateURLs(for: url) {
            for cookie in cookieCandidates(for: cookies, preferring: preferred) {
                if cookie != .none, cookies == .auto {
                    onLine("Trying with \(cookie.title) cookies…")
                }
                do {
                    var info = try await fetchInfoOnce(
                        url: candidate,
                        customBinary: customBinary,
                        cookies: cookie,
                        onLine: onLine
                    )
                    if candidate != url, info.webpageURL == candidate { info.webpageURL = url }
                    info.resolvedCookies = cookie
                    return info
                } catch let error as YTDLPError {
                    if case .cancelled = error { throw error }
                    errors.append(error)
                    if !needsAnotherBrowser(error) { break }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    errors.append(error)
                    break
                }
            }
        }
        throw pickError(errors)
    }

    private static func fetchInfoOnce(
        url: String,
        customBinary: String,
        cookies: BrowserCookies,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> VideoInfo {
        let binary = try requireBinary(customPath: customBinary)
        var arguments = try baseArguments(cookies: cookies, url: url)
        arguments += ["--skip-download"]
        if isInstagramStoryURL(url) { arguments += ["--no-playlist"] }
        if MediaPlatform.detect(from: url) == .instagram {
            // Sem --no-playlist, pra pegar de uma vez todos os itens de um carrossel; posts de foto
            // não têm formato de vídeo nenhum e o yt-dlp trata isso como erro sem essa flag.
            arguments += ["--ignore-no-formats-error"]
        } else {
            arguments += ["--no-playlist"]
        }
        arguments += [
            "--print", infoJSONFields,
            url,
        ]

        let result = try await run(
            binary: binary,
            arguments: arguments,
            timeout: .seconds(90),
            onLine: onLine
        )
        if result.status != 0 {
            DiagnosticLog.write("fetchInfo cookies=\(cookies.rawValue) url=\(url) status=\(result.status) log=\(result.log)")
            throw YTDLPError.failed(status: result.status, message: friendlyMessage(from: result.log, url: url))
        }
        let dtos = try parseInfoDTOs(from: result.stdout)
        return VideoInfo.build(from: dtos, fallbackURL: url)
    }

    /// Um JSON por linha; mais de uma linha quando --print roda pra cada item de um carrossel.
    private static func parseInfoDTOs(from stdout: String) throws -> [YTDLPInfoDTO] {
        var dtos: [YTDLPInfoDTO] = []
        for line in stdout.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { continue }
            if let dto = try? JSONDecoder().decode(YTDLPInfoDTO.self, from: data) {
                dtos.append(dto)
            }
        }
        guard !dtos.isEmpty else { throw YTDLPError.badJSON }
        return dtos
    }

    static func download(
        url: String,
        quality: VideoQuality,
        outputFolder: URL,
        customBinary: String,
        cookies: BrowserCookies,
        titleOverride: String? = nil,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        var errors: [Error] = []
        for candidate in candidateURLs(for: url) {
            for cookie in cookieCandidates(for: cookies) {
                do {
                    return try await downloadOnce(
                        url: candidate,
                        quality: quality,
                        outputFolder: outputFolder,
                        customBinary: customBinary,
                        cookies: cookie,
                        titleOverride: titleOverride,
                        onProgress: onProgress
                    )
                } catch let error as YTDLPError {
                    if case .cancelled = error { throw error }
                    errors.append(error)
                    if !needsAnotherBrowser(error) { break }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    errors.append(error)
                    break
                }
            }
        }
        throw pickError(errors)
    }

    private static func downloadOnce(
        url: String,
        quality: VideoQuality,
        outputFolder: URL,
        customBinary: String,
        cookies: BrowserCookies,
        titleOverride: String? = nil,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let binary = try requireBinary(customPath: customBinary)
        guard BinaryLocator.findFFmpeg() != nil else { throw YTDLPError.ffmpegMissing }

        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        // Com override (ex: username do Instagram), usa o valor literal em vez do `%(title)` do
        // yt-dlp — precisa escapar `%` (o template trata `%` como caractere especial).
        let titleField = titleOverride.map { escapeOutputTemplateLiteral(String($0.prefix(180))) } ?? "%(title).180B"
        // A tag de qualidade no nome evita que baixar o mesmo vídeo em outra qualidade colida
        // com o arquivo já existente (o yt-dlp pularia o download vendo o nome igual).
        let template = outputFolder
            .appendingPathComponent("\(titleField) [%(id)s] [\(quality.fileTag)].%(ext)s")
            .path

        var arguments = try baseArguments(cookies: cookies, url: url)
        arguments += [
            "--newline",
            "--no-playlist",
            "--no-mtime",
            "-f", quality.ytDlpFormat,
            "-o", template,
            "--print", "after_move:filepath",
        ]

        if quality.extractsAudio {
            arguments += ["-x", "--audio-format", "mp3", "--audio-quality", "0"]
        } else {
            arguments += [
                "-S", "res,vcodec:h264,acodec:mp4a,ext:mp4:m4a",
                "--merge-output-format", "mp4",
            ]
        }

        arguments.append(url)

        let destination = PathBox()
        let result = try await run(
            binary: binary,
            arguments: arguments,
            timeout: nil,
            onLine: { line in
                if let parsed = ProgressParser.parse(line) {
                    if let dest = parsed.destinationPath {
                        destination.set(dest)
                    }
                    onProgress(parsed)
                } else if looksLikeFilePath(line) {
                    destination.set(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        )

        if Task.isCancelled { throw YTDLPError.cancelled }
        if result.status != 0 {
            DiagnosticLog.write("download cookies=\(cookies.rawValue) url=\(url) status=\(result.status) log=\(result.log)")
            throw YTDLPError.failed(status: result.status, message: friendlyMessage(from: result.log, url: url))
        }

        let file: URL
        if let lastDestination = destination.get(), FileManager.default.fileExists(atPath: lastDestination) {
            file = URL(fileURLWithPath: lastDestination)
        } else if let newest = newestFile(in: outputFolder, createdAfter: result.startedAt) {
            file = newest
        } else {
            throw YTDLPError.failed(
                status: result.status,
                message: "The download finished, but the file was not found in the destination folder."
            )
        }

        if quality.prefersQuickTime {
            let compatible = try await ensureQuickTimeCompatible(file, targetFPS: quality.targetFPS, onProgress: onProgress)
            if quality.isUpscale, let target = quality.height {
                return try await Upscaler.upscale(compatible, toShortSide: target, onProgress: onProgress)
            }
            return compatible
        }
        return file
    }

    // MARK: - Imagens (posts/carrosséis do Instagram)

    static func downloadImages(
        url: String,
        outputFolder: URL,
        customBinary: String,
        cookies: BrowserCookies,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> [URL] {
        var errors: [Error] = []
        for candidate in candidateURLs(for: url) {
            for cookie in cookieCandidates(for: cookies) {
                do {
                    return try await downloadImagesOnce(
                        url: candidate,
                        outputFolder: outputFolder,
                        customBinary: customBinary,
                        cookies: cookie,
                        onProgress: onProgress
                    )
                } catch let error as YTDLPError {
                    if case .cancelled = error { throw error }
                    errors.append(error)
                    if !needsAnotherBrowser(error) { break }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    errors.append(error)
                    break
                }
            }
        }
        throw pickError(errors)
    }

    /// Sem seleção de formato/merge/QuickTime, sem --no-playlist (baixa o carrossel todo).
    /// Posts de foto não têm formato de vídeo: `--write-thumbnail` baixa a própria foto (é o que
    /// o yt-dlp expõe nesse caso) e `--ignore-no-formats-error` evita que isso derrube o processo.
    /// Por isso o resultado é lido direto da pasta — não dá pra confiar no status de saída nem no
    /// `after_move:filepath` (ele não dispara pra thumbnail).
    private static func downloadImagesOnce(
        url: String,
        outputFolder: URL,
        customBinary: String,
        cookies: BrowserCookies,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> [URL] {
        let binary = try requireBinary(customPath: customBinary)
        try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let template = outputFolder
            .appendingPathComponent("%(title).120B [%(id)s] %(playlist_index|1)s.%(ext)s")
            .path

        var arguments = try baseArguments(cookies: cookies, url: url)
        if isInstagramStoryURL(url) { arguments += ["--no-playlist"] }
        arguments += [
            "--newline",
            "--no-mtime",
            "--ignore-no-formats-error",
            "--write-thumbnail",
            "-o", template,
            url,
        ]

        let startedAt = Date()
        let result = try await run(
            binary: binary,
            arguments: arguments,
            timeout: nil,
            onLine: { line in
                if let parsed = ProgressParser.parse(line) {
                    onProgress(parsed)
                }
            }
        )

        if Task.isCancelled { throw YTDLPError.cancelled }

        let files = newestFiles(in: outputFolder, createdAfter: startedAt)
        guard !files.isEmpty else {
            DiagnosticLog.write("downloadImages cookies=\(cookies.rawValue) url=\(url) status=\(result.status) log=\(result.log)")
            throw YTDLPError.failed(status: result.status, message: friendlyMessage(from: result.log, url: url))
        }
        return convertHEICIfNeeded(files)
    }

    /// O Instagram às vezes serve fotos em HEIC — converte pra JPEG (bem mais compatível) com o
    /// `sips` do próprio macOS, sem precisar de outra dependência. Falha ao converter = mantém o HEIC.
    private static func convertHEICIfNeeded(_ files: [URL]) -> [URL] {
        files.map { file in
            let ext = file.pathExtension.lowercased()
            guard ext == "heic" || ext == "heif" else { return file }
            let jpeg = file.deletingPathExtension().appendingPathExtension("jpg")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
            process.arguments = ["-s", "format", "jpeg", file.path, "--out", jpeg.path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return file }
            process.waitUntilExit()
            guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: jpeg.path) else { return file }
            try? FileManager.default.removeItem(at: file)
            return jpeg
        }
    }

    // MARK: - Vimeo

    /// Ordem de tentativa. Vimeo: o player embutido funciona sem login; a página normal vem como reserva.
    static func candidateURLs(for url: String) -> [String] {
        if let player = vimeoPlayerURL(from: url), player != url {
            return [player, url]
        }
        return [url]
    }

    /// vimeo.com/ID, vimeo.com/ID/HASH, /channels/x/ID, /groups/x/videos/ID, /album/n/video/ID → player.vimeo.com/video/ID[?h=HASH]
    static func vimeoPlayerURL(from rawURL: String) -> String? {
        guard let components = URLComponents(string: rawURL),
              let host = components.host?.lowercased(),
              host == "vimeo.com" || host.hasSuffix(".vimeo.com"),
              host != "player.vimeo.com" else { return nil }

        let parts = components.path.split(separator: "/").map(String.init)
        func isDigits(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy(\.isNumber) }

        var idIndex: Int?
        if let marker = parts.firstIndex(where: { $0 == "video" || $0 == "videos" }),
           marker + 1 < parts.count, isDigits(parts[marker + 1]) {
            idIndex = marker + 1
        } else if let first = parts.first, ["channels", "groups"].contains(first) {
            idIndex = parts.lastIndex(where: isDigits)
        } else if let first = parts.first, isDigits(first) {
            idIndex = 0
        }
        guard let index = idIndex else { return nil }

        var hash: String?
        if index + 1 < parts.count {
            let candidate = parts[index + 1]
            if candidate.count >= 8, candidate.allSatisfy({ $0.isLetter || $0.isNumber }) {
                hash = candidate
            }
        }
        if hash == nil {
            hash = components.queryItems?.first(where: { $0.name == "h" })?.value
        }

        var result = "https://player.vimeo.com/video/\(parts[index])"
        if let hash, !hash.isEmpty { result += "?h=\(hash)" }
        return result
    }

    // MARK: - QuickTime

    private static let quickTimeVideo = Set(["h264", "hevc", "h265", "mpeg4", "prores", "mjpeg"])
    private static let quickTimeAudio = Set(["aac", "alac", "mp3", "ac3", "eac3", "pcm_s16le", "pcm_s24le", "mp2"])

    private static func ensureQuickTimeCompatible(
        _ url: URL,
        targetFPS: Int?,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let probe = try await probeMedia(url)
        let videoOK = probe.videoCodec.map { quickTimeVideo.contains($0) } ?? true
        let audioOK = probe.audioCodec.map { quickTimeAudio.contains($0) } ?? true
        if videoOK && audioOK {
            return url
        }

        onProgress(
            DownloadProgress(
                fraction: nil,
                speed: nil,
                eta: nil,
                isProcessing: true,
                destinationPath: url.path,
                detail: "Converting for QuickTime…"
            )
        )

        guard let ffmpeg = BinaryLocator.findFFmpeg() else { throw YTDLPError.ffmpegMissing }
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).grabb-qt.mp4")

        // `-r` só se aplica reconvertendo; com `-c:v copy` ffmpeg recusa mudar o fps.
        let fpsArgs = (videoOK ? nil : targetFPS).map { ["-r", "\($0)"] } ?? []

        var videoArgs: [String]
        if videoOK {
            videoArgs = ["-c:v", "copy"]
        } else {
            videoArgs = fpsArgs + ["-c:v", "h264_videotoolbox", "-b:v", "8M", "-allow_sw", "1", "-tag:v", "avc1"]
        }
        let audioArgs = audioOK
            ? ["-c:a", "copy"]
            : ["-c:a", "aac", "-b:a", "192k"]

        let duration = probe.duration
        func runFFmpeg(video: [String]) async throws -> YTDLPClientRunResult {
            try await run(
                binary: ffmpeg,
                arguments: ["-y", "-i", url.path] + video + audioArgs + [
                    "-movflags", "+faststart",
                    "-progress", "pipe:1",
                    "-nostats",
                    temp.path,
                ],
                timeout: nil,
                onLine: { line in
                    if let fraction = ffmpegFraction(from: line, duration: duration) {
                        onProgress(
                            DownloadProgress(
                                fraction: fraction,
                                speed: nil,
                                eta: nil,
                                isProcessing: true,
                                destinationPath: temp.path,
                                detail: "Converting for QuickTime…"
                            )
                        )
                    }
                }
            )
        }

        var result = try await runFFmpeg(video: videoArgs)
        if result.status != 0, !videoOK {
            result = try await runFFmpeg(
                video: fpsArgs + ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p"]
            )
        }
        if result.status != 0 {
            try? FileManager.default.removeItem(at: temp)
            throw YTDLPError.failed(
                status: result.status,
                message: "The video downloaded, but the QuickTime conversion failed."
            )
        }

        let replacement = url.deletingPathExtension().appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: replacement.path) {
            try FileManager.default.removeItem(at: replacement)
        }
        try FileManager.default.moveItem(at: temp, to: replacement)
        if url != replacement, FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        return replacement
    }

    struct MediaProbe: Sendable {
        var videoCodec: String?
        var audioCodec: String?
        var duration: Double?
        var width: Int?
        var height: Int?
        var fps: Double?
    }

    private struct FFProbeDTO: Decodable {
        struct Stream: Decodable {
            var codecType: String?
            var codecName: String?
            var width: Int?
            var height: Int?
            var avgFrameRate: String?
            enum CodingKeys: String, CodingKey {
                case codecType = "codec_type"
                case codecName = "codec_name"
                case width
                case height
                case avgFrameRate = "avg_frame_rate"
            }
        }
        struct Format: Decodable {
            var duration: String?
        }
        var streams: [Stream]?
        var format: Format?
    }

    static func probeMedia(_ url: URL) async throws -> MediaProbe {
        guard let ffprobe = BinaryLocator.findFFprobe() ?? BinaryLocator.ffprobeBesideFFmpeg() else {
            return MediaProbe(videoCodec: nil, audioCodec: nil, duration: nil)
        }
        let result = try await run(
            binary: ffprobe,
            arguments: [
                "-v", "error",
                "-print_format", "json",
                "-show_streams",
                "-show_format",
                url.path,
            ],
            timeout: .seconds(30),
            onLine: { _ in }
        )
        guard result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let dto = try? JSONDecoder().decode(FFProbeDTO.self, from: data) else {
            return MediaProbe(videoCodec: nil, audioCodec: nil, duration: nil)
        }
        let videoStream = dto.streams?.first(where: { $0.codecType == "video" })
        let video = videoStream?.codecName
        let audio = dto.streams?.first(where: { $0.codecType == "audio" })?.codecName
        let duration = dto.format?.duration.flatMap(Double.init)
        var fps: Double?
        if let rate = videoStream?.avgFrameRate {
            let parts = rate.split(separator: "/").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { fps = parts[0] / parts[1] }
        }
        return MediaProbe(
            videoCodec: video,
            audioCodec: audio,
            duration: duration,
            width: videoStream?.width,
            height: videoStream?.height,
            fps: fps
        )
    }

    private static func ffmpegFraction(from line: String, duration: Double?) -> Double? {
        guard let duration, duration > 0 else { return nil }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("out_time_ms=") {
            let value = Double(trimmed.dropFirst("out_time_ms=".count)) ?? 0
            return min(max(value / (duration * 1_000_000), 0), 1)
        }
        if trimmed.hasPrefix("out_time_us=") {
            let value = Double(trimmed.dropFirst("out_time_us=".count)) ?? 0
            return min(max(value / (duration * 1_000_000), 0), 1)
        }
        return nil
    }

    // MARK: - Process

    private static func requireBinary(customPath: String) throws -> URL {
        guard let url = BinaryLocator.findYTDLP(customPath: customPath) else {
            throw YTDLPError.binaryMissing
        }
        return url
    }

    static func isInstagramStoryURL(_ url: String) -> Bool {
        guard let parsed = URL(string: url) else { return false }
        return MediaPlatform.detect(from: url) == .instagram && parsed.path.hasPrefix("/stories/")
    }

    private static func baseArguments(cookies: BrowserCookies, url: String) throws -> [String] {
        var args = [
            "--no-update",
            "--ignore-config",
            "--encoding", "utf-8",
            "--no-colors",
        ]
        if DiagnosticLog.isEnabled {
            args += ["--verbose", "--retries", "0", "--extractor-retries", "0"]
        }
        if isInstagramStoryURL(url) {
            guard cookies.ytDlpName != nil else {
                throw YTDLPError.failed(status: -1, message: "Select a browser in General → Cookies for Instagram Stories.")
            }
            guard let plugins = Bundle.main.url(forResource: "Diagnostics", withExtension: nil) else {
                throw YTDLPError.failed(status: -1, message: "Stories fix component is missing.")
            }
            args += ["--no-plugin-dirs", "--plugin-dirs", plugins.path,
                     "--retries", "0", "--extractor-retries", "0"]
        }
        if let ffmpeg = BinaryLocator.findFFmpeg() {
            args += ["--ffmpeg-location", ffmpeg.path]
        }
        if let deno = BinaryLocator.findDeno() {
            args += ["--js-runtimes", "deno:\(deno.path)"]
            // Alguns vídeos do YouTube só resolvem o desafio de assinatura com o solver "ejs"
            // baixado do GitHub sob demanda; sem isso o yt-dlp pula a resolução e só sobram
            // miniaturas (nenhuma resolução de vídeo). Sem essa flag, cai de vez em quando.
            args += ["--remote-components", "ejs:github"]
        } else if let node = BinaryLocator.findNode() {
            args += ["--js-runtimes", "node:\(node.path)"]
            args += ["--remote-components", "ejs:github"]
        }
        if let browser = cookies.ytDlpName {
            args += ["--cookies-from-browser", browser]
        }
        return args
    }

    static func run(
        binary: URL,
        arguments: [String],
        timeout: Duration?,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws -> YTDLPClientRunResult {
        let session = ProcessSession()
        let work = Task.detached(priority: .userInitiated) {
            try session.runSync(binary: binary, arguments: arguments, onLine: onLine)
        }

        return try await withTaskCancellationHandler {
            if let timeout {
                try await withThrowingTaskGroup(of: YTDLPClientRunResult.self) { group in
                    group.addTask { try await work.value }
                    group.addTask {
                        try await Task.sleep(for: timeout)
                        session.terminate()
                        throw YTDLPError.timeout
                    }
                    let result = try await group.next()!
                    group.cancelAll()
                    if Task.isCancelled {
                        session.terminate()
                        throw YTDLPError.cancelled
                    }
                    return result
                }
            } else {
                try await work.value
            }
        } onCancel: {
            session.terminate()
            work.cancel()
        }
    }

    private static func newestFile(in folder: URL, createdAfter: Date) -> URL? {
        let cutoff = createdAfter.addingTimeInterval(-2)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return files
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true, let date = values?.contentModificationDate, date >= cutoff else {
                    return nil
                }
                return (url, date)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    /// Como `newestFile`, mas devolve todos os arquivos novos (não só o mais recente) — usado
    /// quando um post vira vários arquivos (carrossel de imagens).
    private static func newestFiles(in folder: URL, createdAfter: Date) -> [URL] {
        let cutoff = createdAfter.addingTimeInterval(-2)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true, let date = values?.contentModificationDate else { return false }
                return date >= cutoff
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// `%` é caractere especial nos output templates do yt-dlp; precisa virar `%%` pra ser literal.
    private static func escapeOutputTemplateLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "%", with: "%%")
    }

    private static func looksLikeFilePath(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return false }
        let ext = URL(fileURLWithPath: trimmed).pathExtension.lowercased()
        let known = ["mp4", "m4a", "mp3", "webm", "mkv", "mov", "wav", "opus", "aac"]
        return known.contains(ext)
    }

    static func friendlyMessage(from log: String, url: String) -> String {
        let lower = log.lowercased()
        if lower.contains("vimeo"), lower.contains("password") {
            return "This Vimeo video has a password. Grabb does not support password-protected videos yet."
        }
        if lower.contains("vimeo"), lower.contains("referer") || lower.contains("embedding") {
            return "This Vimeo video plays only when embedded in another site. Open the page that shows it and paste the link of that page."
        }
        if lower.contains("operation not permitted") || lower.contains("permissionerror")
            || lower.contains("full disk access") || lower.contains("could not find") && lower.contains("cookies") {
            return permissionMessage
        }
        if lower.contains("login") || lower.contains("logged-in") || lower.contains("cookies")
            || lower.contains("sign in") || lower.contains("not a bot") {
            return loginMessage
        }
        if lower.contains("private") || lower.contains("unavailable") {
            return "The video is private, was removed, or is not available in this region."
        }
        if lower.contains("unsupported url") || lower.contains("no video") {
            return "This URL does not look like a supported video."
        }
        if lower.contains("http error 429") || lower.contains("too many requests") {
            return "Too many requests in a row. Wait a moment and try again."
        }
        let last = log
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty && !$0.hasPrefix("[debug]") && !$0.hasPrefix("WARNING:") }
        return last ?? "Download failed: \(url)."
    }

    static func statusLine(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("[debug]") { return nil }
        if trimmed.hasPrefix("{") { return nil }
        if trimmed.hasPrefix("WARNING:") { return nil }
        if trimmed.hasPrefix("ERROR:") {
            return String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}

/// Isola o `Process` para cancelamento e leitura incremental (evita deadlock de pipe).
private final class ProcessSession: @unchecked Sendable {
    let process = Process()
    private let lock = NSLock()
    private var didTerminate = false

    func runSync(
        binary: URL,
        arguments: [String],
        onLine: @escaping @Sendable (String) -> Void
    ) throws -> YTDLPClientRunResult {
        process.executableURL = binary
        process.arguments = arguments
        process.environment = BinaryLocator.processEnvironment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        let startedAt = Date()
        let diagnostic = (DiagnosticLog.isEnabled || arguments.contains("grabb:instagram-session"))
            ? DiagnosticRun(binary: binary, arguments: arguments) : nil
        let stdoutReader = LineAssembler(onLine: { line in
            // O JSON de metadados inclui URLs assinadas e não deve ir para o log.
            if !line.trimmingCharacters(in: .whitespaces).hasPrefix("{") {
                diagnostic?.write("stdout: \(line)")
            }
            onLine(line)
        })
        let stderrReader = LineAssembler(onLine: { line in
            diagnostic?.write("stderr: \(line)")
            onLine(line)
        })
        var launched = false
        defer {
            let status = launched ? String(process.terminationStatus) : "did not start"
            diagnostic?.write("END status=\(status) elapsed=\(Date().timeIntervalSince(startedAt))s")
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutReader.ingest(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrReader.ingest(handle.availableData)
        }

        do {
            try process.run()
            launched = true
        } catch {
            diagnostic?.write("Failed to start: \(error.localizedDescription)")
            throw error
        }
        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        stdoutReader.ingest(stdoutPipe.fileHandleForReading.availableData)
        stderrReader.ingest(stderrPipe.fileHandleForReading.availableData)
        stdoutReader.flush()
        stderrReader.flush()

        return YTDLPClientRunResult(
            status: process.terminationStatus,
            stdout: stdoutReader.text(),
            log: [stdoutReader.text(), stderrReader.text()].joined(separator: "\n"),
            startedAt: startedAt
        )
    }

    func terminate() {
        lock.lock()
        defer { lock.unlock() }
        guard !didTerminate else { return }
        didTerminate = true
        if process.isRunning {
            process.terminate()
        }
    }
}

struct YTDLPClientRunResult: Sendable {
    var status: Int32
    var stdout: String
    var log: String
    var startedAt: Date
}

/// Monta linhas a partir de blocos do pipe — não espera o JSON inteiro chegar.
private final class LineAssembler: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()
    private var collected = Data()
    private let onLine: @Sendable (String) -> Void

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func ingest(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        collected.append(data)
        pending.append(data)
        while let range = pending.range(of: Data([0x0A])) {
            let lineData = pending.subdata(in: pending.startIndex..<range.lowerBound)
            pending.removeSubrange(pending.startIndex..<range.upperBound)
            lock.unlock()
            emit(lineData)
            lock.lock()
        }
        lock.unlock()
    }

    func flush() {
        lock.lock()
        let rest = pending
        pending.removeAll()
        lock.unlock()
        if !rest.isEmpty {
            emit(rest)
        }
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: collected, encoding: .utf8)
            ?? String(data: collected, encoding: .isoLatin1)
            ?? ""
    }

    private func emit(_ data: Data) {
        var slice = data
        if slice.last == 0x0D {
            slice.removeLast()
        }
        guard !slice.isEmpty else { return }
        let line = String(data: slice, encoding: .utf8)
            ?? String(data: slice, encoding: .isoLatin1)
            ?? ""
        onLine(line)
    }
}

private final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var path: String?

    func set(_ value: String) {
        lock.lock()
        path = value
        lock.unlock()
    }

    func get() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return path
    }
}

enum ProgressParser {
    private static let percentRegex = try! NSRegularExpression(
        pattern: #"\[download\]\s+(\d+(?:\.\d+)?)%"#
    )
    private static let speedRegex = try! NSRegularExpression(
        pattern: #"at\s+(\S+/s)"#
    )
    private static let etaRegex = try! NSRegularExpression(
        pattern: #"ETA\s+(\S+)"#
    )
    private static let destRegex = try! NSRegularExpression(
        pattern: #"\[download\] Destination:\s+(.+)"#
    )

    static func parse(_ line: String) -> DownloadProgress? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        if ns.range(of: "[Merger]", options: .caseInsensitive).location != NSNotFound
            || ns.range(of: "[ExtractAudio]", options: .caseInsensitive).location != NSNotFound
            || ns.range(of: "[ffmpeg]", options: .caseInsensitive).location != NSNotFound {
            // yt-dlp não informa % real pra essas etapas; quem chama estima com o tempo decorrido.
            return DownloadProgress(fraction: nil, speed: nil, eta: nil, isProcessing: true, destinationPath: nil)
        }

        var destination: String?
        if let destMatch = destRegex.firstMatch(in: line, range: full), destMatch.numberOfRanges > 1 {
            destination = ns.substring(with: destMatch.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let percentMatch = percentRegex.firstMatch(in: line, range: full), percentMatch.numberOfRanges > 1 else {
            if let destination {
                return DownloadProgress(
                    fraction: 0,
                    speed: nil,
                    eta: nil,
                    isProcessing: false,
                    destinationPath: destination
                )
            }
            // Tamanho total desconhecido (CDN sem Content-Length): yt-dlp só informa
            // bytes e velocidade, sem %. Sem isso a barra fica presa em 0% até concluir.
            if ns.range(of: "[download]", options: .caseInsensitive).location != NSNotFound,
               let speed = firstCapture(speedRegex, in: ns) {
                return DownloadProgress(
                    fraction: nil,
                    speed: speed,
                    eta: firstCapture(etaRegex, in: ns),
                    isProcessing: false,
                    destinationPath: nil
                )
            }
            return nil
        }

        let percentString = ns.substring(with: percentMatch.range(at: 1))
        let fraction = (Double(percentString) ?? 0) / 100.0
        let speed = firstCapture(speedRegex, in: ns)
        let eta = firstCapture(etaRegex, in: ns)
        return DownloadProgress(
            fraction: min(max(fraction, 0), 1),
            speed: speed,
            eta: eta,
            isProcessing: false,
            destinationPath: destination
        )
    }

    private static func firstCapture(_ regex: NSRegularExpression, in ns: NSString) -> String? {
        let full = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: ns as String, range: full), match.numberOfRanges > 1 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }
}
