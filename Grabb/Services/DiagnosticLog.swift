import Foundation

enum DiagnosticLog: Sendable {
    private static let lock = NSLock()

    static var defaultEnabled: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "diagnosticLogging") as? Bool ?? defaultEnabled
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Grabb", isDirectory: true)
    }

    /// Não habilitamos dump de páginas, cabeçalhos HTTP ou exportação de cookies.
    static func sanitized(_ message: String) -> String {
        message.split(separator: "\n", omittingEmptySubsequences: false).map { part in
            var line = String(part)
            let sensitive = #"(?i)(?:\b(?:cookie|set-cookie|authorization|proxy-authorization)\s*:|\b(?:sessionid|csrftoken|access_token|refresh_token|password|passwd|token)\b["']?\s*[:=])"#
            if line.range(of: sensitive, options: .regularExpression) != nil {
                return "[line with credentials omitted]"
            }
            let regex = try! NSRegularExpression(pattern: #"https?://[^\s\"'<>]+"#)
            for match in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
                guard let range = Range(match.range, in: line) else { continue }
                var components = URLComponents(string: String(line[range]))
                components?.user = nil
                components?.password = nil
                components?.query = nil
                components?.fragment = nil
                line.replaceSubrange(range, with: components?.string ?? "[URL omitted]")
            }
            return line.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }.joined(separator: "\n")
    }

    static func append(_ message: String, to url: URL) {
        let line = "\(Date().formatted(.iso8601)) \(sanitized(message))\n"
        lock.lock()
        defer { lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .withoutOverwriting)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            NSLog("Grabb: failed to write diagnostics (%@)", error.localizedDescription)
        }
    }

    static func write(_ message: String) {
        let url = directory.deletingLastPathComponent().appendingPathComponent("Grabb.log")
        append(String(message.suffix(1500)), to: url)
    }
}

/// Um arquivo por subprocesso: não mistura sondagem, download e tentativas com outros navegadores.
struct DiagnosticRun: Sendable {
    let id = UUID().uuidString
    let file: URL

    init(binary: URL, arguments: [String]) {
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        file = DiagnosticLog.directory.appendingPathComponent("\(stamp)-\(id).log")
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        write("BEGIN id=\(id) app=\(version) build=\(build) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        write("appPath=\(bundle.bundlePath) executable=\(binary.path)")
        write("arguments=\(arguments)")
        if !arguments.contains("--cookies-from-browser") {
            write("Browser cookies were not requested in this run.")
        }
    }

    func write(_ message: String) {
        DiagnosticLog.append(message, to: file)
    }
}
