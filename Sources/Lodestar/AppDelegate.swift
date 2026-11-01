import AppKit
import SwiftUI
import RadialCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var environment: AppEnvironment!
    private var radialController: RadialController!
    private var hotkey: GlobalHotkey!
    private var listModel: BookmarkListModel!
    private var settingsModel: SettingsModel!
    private var onboardingModel: OnboardingModel?
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var managerWindow: NSWindow?
    private var quickAddWindow: NSWindow?
    private let router = ManagerRouter()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment()
        environment.migratePreferencesIfNeeded()

        hotkey = GlobalHotkey()
        radialController = RadialController(store: environment.store, preferences: environment.preferences)
        listModel = BookmarkListModel(environment: environment)
        settingsModel = SettingsModel(environment: environment, hotkey: hotkey)

        radialController.onEmptyMenu = { [weak self] in
            self?.openManager(focusNewLink: true)
        }
        settingsModel.onHotkeyChange = { [weak self] spec in
            self?.registerHotkey(spec) ?? false
        }
        settingsModel.onPreferencesChanged = { [weak self] preferences in
            guard let self else { return }
            self.radialController.updatePreferences(preferences)
            self.updateStatusItemTooltip()
        }

        registerHotkey(environment.preferences.hotkey)
        setUpStatusItem()
        buildMainMenu()

        if environment.preferences.autoSyncOnLaunch {
            // Import silently; failures stay quiet at launch and surface in the window instead.
            _ = environment.syncFromSafari()
            listModel.reload()
        }

        if !environment.preferences.hasCompletedOnboarding {
            showOnboarding()
        } else if environment.store.count == 0 {
            // A dial with nothing in it looks broken, so open the window that fills it.
            openManager(focusNewLink: true)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.unregister()
    }

    /// The app lives in the menu bar, so closing the last window must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Clicking the Dock icon (only present while a window is open) brings the window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { openManager() }
        return true
    }

    // MARK: - Hotkey

    @discardableResult
    private func registerHotkey(_ spec: HotkeySpec) -> Bool {
        hotkey.register(spec) { [weak self] in
            guard let self else { return }
            // The on-screen keycaps press along with the real ones.
            NotificationCenter.default.post(name: .dialHotkeyPressed, object: nil)
            if self.radialController.isOpen {
                self.radialController.hotkeyWhileOpen()
            } else {
                self.radialController.present()
            }
        }
    }

    // MARK: - Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Drawn from the same nine-slice geometry as the app itself, so the menu bar mark
            // is recognisably this product rather than a generic glyph.
            button.image = StatusIcon.make()
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
        }
        updateStatusItemTooltip()

        statusMenu = NSMenu()
        statusMenu.delegate = self
        // The click opens the menu, not the dial: adding a link and importing are here, and
        // hiding them behind a right-click would trade one undiscoverable action for another.
        statusItem.menu = statusMenu
        rebuildStatusMenu(statusMenu)
    }

    private func updateStatusItemTooltip() {
        statusItem.button?.toolTip = "Lodestar — \(environment.preferences.hotkey.displayName) opens the dial"
    }

    /// Rebuilt on open, so the labels carry the live shortcut and the paste item is honest
    /// about whether the clipboard actually holds a link.
    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let openItem = NSMenuItem(
            title: "Open the Dial",
            action: #selector(openDialFromMenuBar),
            keyEquivalent: ""
        )
        openItem.image = NSImage(systemSymbolName: "circle.hexagongrid", accessibilityDescription: nil)
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Adding a bookmark was previously only reachable by opening the window, which is the
        // wrong shape of interaction for a menu bar icon: most additions start from a URL you
        // already copied.
        let newItem = NSMenuItem(
            title: "New Bookmark…",
            action: #selector(newBookmark),
            keyEquivalent: "n"
        )
        newItem.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(newItem)

        let clipboardItem = NSMenuItem(
            title: "Add Link from Clipboard",
            action: #selector(addFromClipboard),
            keyEquivalent: ""
        )
        clipboardItem.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
        clipboardItem.isEnabled = Bookmark.normalizedURL(NSPasteboard.general.string(forType: .string) ?? "") != nil
        if let preview = clipboardPreview() {
            clipboardItem.title = "Add “\(preview)”"
        }
        menu.addItem(clipboardItem)

        menu.addItem(.separator())

        let manageItem = NSMenuItem(
            title: "All Bookmarks…",
            action: #selector(showManagerWindow(_:)),
            keyEquivalent: "b"
        )
        manageItem.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
        menu.addItem(manageItem)

        let syncItem = NSMenuItem(
            title: "Import from Safari",
            action: #selector(syncNow),
            keyEquivalent: ""
        )
        syncItem.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)
        menu.addItem(syncItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettingsWindow),
            keyEquivalent: ","
        )
        settingsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let tourItem = NSMenuItem(
            title: "Reopen the Tour",
            action: #selector(showOnboarding),
            keyEquivalent: ""
        )
        menu.addItem(tourItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Lodestar",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        for item in menu.items where item.target == nil {
            item.target = self
        }
    }

    private func clipboardPreview() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string),
              let url = Bookmark.normalizedURL(raw),
              let host = url.host
        else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    @objc private func openDialFromMenuBar() {
        radialController.present()
    }

    @objc private func syncNow() {
        listModel.syncFromSafari()
        openManager(tab: .importer)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Quick add

    @objc private func newBookmark() {
        openQuickAdd()
    }

    /// A one-field panel rather than the manager window: adding a link from the menu bar is a
    /// two-second action and should not cost a window, a reload and a scroll.
    private func openQuickAdd(prefill: String? = nil) {
        if let quickAddWindow {
            quickAddWindow.makeKeyAndOrderFront(nil)
            return
        }
        let view = QuickAddView(model: listModel) { [weak self] in
            self?.closeQuickAdd()
        }
        let panel = QuickAddPanel(content: NSHostingController(rootView: view))
        panel.delegate = self
        if let screen = windowScreen() {
            let size = panel.frame.size
            let origin = CGPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.midY - size.height / 2
            )
            panel.setFrameOrigin(origin)
        }
        quickAddWindow = panel
        promoteForWindow()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeQuickAdd() {
        quickAddWindow?.close()
        quickAddWindow = nil
        restoreAccessoryPolicyIfNeeded()
    }

    /// The screen the pointer is on, so the panel appears where the user is looking.
    private func windowScreen() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    /// Windows opened while the app is `.accessory` cannot take focus, so promotion is shared.
    private func promoteForWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The fast path for "I have a link in my clipboard and I want it on the dial". The panel
    /// opens pre-filled from the clipboard, so confirming is one Return press.
    @objc private func addFromClipboard() {
        // The status menu is still tracking here; opening a panel inside that callback is
        // dropped, so defer to the next runloop turn.
        DispatchQueue.main.async { [weak self] in
            self?.openQuickAdd()
        }
    }

    // MARK: - Windows

    /// Menu-bar entry point. AppKit passes the sender as the single argument, so the selector
    /// must take an object rather than a defaulted Swift parameter.
    @objc private func showManagerWindow(_ sender: Any?) {
        openManager()
    }

    private func openManager(focusNewLink: Bool = false, tab: ManagerTab? = nil) {
        if let tab { router.tab = tab }
        if let managerWindow {
            present(managerWindow)
            listModel.reload()
            if focusNewLink { listModel.focusRequest += 1 }
            return
        }

        let view = BookmarkManagerView(
            model: listModel,
            settings: settingsModel,
            router: router,
            onOpenDial: { [weak self] in self?.radialController.present() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Lodestar"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1040, height: 720))
        window.minSize = NSSize(width: 900, height: 640)
        // The desk's light follows the cursor, which needs move events even while idle.
        window.acceptsMouseMovedEvents = true
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = Palette.nsVoid
        window.appearance = NSAppearance(named: .darkAqua)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        managerWindow = window

        present(window)
        if focusNewLink { listModel.focusRequest += 1 }
    }

    /// Settings are a tab of the manager window, not a window of their own.
    @objc private func showSettingsWindow() {
        settingsModel.refresh()
        openManager(tab: .settings)
    }

    @objc private func showOnboarding() {
        if let onboardingWindow {
            present(onboardingWindow)
            return
        }

        let model = OnboardingModel(
            environment: environment,
            hotkey: environment.preferences.hotkey,
            hasBookmarks: environment.store.count > 0
        )
        model.onFinish = { [weak self] in
            guard let self else { return }
            self.onboardingWindow?.close()
            self.onboardingWindow = nil
            self.onboardingModel = nil
            if self.environment.store.count == 0 {
                self.openManager(focusNewLink: true)
            } else {
                self.openManager()
            }
        }
        onboardingModel = model

        let hosting = NSHostingController(rootView: OnboardingView(model: model))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to Lodestar"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.acceptsMouseMovedEvents = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.center()
        window.backgroundColor = Palette.nsVoid
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self
        onboardingWindow = window

        present(window)
    }

    /// Brings a window forward reliably.
    ///
    /// An `.accessory` app cannot activate itself on modern macOS, so a window opened from the
    /// status menu appeared behind the frontmost app (or not at all). Promoting to `.regular`
    /// while a window is up fixes that and gives the app a real menu bar — then the app drops
    /// back to the menu bar only when the last window closes.
    private func present(_ window: NSWindow) {
        // A status menu is still tracking while its action runs, and changing activation
        // policy or ordering a window front inside that callback is dropped. Defer past the
        // menu's own teardown.
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func restoreAccessoryPolicyIfNeeded() {
        let hasVisibleWindow = [managerWindow, onboardingWindow]
            .compactMap { $0 }
            .contains { $0.isVisible }
        if !hasVisibleWindow {
            // Order matters: set the policy first, otherwise the Dock icon lingers.
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Main menu

    /// A real menu bar while a window is open: standard Edit items so text fields work,
    /// plus this app's own commands with shortcuts. Nothing here is required for the dial —
    /// the dial is keyboard-driven already — but omitting menus would make the app feel like
    /// a utility that was never finished.
    private func buildMainMenu() {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem())
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(viewMenuItem())
        mainMenu.addItem(windowMenuItem())
        mainMenu.addItem(helpMenuItem())
        NSApp.mainMenu = mainMenu
    }

    /// Menu items that call this app's own selectors must name their target. Items with a nil
    /// target go through the responder chain instead, which is what Edit needs to reach the
    /// focused text field.
    private func item(_ title: String, _ action: Selector, _ key: String = "", mask: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = mask }
        item.target = self
        return item
    }

    /// Same, but delivered through the responder chain — required for window actions such as
    /// full screen, where a target of `self` would send the selector to this delegate.
    private func windowItem(_ title: String, _ action: Selector, _ key: String = "",
                           mask: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = mask }
        return item
    }

    private func appMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu()
        menu.addItem(item("About Lodestar", #selector(showAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettingsWindow), ","))
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        services.submenu = servicesMenu
        menu.addItem(services)
        NSApp.servicesMenu = servicesMenu
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide Lodestar", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = menu.addItem(
            withTitle: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(item("Quit Lodestar", #selector(quit), "q"))
        root.submenu = menu
        return root
    }

    private func fileMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Bookmark…", #selector(newBookmark), "n"))
        menu.addItem(item("Add Link from Clipboard", #selector(addFromClipboard), "v", mask: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Import from Safari", #selector(syncNow), "i", mask: [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(windowItem("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        root.submenu = menu
        return root
    }

    /// Standard Edit menu. Targets stay nil so these resolve through the responder chain to
    /// whichever text field has focus — pointing them at the delegate would break every field.
    private func editMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        root.submenu = menu
        return root
    }

    private func viewMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "View")
        menu.addItem(item("Open the Dial", #selector(openDialFromMenuBar)))
        menu.addItem(.separator())
        menu.addItem(windowItem("Toggle Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", mask: [.command, .control]))
        root.submenu = menu
        return root
    }

    private func windowMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Window")
        menu.addItem(windowItem("Minimise", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(windowItem("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bookmarks", #selector(showManagerWindow(_:)), "0"))
        root.submenu = menu
        NSApp.windowsMenu = menu
        return root
    }

    private func helpMenuItem() -> NSMenuItem {
        let root = NSMenuItem()
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Lodestar Help", #selector(showHelp), "?"))
        menu.addItem(item("Reopen the Tour", #selector(showOnboarding)))
        root.submenu = menu
        NSApp.helpMenu = menu
        return root
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Lodestar"
        alert.informativeText = """
        A radial menu for the bookmarks you actually use.

        \(environment.preferences.hotkey.displayName) opens the dial at your cursor, 1–9 opens a slot, Esc closes it.

        Your bookmarks are stored locally. Safari import is optional and needs Full Disk Access.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func showHelp() {
        showOnboarding()
    }
}

// MARK: - NSMenuDelegate

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        rebuildStatusMenu(menu)
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === managerWindow {
            listModel.syncMessage = nil
        }
        if window === quickAddWindow {
            quickAddWindow = nil
        }
        if window === onboardingWindow {
            onboardingWindow = nil
            onboardingModel = nil
            // Closing the tour is a decision, not an error: honour it.
            environment.updatePreferences { $0.hasCompletedOnboarding = true }
        }
        // Deferred: the window is still visible inside this callback.
        DispatchQueue.main.async { [weak self] in
            self?.restoreAccessoryPolicyIfNeeded()
        }
    }
}

/// The menu bar mark: the dial's nine slices as a broken ring, and a needle.
///
/// Drawn rather than borrowed from an SF Symbol, so it matches the product. Rendered as a
/// template image, so macOS tints it for light and dark menu bars, which means it has to say
/// "radial menu" in one colour and about twelve pixels. The ring is split into nine arcs, one
/// per slice with a gap on each boundary, so it reads as the dial and not as Safari's own
/// compass; the needle is aimed at slice 2. A scale or numerals would turn to mush here.
///
/// The geometry is on a 64-unit grid and matches `docs/icon-prototypes/menubar-b.svg`.
enum StatusIcon {
    static func make(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let unit = rect.width / 64

            // Compass degrees, clockwise from 12 o'clock, in the flipped frame set up below.
            func point(_ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
                let angle = degrees * .pi / 180
                return CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
            }

            context.saveGState()
            context.translateBy(x: rect.midX, y: rect.midY)
            context.scaleBy(x: 1, y: -1)

            // One arc per slice, centred on the slice, leaving a gap on each boundary.
            let halfArc: CGFloat = 14
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(5 * unit)
            context.setLineCap(.butt)
            for slice in 0..<9 {
                let centre = CGFloat(slice) * 40
                let arc = CGMutablePath()
                arc.addArc(
                    center: .zero,
                    radius: 27 * unit,
                    startAngle: (centre - halfArc - 90) * .pi / 180,
                    endAngle: (centre + halfArc - 90) * .pi / 180,
                    clockwise: false
                )
                context.addPath(arc)
            }
            context.strokePath()

            // Needle: a kite aimed at slice 2.
            context.setFillColor(NSColor.black.cgColor)
            let needle = CGMutablePath()
            needle.move(to: point(19 * unit, 40))
            needle.addLine(to: point(6.5 * unit, 130))
            needle.addLine(to: point(12 * unit, 220))
            needle.addLine(to: point(6.5 * unit, 310))
            needle.closeSubpath()
            context.addPath(needle)
            context.fillPath()

            context.restoreGState()
            return true
        }
        image.isTemplate = true
        return image
    }
}
