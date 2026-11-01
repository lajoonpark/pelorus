import XCTest
@testable import RadialCore

final class AppSupportTests: XCTestCase {
    private var base: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        base = fm.temporaryDirectory.appendingPathComponent("AppSupportTests-\(UUID().uuidString)")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: base)
    }

    private func write(_ text: String, to folder: String, file: String = "bookmarks.json") throws {
        let dir = base.appendingPathComponent(folder)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try text.write(to: dir.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    func testFreshInstallUsesNewFolderAndCreatesNothing() {
        let url = AppSupport.url(for: "bookmarks.json", base: base)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Lodestar")
        XCTAssertFalse(fm.fileExists(atPath: url.path))
        XCTAssertFalse(fm.fileExists(atPath: base.appendingPathComponent("Lodestar").path),
                       "asking for a path must not create folders by itself")
    }

    func testLegacyFileIsCopiedAndTheOriginalIsLeftAlone() throws {
        try write("old slots", to: "SafariRadial")
        let url = AppSupport.url(for: "bookmarks.json", base: base)
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Lodestar")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old slots")
        let legacy = base.appendingPathComponent("SafariRadial/bookmarks.json")
        XCTAssertEqual(try String(contentsOf: legacy, encoding: .utf8), "old slots")
    }

    func testExistingNewFileIsNeverOverwritten() throws {
        try write("old slots", to: "SafariRadial")
        try write("new slots", to: "Lodestar")
        let url = AppSupport.url(for: "bookmarks.json", base: base)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new slots")
    }

    func testEachFileIsCarriedOverOnItsOwn() throws {
        // Preferences saved first (creating the new folder) must not strand the old bookmarks.
        try write("old slots", to: "SafariRadial")
        try write("{}", to: "Lodestar", file: "preferences.json")
        let url = AppSupport.url(for: "bookmarks.json", base: base)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "old slots")
    }

    func testRepeatedCallsAreStable() throws {
        try write("old slots", to: "SafariRadial")
        let first = AppSupport.url(for: "bookmarks.json", base: base)
        let second = AppSupport.url(for: "bookmarks.json", base: base)
        XCTAssertEqual(first, second)
    }
}
