import Foundation

/// User-tunable behaviour, persisted as JSON in Application Support.
public struct Preferences: Codable, Equatable {
    public var hotkey: HotkeySpec
    /// How links open unless a bookmark says otherwise.
    public var openBehavior: OpenBehavior
    /// Bundle identifier of the browser links open in. Safari by default, so an upgrade
    /// does not silently change where people's links land.
    public var browserBundleID: String
    /// Re-read Safari's bookmarks on every launch.
    public var autoSyncOnLaunch: Bool
    /// Reveal the number badge on each slice.
    public var showNumbers: Bool
    /// Draw the compass with its hard-edged wear: scratches, dents, chips, rust and folds. Off by
    /// default, which shows the cleaner, softly aged instrument; the tour offers the choice.
    public var compassWorn: Bool
    /// Radius of the menu in points.
    public var menuRadius: Double
    /// Start the app automatically when you log in.
    public var launchAtLogin: Bool
    /// Whether the first-run tour has been finished or dismissed.
    public var hasCompletedOnboarding: Bool
    /// Set once the ⌘R → ⌘E default change has been applied, so an explicit ⌘R is respected.
    public var hotkeyMigrated: Bool

    public init(
        hotkey: HotkeySpec = .default,
        openBehavior: OpenBehavior = .newTabForeground,
        browserBundleID: String = Browser.safari.bundleID,
        autoSyncOnLaunch: Bool = true,
        showNumbers: Bool = true,
        compassWorn: Bool = false,
        menuRadius: Double = 200,
        launchAtLogin: Bool = false,
        hasCompletedOnboarding: Bool = false,
        hotkeyMigrated: Bool = false
    ) {
        self.hotkey = hotkey
        self.openBehavior = openBehavior
        self.browserBundleID = browserBundleID
        self.autoSyncOnLaunch = autoSyncOnLaunch
        self.showNumbers = showNumbers
        self.compassWorn = compassWorn
        self.menuRadius = menuRadius
        self.launchAtLogin = launchAtLogin
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.hotkeyMigrated = hotkeyMigrated
    }

    public static let `default` = Preferences()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Preferences.default
        hotkey = try container.decodeIfPresent(HotkeySpec.self, forKey: .hotkey) ?? fallback.hotkey
        if let behavior = try container.decodeIfPresent(OpenBehavior.self, forKey: .openBehavior) {
            openBehavior = behavior
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            openBehavior = OpenBehavior.migrating(
                legacyTarget: try legacy.decodeIfPresent(String.self, forKey: .openIn),
                background: try legacy.decodeIfPresent(Bool.self, forKey: .openInBackground) ?? false
            )
        }
        browserBundleID = try container.decodeIfPresent(String.self, forKey: .browserBundleID)
            ?? fallback.browserBundleID
        autoSyncOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .autoSyncOnLaunch) ?? fallback.autoSyncOnLaunch
        showNumbers = try container.decodeIfPresent(Bool.self, forKey: .showNumbers) ?? fallback.showNumbers
        compassWorn = try container.decodeIfPresent(Bool.self, forKey: .compassWorn) ?? fallback.compassWorn
        menuRadius = try container.decodeIfPresent(Double.self, forKey: .menuRadius) ?? fallback.menuRadius
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        // Absent keys mean an older preferences file, which also means the user never
        // chose a shortcut knowingly — so a missing flag stays false.
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? container.contains(.hotkey) // a file that already has settings predates onboarding
        hotkeyMigrated = try container.decodeIfPresent(Bool.self, forKey: .hotkeyMigrated) ?? false
    }

    /// The keys of the two settings `openBehavior` replaced, read only to carry them forward.
    private enum LegacyKeys: String, CodingKey {
        case openIn
        case openInBackground
    }

    /// The browser links open in.
    public var browser: Browser { Browser.browser(forBundleID: browserBundleID) }

    /// Keeps pathological values out of the UI.
    public mutating func clamp() {
        menuRadius = min(max(menuRadius, 140), 320)
        if !hotkey.isValid { hotkey = .default }
        if browserBundleID.isEmpty { browserBundleID = Browser.safari.bundleID }
    }

    /// Moves anyone still on the old ⌘R default onto ⌘E, once.
    ///
    /// ⌘R is Safari's reload, and a Carbon hot key wins over the frontmost app, so leaving
    /// people on the old default would keep breaking reload for them. Anyone who picked
    /// something else — including deliberately picking ⌘R after the migration — is left alone.
    public mutating func migrateLegacyHotkey() {
        guard !hotkeyMigrated else { return }
        if hotkey == HotkeySpec.legacyDefault { hotkey = .default }
        hotkeyMigrated = true
    }

    public static var defaultFileURL: URL {
        AppSupport.url(for: "preferences.json")
    }

    public static func load(from url: URL = Preferences.defaultFileURL) -> Preferences {
        guard let data = try? Data(contentsOf: url),
              var prefs = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return .default }
        prefs.clamp()
        return prefs
    }

    public func save(to url: URL = Preferences.defaultFileURL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("Lodestar: failed to save preferences: \(error.localizedDescription)")
        }
    }
}
