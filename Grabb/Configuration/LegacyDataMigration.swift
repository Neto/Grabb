import Foundation

/// Grabb used to be called DLALL, and has had two earlier bundle identifiers. On the first launch
/// of this version, it copies the old settings and moves the old history so nothing is lost.
enum LegacyDataMigration {
    /// Newest first: a setting found in a newer identifier wins.
    private static let legacyBundleIDs = ["com.spinoff.Grabb", "com.spinoff.DLALL"]
    private static let doneKey = "migratedLegacySettings"

    static func runIfNeeded(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        // Settings: output folder, cookie browsers, tutorial seen, diagnostics.
        // Window frames and Sparkle state are left behind; they belong to the old app.
        for id in legacyBundleIDs {
            guard let old = defaults.persistentDomain(forName: id) else { continue }
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
