import Foundation

enum BinaryLocator: Sendable {
    static let brewPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/opt/homebrew/sbin",
    ]

    /// `Grabb.app/Contents/Helpers` — yt-dlp, ffmpeg, deno empacotados no app.
    static var bundledHelpersDirectory: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }

    static var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        var parts: [String] = []
        if let bundled = bundledHelpersDirectory {
            parts.append(bundled.path)
        }
        parts.append(contentsOf: brewPaths)
        let current = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (parts + [current]).joined(separator: ":")
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }

    static func findYTDLP(customPath: String) -> URL? {
        existingExecutable(customPath)
            // yt-dlp é empacotado como PyInstaller onedir (pasta yt-dlp.bundle/ com o executável
            // yt-dlp dentro) em vez de onefile — onefile se autoextrai a cada execução (~7s de
            // startup por chamada); onedir já vem descompactado, então roda na hora. A extensão
            // .bundle é necessária pro codesign do app tratar a pasta como um pacote já assinado
            // (senão ele tenta validar o conteúdo de _internal/ por dentro e falha).
            ?? bundled("yt-dlp.bundle/yt-dlp")
            ?? existingExecutable("/opt/homebrew/bin/yt-dlp")
            ?? existingExecutable("/usr/local/bin/yt-dlp")
            ?? which("yt-dlp")
    }

    static func findFFmpeg() -> URL? {
        bundled("ffmpeg")
            ?? existingExecutable("/opt/homebrew/bin/ffmpeg")
            ?? existingExecutable("/usr/local/bin/ffmpeg")
            ?? which("ffmpeg")
    }

    static func findFFprobe() -> URL? {
        bundled("ffprobe")
            ?? existingExecutable("/opt/homebrew/bin/ffprobe")
            ?? existingExecutable("/usr/local/bin/ffprobe")
            ?? which("ffprobe")
    }

    static func ffprobeBesideFFmpeg() -> URL? {
        guard let ffmpeg = findFFmpeg() else { return nil }
        return existingExecutable(
            ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe").path
        )
    }

    static func findDeno() -> URL? {
        bundled("deno")
            ?? existingExecutable("/opt/homebrew/bin/deno")
            ?? existingExecutable("/usr/local/bin/deno")
            ?? which("deno")
    }

    static func findNode() -> URL? {
        bundled("node")
            ?? existingExecutable("/opt/homebrew/bin/node")
            ?? existingExecutable("/usr/local/bin/node")
            ?? which("node")
    }

    static func bundled(_ name: String) -> URL? {
        guard let dir = bundledHelpersDirectory else { return nil }
        return existingExecutable(dir.appendingPathComponent(name).path)
    }

    static func existingExecutable(_ path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDir), !isDir.boolValue,
              FileManager.default.isExecutableFile(atPath: trimmed) else {
            return nil
        }
        return URL(fileURLWithPath: trimmed)
    }

    private static func which(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        process.environment = processEnvironment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return existingExecutable(path)
    }
}
