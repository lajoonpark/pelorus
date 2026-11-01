import AppKit
import RadialCore

/// Shared app state. One instance, passed explicitly — no singletons scattered around.
final class AppEnvironment {
    let store: BookmarkStore
    private(set) var preferences: Preferences
    private let preferencesURL: URL

    init(storeURL: URL = BookmarkStore.defaultFileURL,
         preferencesURL: URL = Preferences.defaultFileURL) {
        self.store = BookmarkStore.load(from: storeURL)
        self.preferences = Preferences.load(from: preferencesURL)
        self.preferencesURL = preferencesURL
    }

    func updatePreferences(_ mutate: (inout Preferences) -> Void) {
        mutate(&preferences)
        preferences.clamp()
        preferences.save(to: preferencesURL)
    }

    struct SyncReport {
        var result: BookmarkStore.MergeResult?
        var error: Error?
    }

    struct PreviewReport {
        var preview: BookmarkStore.MergePreview?
        var error: Error?
    }

    /// What `syncFromSafari` would do, without doing it.
    func previewSafariImport() -> PreviewReport {
        do {
            let remote = try SafariBookmarksReader.read()
            return PreviewReport(preview: store.previewMerge(remote), error: nil)
        } catch {
            return PreviewReport(preview: nil, error: error)
        }
    }

    /// Applies one-time preference migrations and persists the result.
    ///
    /// Called at launch before anything reads `preferences`, so the rest of the app only ever
    /// sees current values.
    func migratePreferencesIfNeeded() {
        let before = preferences
        var migrated = preferences
        migrated.migrateLegacyHotkey()
        guard migrated != before else { return }
        preferences = migrated
        preferences.save(to: preferencesURL)
    }

    /// Pulls the current Safari bookmarks in.
    ///
    /// Links already in the list keep their slot, so slice numbers survive repeated imports.
    func syncFromSafari() -> SyncReport {
        do {
            let remote = try SafariBookmarksReader.read()
            let result = store.merge(remote)
            return SyncReport(result: result, error: nil)
        } catch {
            return SyncReport(result: nil, error: error)
        }
    }

    var hasFullDiskAccess: Bool {
        SafariBookmarksReader.accessStatus()
    }
}
