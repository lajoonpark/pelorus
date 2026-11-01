import AppKit
import RadialCore

/// Opens bookmarks in the browser the user chose.
///
/// The care here is in doing exactly what was asked. Handing a URL to `NSWorkspace` with a target
/// application *looks* like opening a tab, but Safari and the Chromium family both treat it as
/// "open this address", which re-focuses an existing tab when that link is already loaded — so a
/// "New tab" setting quietly meant "new tab, unless I already had it open". The only way to get
/// exactly the behaviour asked for is to ask the browser, which is why a scriptable browser gets
/// AppleScript and an unscriptable one gets the plain open plus an honest note in Settings.
enum BrowserLauncher {

    static func open(_ url: URL, plan: OpenPlan, browser: Browser) {
        switch plan {
        case .launchServices(let background):
            openViaLaunchServices(url, browser: browser, background: background)
        case .scripted(let behavior, let wholeSite):
            if !runScripted(url, behavior: behavior, wholeSite: wholeSite, browser: browser) {
                // Consent denied, or the browser is busy. A plain open still gets the page in
                // front of the user; it may just land in a tab that already had it.
                openViaLaunchServices(url, browser: browser, background: !behavior.switchesToLink)
            }
        }
    }

    /// Returns whether the browser did as asked, so the caller knows when to fall back.
    private static func runScripted(
        _ url: URL,
        behavior: OpenBehavior,
        wholeSite: Bool,
        browser: Browser
    ) -> Bool {
        if behavior == .reuseTab, isRunning(browser),
           let tab = openTab(for: url, wholeSite: wholeSite, in: browser),
           let select = BrowserScripts.select(tab, in: browser) {
            return runAppleScript(select).succeeded
        }
        // A new tab, in the background only if that is what was asked for: finding nothing to
        // reuse means the link still has to appear in front of the user.
        guard let script = BrowserScripts.openNewTab(
            url: url.absoluteString,
            foreground: behavior.switchesToLink,
            in: browser
        ) else { return false }
        return runAppleScript(script).succeeded
    }

    /// A tab that already has the link, or nil when none does (or the browser would not say).
    private static func openTab(for url: URL, wholeSite: Bool, in browser: Browser) -> TabMatcher.Tab? {
        guard let list = BrowserScripts.listTabs(in: browser),
              let output = runAppleScript(list).output
        else { return nil }
        return TabMatcher.firstMatch(
            in: BrowserScripts.parseTabs(output),
            for: url.absoluteString,
            wholeSite: wholeSite
        )
    }

    /// Looking at a browser that is not running would launch it just to find nothing.
    private static func isRunning(_ browser: Browser) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
    }

    /// `withApplicationAt:` targets one specific browser and needs no scripting at all.
    static func openViaLaunchServices(_ url: URL, browser: Browser, background: Bool) {
        guard let applicationURL = applicationURL(for: browser) else {
            NSWorkspace.shared.open(url)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = !background
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                NSLog("Lodestar: failed to open \(url.absoluteString): \(error.localizedDescription)")
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }
    }

    static func applicationURL(for browser: Browser) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: browser.bundleID)
    }

    static func isInstalled(_ browser: Browser) -> Bool {
        applicationURL(for: browser) != nil
    }

    /// Browsers on this Mac, always including the selected one.
    static func installedBrowsers(selected: Browser) -> [Browser] {
        BrowserCatalog.available(selected: selected) { isInstalled(Browser.browser(forBundleID: $0)) }
    }

    private struct ScriptResult {
        let output: String?
        let succeeded: Bool
    }

    private static func runAppleScript(_ source: String) -> ScriptResult {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return ScriptResult(output: nil, succeeded: false) }
        let result = script.executeAndReturnError(&error)
        if let error {
            NSLog("Lodestar: AppleScript failed: \(error)")
            return ScriptResult(output: nil, succeeded: false)
        }
        return ScriptResult(output: result.stringValue, succeeded: true)
    }
}
