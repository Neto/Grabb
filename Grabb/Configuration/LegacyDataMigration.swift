import Foundation

/// Grabb used to be called DLALL (bundle id com.spinoff.DLALL). On the first launch of Grabb,
/// this copies the old settings and moves the old history so nothing is lost after the rename.
enum LegacyDataMigration {
    private static let legacyBundleID = "com.spinoff.DLALL"
    private static let doneKey = "migratedFromDLALL"

    static func runIfNeeded(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // Settings: output folder, cookie browsers, tutorial seen, diagnostics.
        // Window frames and Sparkle state are left behind; they belong to the old app.
        if let old = defaults.persistentDomain(forName: legacyBundleID) {
            for (key, value) in old where !key.hasPrefix("NSWindow Frame") && !key.hasPrefix("SU")
                && !key.hasPrefix("NSNav") && !key.hasPrefix("NSOSP") && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        // History: ~/Library/Application Support/DLALL → …/Grabb
        if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let old = support.appendingPathComponent("DLALL", isDirectory: true)
            let new = support.appendingPathComponent("Grabb", isDirectory: true)
            if fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) {
                try? fileManager.moveItem(at: old, to: new)
            }
        }
    }
}
