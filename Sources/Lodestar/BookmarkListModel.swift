import SwiftUI
import AppKit
import RadialCore

/// Observable wrapper so SwiftUI can react to store mutations.
final class BookmarkListModel: ObservableObject {
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published var selectedID: UUID?
    @Published var searchText = ""
    @Published var syncMessage: SyncMessage?
    /// Bumped when something asks the window to put the cursor in the add field.
    @Published var focusRequest = 0

    enum SyncMessage: Equatable {
        case success(String)
        case failure(String)

        var text: String {
            switch self {
            case .success(let text), .failure(let text): return text
            }
        }

        var isError: Bool {
            if case .failure = self { return true }
            return false
        }
    }

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        reload()
    }

    var store: BookmarkStore { environment.store }

    var hasFullDiskAccess: Bool { environment.hasFullDiskAccess }

    func reload() {
        bookmarks = store.bookmarks
    }

    /// Filtered view used by the list. Order is preserved so the numbers stay honest.
    var filtered: [Bookmark] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.title.lowercased().contains(query)
                || $0.url.lowercased().contains(query)
                || $0.folder.lowercased().contains(query)
        }
    }

    /// 1-based slot number, matching what the radial shows.
    func slotNumber(for bookmark: Bookmark) -> Int? {
        bookmarks.firstIndex(where: { $0.id == bookmark.id }).map { $0 + 1 }
    }

    @discardableResult
    func add(title: String, url: String) -> String? {
        guard let normalized = Bookmark.normalizedURL(url) else {
            return "That doesn't look like a web address."
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmark = Bookmark(title: trimmedTitle, url: normalized.absoluteString)
        guard store.add(bookmark) else {
            return "That link is already in your menu."
        }
        reload()
        selectedID = bookmark.id
        syncMessage = .success("Added \(bookmark.displayTitle)")
        return nil
    }

    func update(
        id: UUID,
        title: String,
        url: String,
        openBehavior: OpenBehavior?,
        matchWholeSite: Bool
    ) -> String? {
        guard store.update(id: id, title: title, url: url) else {
            return "Could not save — check the address, or it may already exist."
        }
        _ = store.setOpening(id: id, behavior: openBehavior, matchWholeSite: matchWholeSite)
        reload()
        syncMessage = .success("Saved")
        return nil
    }

    func remove(_ bookmark: Bookmark) {
        _ = store.remove(id: bookmark.id)
        if selectedID == bookmark.id { selectedID = nil }
        reload()
    }

    func move(from source: IndexSet, to destination: Int) {
        store.move(fromOffsets: source, toOffset: destination)
        reload()
    }

    /// Reorders by slot, used by the up/down controls (drag is finicky in a table on macOS 13).
    func moveSlot(of bookmark: Bookmark, by delta: Int) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        let target = index + delta
        guard bookmarks.indices.contains(target) else { return }
        store.move(fromOffsets: IndexSet(integer: index), toOffset: delta > 0 ? target + 1 : target)
        reload()
    }

    /// Drag-to-reorder: `id` takes the slot `target` holds, and the rows between shift to close the gap.
    func move(_ id: UUID, ontoSlotOf target: UUID) {
        guard store.move(id: id, ontoSlotOf: target) else { return }
        reload()
    }

    /// Promotes an entry to slot 1. Cheap in the UI, and the only reorder people ask for.
    func moveToFront(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }), index > 0 else { return }
        store.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        reload()
    }

    func syncFromSafari() {
        let report = environment.syncFromSafari()
        reload()
        if let error = report.error {
            syncMessage = .failure(error.localizedDescription)
        } else if let result = report.result {
            let parts = [
                result.added > 0 ? "\(result.added) added" : nil,
                result.updated > 0 ? "\(result.updated) updated" : nil,
                result.added == 0 && result.updated == 0 ? "already up to date" : nil,
            ].compactMap { $0 }
            syncMessage = .success("Safari import: " + parts.joined(separator: ", "))
        }
    }

    /// A dry run of the Safari import, for the Import tab: what would land, and where.
    func previewSafariImport() -> (preview: BookmarkStore.MergePreview?, error: String?) {
        let report = environment.previewSafariImport()
        return (report.preview, report.error?.localizedDescription)
    }

    func openFullDiskAccessSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    func openBookmark(_ bookmark: Bookmark) {
        guard let url = Bookmark.normalizedURL(bookmark.url) else { return }
        BrowserLauncher.open(
            url,
            plan: OpenPlan.resolve(bookmark, default: defaultOpenBehavior, in: browser),
            browser: browser
        )
    }

    /// Changes how one link opens from a menu, without the edit sheet. `nil` means the default.
    func setOpenBehavior(_ behavior: OpenBehavior?, for bookmark: Bookmark) {
        _ = store.setOpening(id: bookmark.id, behavior: behavior, matchWholeSite: bookmark.matchesWholeSite)
        reload()
        let name = behavior?.displayName ?? "Default (\(defaultOpenBehavior.displayName))"
        syncMessage = .success("\(bookmark.displayTitle): \(name)")
    }

    /// What Settings says links do unless a bookmark overrides it.
    var defaultOpenBehavior: OpenBehavior { environment.preferences.openBehavior }

    var browser: Browser { environment.preferences.browser }

    /// Name of the browser links open in, so row actions and help text can name it.
    var browserName: String { browser.name }
}
