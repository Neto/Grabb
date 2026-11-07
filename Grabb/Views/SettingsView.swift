import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(LibraryModel.self) private var model
    @State private var checkingSession = false
    @State private var sessionReport: String?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            engineTab
                .tabItem { Label("Engine", systemImage: "terminal") }
        }
        .frame(width: 520, height: 420)
        .onAppear { model.refreshEngine() }
    }

    @ViewBuilder
    private var generalTab: some View {
        @Bindable var settings = settings

        Form {
            Section("Download") {
                LabeledContent("Destination folder") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(settings.resolvedOutputFolder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: 280, alignment: .trailing)
                            .help(settings.resolvedOutputFolder.path)
                        HStack {
                            Button("Escolher…") { pickFolder() }
                            if !settings.outputFolderPath.isEmpty {
                                Button("Use Downloads") {
                                    settings.outputFolderPath = ""
                                }
                            }
                        }
                    }
                }

                Picker("Default quality", selection: $settings.defaultQuality) {
                    ForEach(VideoQuality.standardCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Text("Videos are saved as H.264 + AAC. They open in QuickTime and in the TV app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Cookies for videos", selection: $settings.videoCookiesBrowser) {
                    ForEach(BrowserCookies.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Text("YouTube, Reels, Instagram posts, and other links. None does not read cookies. Automatic tries without a login first and uses a browser if necessary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Cookies for Instagram Stories", selection: $settings.storyCookiesBrowser) {
                    ForEach(BrowserCookies.allCases.filter { $0.ytDlpName != nil }) { option in
                        Text(option.title).tag(option)
                    }
                }
                Text("Video and image Stories use only this browser. For Safari, the app needs Full Disk Access in System Settings → Privacy & Security.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("When finished") {
                Toggle("Show in Finder", isOn: $settings.revealWhenDone)
                Toggle("Open the file", isOn: $settings.openWhenDone)
            }

            Section("Uso") {
                Text("Download only content that you created, that is in the public domain, or that you have permission to download. The terms of YouTube, Instagram, TikTok, and Vimeo restrict downloads. This app is a personal tool. It is not for the App Store.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    @ViewBuilder
    private var engineTab: some View {
        @Bindable var settings = settings

        Form {
            Section("Ferramentas") {
                LabeledContent("yt-dlp") {
                    Text(binaryLabel(BinaryLocator.findYTDLP(customPath: settings.customYTDLPPath)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("ffmpeg") {
                    Text(binaryLabel(BinaryLocator.findFFmpeg()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                LabeledContent("deno") {
                    Text(binaryLabel(BinaryLocator.findDeno()) + (BinaryLocator.findDeno() == nil ? " (optional, helps with YouTube)" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                TextField("Manual yt-dlp path", text: $settings.customYTDLPPath)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: settings.customYTDLPPath) {
                        model.refreshEngine()
                    }
                Text("If empty, Grabb uses the tools inside the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Installation") {
                Text("yt-dlp, ffmpeg, and deno are inside the app. You do not need to install anything in Terminal.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Check Again") {
                    model.refreshEngine()
                }
            }

            Section("Diagnostics") {
                Toggle("Record detailed diagnostics", isOn: $settings.diagnosticLogging)
                Text("Records versions, browser, cookie reading, and errors for each run. It makes no extra requests. Cookie and token values are omitted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(checkingSession ? "Checking local cookies…" : "Check Instagram session (offline)") {
                    let browser = settings.storyCookiesBrowser
                    let binary = settings.customYTDLPPath
                    checkingSession = true
                    sessionReport = nil
                    Task {
                        defer { checkingSession = false }
                        do {
                            sessionReport = try await YTDLPClient.checkInstagramSession(customBinary: binary, cookies: browser)
                        } catch {
                            sessionReport = error.localizedDescription
                        }
                    }
                }
                .disabled(checkingSession)
                Text("Uses Cookies for Instagram Stories in General. This check reads local cookies only; it does not contact Instagram or show cookie values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let sessionReport {
                    Text(sessionReport)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                Button("Show Logs in Finder") {
                    let folder = DiagnosticLog.directory
                    do {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    } catch {
                        model.banner = "Could not open the logs folder: \(error.localizedDescription)"
                    }
                }
            }

            Section("Version") {
                LabeledContent("Grabb") {
                    Text(AppVersion.full)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private func binaryLabel(_ url: URL?) -> String {
        url?.path ?? "not found"
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Escolher"
        panel.message = "Folder where videos are saved."
        panel.directoryURL = settings.resolvedOutputFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.outputFolderPath = url.path
    }
}

#Preview {
    let settings = AppSettings()
    SettingsView()
        .environment(settings)
        .environment(LibraryModel(settings: settings))
}
