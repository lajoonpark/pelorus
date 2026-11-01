import SwiftUI
import AppKit
import ServiceManagement
import RadialCore

final class SettingsModel: ObservableObject {
    @Published private(set) var preferences: Preferences
    @Published var hotkeyError: String?
    @Published private(set) var safariMessage: String?
    @Published private(set) var hasFullDiskAccess = false

    private let environment: AppEnvironment
    private let hotkey: GlobalHotkey
    /// Re-registers the shortcut; the app delegate owns the handler.
    var onHotkeyChange: ((HotkeySpec) -> Bool)?
    /// Fired after any preference change so the radial picks up new settings immediately.
    var onPreferencesChanged: ((Preferences) -> Void)?

    init(environment: AppEnvironment, hotkey: GlobalHotkey) {
        self.environment = environment
        self.hotkey = hotkey
        self.preferences = environment.preferences
        self.hasFullDiskAccess = environment.hasFullDiskAccess
        CompassTheme.isWorn = preferences.compassWorn
    }

    func refresh() {
        preferences = environment.preferences
        hasFullDiskAccess = environment.hasFullDiskAccess
    }

    // MARK: - Safari import

    /// Optional by design: the rest of the app never consults this.
    func syncFromSafari() {
        let report = environment.syncFromSafari()
        hasFullDiskAccess = environment.hasFullDiskAccess
        if let error = report.error {
            safariMessage = error.localizedDescription
        } else if let result = report.result {
            let parts = [
                result.added > 0 ? "\(result.added) added" : nil,
                result.updated > 0 ? "\(result.updated) updated" : nil,
                result.added == 0 && result.updated == 0 ? "already up to date" : nil,
            ].compactMap { $0 }
            safariMessage = parts.joined(separator: ", ")
        }
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

    var conflict: HotkeyConflicts.Conflict? {
        HotkeyConflicts.conflict(for: preferences.hotkey)
    }

    var suggestedHotkey: HotkeySpec {
        HotkeyConflicts.saferAlternative(to: preferences.hotkey)
    }

    func setHotkey(_ spec: HotkeySpec) {
        guard spec.isValid else {
            hotkeyError = "Include at least one of ⌘, ⌃ or ⌥."
            return
        }
        // Re-selecting the active shortcut is a no-op, not a conflict with ourselves.
        guard spec == preferences.hotkey || hotkey.isAvailable(spec) else {
            hotkeyError = "\(spec.displayName) is already taken by another app."
            return
        }
        let applied = onHotkeyChange?(spec) ?? false
        guard applied else {
            hotkeyError = "Could not register \(spec.displayName)."
            return
        }
        hotkeyError = nil
        mutate { $0.hotkey = spec }
    }

    func setOpenBehavior(_ behavior: OpenBehavior) {
        mutate { $0.openBehavior = behavior }
    }

    /// Browsers actually installed on this Mac, plus the current choice.
    var installedBrowsers: [Browser] {
        BrowserLauncher.installedBrowsers(selected: preferences.browser)
    }

    func setBrowser(_ browser: Browser) {
        mutate { $0.browserBundleID = browser.bundleID }
    }

    /// Whether the chosen browser can be told what to do with its tabs.
    ///
    /// Firefox and Arc have no tab scripting, so none of the behaviours can be asked for:
    /// saying so here is better than letting the setting quietly do nothing.
    var behaviorIsHonoured: Bool {
        OpenPlan.honours(preferences.browser)
    }

    func setAutoSync(_ value: Bool) {
        mutate { $0.autoSyncOnLaunch = value }
    }

    func setShowNumbers(_ value: Bool) {
        mutate { $0.showNumbers = value }
    }

    func setCompassWorn(_ value: Bool) {
        mutate { $0.compassWorn = value }
    }

    func setMenuRadius(_ value: Double) {
        mutate { $0.menuRadius = value }
    }

    func setLaunchAtLogin(_ value: Bool) {
        LaunchAtLogin.setEnabled(value)
        mutate { $0.launchAtLogin = value }
    }

    private func mutate(_ block: (inout Preferences) -> Void) {
        environment.updatePreferences(block)
        preferences = environment.preferences
        CompassTheme.isWorn = preferences.compassWorn
        onPreferencesChanged?(preferences)
    }
}

/// Registering as a login item, without a bundled helper.
enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        // SMLoginItemSetEnabled needs a bundled helper, which is overkill here. SMAppService
        // is available on macOS 13+, which is this app's floor.
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    _ = try SMAppServiceRegistrar.register()
                } else {
                    try SMAppServiceRegistrar.unregister()
                }
            } catch {
                NSLog("Lodestar: login item update failed: \(error.localizedDescription)")
            }
        }
    }
}

/// Thin wrapper so the rest of the code does not import ServiceManagement everywhere.
enum SMAppServiceRegistrar {
    static func register() throws -> Bool {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.register()
            return true
        }
        return false
    }

    static func unregister() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
        }
    }
}
