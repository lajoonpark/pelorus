import Foundation

/// Owns the ordered list of bookmarks that the radial menu shows.
///
/// Order is the product: slice numbers are muscle memory, so nothing ever reshuffles
/// silently. Imports keep the existing order and append unseen links at the end.
public final class BookmarkStore {

    public struct MergeResult: Equatable {
        public var added = 0
        public var updated = 0
        public var unchanged = 0
        public var total: Int { added + updated + unchanged }
    }

    /// What an import would do, worked out without doing it.
    public struct MergePreview: Equatable {
        /// The counts a real merge would report.
        public var result: MergeResult
        /// The links that would be appended, in the order they would land, already normalised.
        public var added: [Bookmark]
    }

    public private(set) var bookmarks: [Bookmark]
    public let fileURL: URL?
    private let fileManager: FileManager

    public init(bookmarks: [Bookmark] = [], fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.bookmarks = bookmarks
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static var defaultFileURL: URL {
        AppSupport.url(for: "bookmarks.json")
    }

    // MARK: - Loading and saving

    public static func load(from url: URL = BookmarkStore.defaultFileURL) -> BookmarkStore {
        let store = BookmarkStore(fileURL: url)
        guard let data = try? Data(contentsOf: url) else { return store }
        do {
            store.bookmarks = try JSONDecoder().decode([Bookmark].self, from: data)
        } catch {
            // A corrupt store must not lose the app: keep the bad file for recovery.
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("bookmarks-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
        }
        return store
    }

    public func save() {
        guard let fileURL else { return }
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(bookmarks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Lodestar: failed to save bookmarks: \(error.localizedDescription)")
        }
    }

    // MARK: - Queries

    public var count: Int { bookmarks.count }

    public func bookmark(at index: Int) -> Bookmark? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index]
    }

    public var paging: RadialPaging { RadialPaging(total: bookmarks.count) }

    /// Bookmarks visible on a page, already sliced for display.
    public func bookmarks(onPage page: Int) -> [Bookmark] {
        paging.items(onPage: page).compactMap { bookmark(at: $0) }
    }

    // MARK: - Mutation

    @discardableResult
    public func add(_ bookmark: Bookmark, save shouldSave: Bool = true) -> Bool {
        guard let normalized = Bookmark.normalizedURL(bookmark.url) else { return false }
        var copy = bookmark
        copy.url = normalized.absoluteString
        guard !bookmarks.contains(where: { $0.comparisonKey == copy.comparisonKey }) else { return false }
        bookmarks.append(copy)
        if shouldSave { save() }
        return true
    }

    @discardableResult
    public func update(id: UUID, title: String, url: String, folder: String? = nil) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }),
              let normalized = Bookmark.normalizedURL(url)
        else { return false }
        // Reject a change that would collide with a different entry.
        if bookmarks.contains(where: { $0.id != id && $0.comparisonKey == Bookmark(title: title, url: normalized.absoluteString).comparisonKey }) {
            return false
        }
        bookmarks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmarks[index].url = normalized.absoluteString
        if let folder { bookmarks[index].folder = folder }
        save()
        return true
    }

    /// Sets how one link opens. `nil` returns it to the default from Settings.
    ///
    /// The whole-site flag only means something when the link goes to an open tab, which a link
    /// on the default may also do, so it is dropped only for the two new-tab behaviours rather
    /// than left behind to resurface if the behaviour changes back.
    @discardableResult
    public func setOpening(id: UUID, behavior: OpenBehavior?, matchWholeSite: Bool) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return false }
        bookmarks[index].openBehavior = behavior
        bookmarks[index].matchWholeSite = (behavior == nil || behavior == .reuseTab) && matchWholeSite ? true : nil
        save()
        return true
    }

    @discardableResult
    public func remove(id: UUID) -> Bool {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return false }
        bookmarks.remove(at: index)
        save()
        return true
    }

    public func remove(atOffsets offsets: IndexSet) {
        for index in offsets.sorted(by: >) where bookmarks.indices.contains(index) {
            bookmarks.remove(at: index)
        }
        save()
    }

    /// Moves an entry, used by drag-to-reorder. Order is what makes slice numbers stable.
    @discardableResult
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) -> Bool {
        guard let from = source.first, bookmarks.indices.contains(from) else { return false }
        let item = bookmarks.remove(at: from)
        let target = destination > from ? destination - 1 : destination
        bookmarks.insert(item, at: min(max(0, target), bookmarks.count))
        save()
        return true
    }

    /// Drops `id` into the slot `target` holds right now.
    ///
    /// The dragged entry ends up exactly where it was dropped, and everything between the two
    /// shifts by one, in whichever direction closes the gap. That is the rule people expect from
    /// dragging a row onto another row, and it keeps every other slot number as close to where
    /// it was as a reorder can.
    @discardableResult
    public func move(id: UUID, ontoSlotOf target: UUID) -> Bool {
        guard id != target,
              let from = bookmarks.firstIndex(where: { $0.id == id }),
              let to = bookmarks.firstIndex(where: { $0.id == target })
        else { return false }
        return move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    /// Merges an import into the current list.
    ///
    /// - New links are appended in source order, so the first import fills page one.
    /// - Existing links keep their position (muscle memory) but pick up a renamed title.
    @discardableResult
    public func merge(_ incoming: [Bookmark], save shouldSave: Bool = true) -> MergeResult {
        var result = MergeResult()
        var indexByKey = Dictionary(
            bookmarks.enumerated().map { ($1.comparisonKey, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for bookmark in incoming {
            guard let normalized = Bookmark.normalizedURL(bookmark.url) else { continue }
            var copy = bookmark
            copy.url = normalized.absoluteString
            if let index = indexByKey[copy.comparisonKey] {
                let newTitle = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newTitle.isEmpty, bookmarks[index].title != newTitle {
                    bookmarks[index].title = newTitle
                    result.updated += 1
                } else {
                    result.unchanged += 1
                }
                if bookmarks[index].folder.isEmpty, !copy.folder.isEmpty {
                    bookmarks[index].folder = copy.folder
                }
            } else {
                bookmarks.append(copy)
                indexByKey[copy.comparisonKey] = bookmarks.count - 1
                result.added += 1
            }
        }
        if shouldSave { save() }
        return result
    }

    /// A dry run of `merge`: what it would add, rename and leave alone, with the store untouched.
    ///
    /// It runs the real merge on a scratch copy that has no file, so the preview cannot drift from
    /// the import it promises: whatever `merge` does, this reports, because it is the same code.
    public func previewMerge(_ incoming: [Bookmark]) -> MergePreview {
        let scratch = BookmarkStore(bookmarks: bookmarks)
        let result = scratch.merge(incoming, save: false)
        return MergePreview(result: result, added: Array(scratch.bookmarks.dropFirst(bookmarks.count)))
    }

    public func replaceAll(_ bookmarks: [Bookmark], save shouldSave: Bool = true) {
        self.bookmarks = bookmarks
        if shouldSave { save() }
    }
}
