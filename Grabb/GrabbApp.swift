import SwiftUI

@main
struct GrabbApp: App {
    @State private var settings: AppSettings
    @State private var model: LibraryModel
    @StateObject private var updater = AppUpdater()

    init() {
        LegacyDataMigration.runIfNeeded()
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _model = State(initialValue: LibraryModel(settings: settings))

        #if DEBUG
        // Test hook: Grabb --upscale-test <file> <short side>. Writes the result to /tmp/upscale_test.log.
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--upscale-test"), args.count > index + 2 {
            let path = args[index + 1]
            let target = Int(args[index + 2]) ?? 1080
            Task.detached {
                do {
                    let out = try await Upscaler.upscale(URL(fileURLWithPath: path), toShortSide: target) { _ in }
                    try? "OK \(out.path)".write(toFile: "/tmp/upscale_test.log", atomically: true, encoding: .utf8)
                } catch {
                    try? "ERR \(error)".write(toFile: "/tmp/upscale_test.log", atomically: true, encoding: .utf8)
                }
                exit(0)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(model)
                .task {
                    model.presentTutorialIfFirstLaunch()
                    model.refreshEngine()
                }
        }
        .defaultSize(width: 760, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Grabb") {
                    AppVersion.showAboutPanel()
                }
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Download from Clipboard") {
                    model.pasteFromClipboard()
                    model.enqueueDraft()
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])

                Button("Download URL") {
                    model.enqueueDraft()
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Show Tutorial") {
                    model.showTutorial = true
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Clear Finished") {
                    model.clearFinished()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(model)
        }
    }
}
