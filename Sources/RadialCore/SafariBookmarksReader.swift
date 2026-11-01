import Foundation

/// Reads bookmarks from Safari's `Bookmarks.plist`.
///
/// Safari stores its bookmarks as a binary/XML plist at
/// `~/Library/Safari/Bookmarks.plist`. Reading it requires Full Disk Access for the
/// host app on modern macOS, because the file lives behind TCC. There is no public,
/// sandbox-friendly API for this, so we read the file directly and surface a clear,
/// actionable error when access is missing.
public enum SafariBookmarksReader {

    public enum ReadError: LocalizedError, Equatable {
        case fileNotFound(URL)
        case permissionDenied(URL)
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "No Safari bookmarks found at \(url.path). If Safari has never saved a bookmark, open it once and try again."
            case .permissionDenied:
                return "macOS blocked access to your Safari bookmarks. Grant Full Disk Access to Lodestar in System Settings › Privacy & Security › Full Disk Access, then try again."
            case .malformed(let detail):
                return "The Safari bookmarks file could not be read: \(detail)"
            }
        }

        /// The settings pane to send people to when access is the problem.
        public var isPermissionProblem: Bool {
            if case .permissionDenied = self { return true }
            return false
        }
    }

    public static var defaultURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Safari/Bookmarks.plist")
    }

    public static func read(from url: URL = defaultURL) throws -> [Bookmark] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ReadError.fileNotFound(url)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain,
               error.code == NSFileReadNoPermissionError || error.code == NSFileReadUnknownError {
                throw ReadError.permissionDenied(url)
            }
            if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) {
                throw ReadError.permissionDenied(url)
            }
            throw ReadError.malformed(error.localizedDescription)
        }
        return try parse(data)
    }

    /// Parses an in-memory plist. Exposed so the format can be tested without Safari.
    public static func parse(_ data: Data) throws -> [Bookmark] {
        let root: Any
        do {
            root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw ReadError.malformed(error.localizedDescription)
        }
        guard let dictionary = root as? [String: Any] else {
            throw ReadError.malformed("unexpected plist root")
        }
        var results: [Bookmark] = []
        var seen = Set<String>()
        walk(dictionary, path: [], into: &results, seen: &seen)
        return results
    }

    private static func walk(
        _ node: [String: Any],
        path: [String],
        into results: inout [Bookmark],
        seen: inout Set<String>
    ) {
        let type = node["WebBookmarkType"] as? String
        switch type {
        case "WebBookmarkTypeLeaf":
            guard let urlString = node["URLString"] as? String,
                  let url = Bookmark.normalizedURL(urlString)
            else { return }
            // Titles in Safari plists are in "URIDictionary"; fall back to the raw title.
            let uriTitle = (node["URIDictionary"] as? [String: Any])?["title"] as? String
            let fallbackTitle = node["Title"] as? String
            let bookmark = Bookmark(
                title: uriTitle ?? fallbackTitle ?? "",
                url: url.absoluteString,
                folder: path.joined(separator: "/")
            )
            guard seen.insert(bookmark.comparisonKey).inserted else { return }
            results.append(bookmark)

        case "WebBookmarkTypeList", "WebBookmarkTypeProxy":
            let rawTitle = (node["Title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (rawTitle?.isEmpty ?? true) ? nil : rawTitle
            // Safari's synthetic roots ("BookmarksBar", the reading list, the empty root) are
            // structure, not folders the user named, so they never appear in the subtitle.
            let isSyntheticRoot = title == nil || title == "BookmarksBar" || title == "BookmarksMenu"
                || title == "com.apple.ReadingList" || title == "History"
            if title == "com.apple.ReadingList" { return }
            let nextPath = isSyntheticRoot ? path : path + [title!]
            for child in (node["Children"] as? [[String: Any]]) ?? [] {
                walk(child, path: nextPath, into: &results, seen: &seen)
            }

        default:
            return
        }
    }

    /// Whether the process can currently read the bookmarks file.
    public static func accessStatus(for url: URL = defaultURL) -> Bool {
        FileManager.default.isReadableFile(atPath: url.path)
    }
}
