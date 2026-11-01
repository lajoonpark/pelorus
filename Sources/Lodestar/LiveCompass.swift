import SwiftUI
import AppKit
import RadialCore

/// Lets SwiftUI reach the compass it hosts, to flash a slice or replay the lid.
final class CompassHandle {
    fileprivate(set) weak var view: RadialMenuView?

    /// A slice springs in as if pressed, so a key and a click feel like one action.
    func flash(_ index: Int) { view?.flashSlice(index) }

    /// Shuts the lid and flips it open again.
    func replay() {
        guard let view else { return }
        view.dismiss(animated: true) { [weak view] in view?.present() }
    }
}

/// The real instrument, embedded in the window.
///
/// This is the overlay's own `RadialMenuView` — the same renderer, springs, lid and hit testing —
/// so the compass in the window is the compass you get at the cursor, not a lookalike. It is put
/// into `isEmbedded` mode: no backdrop, no hint row, and it fits itself to whatever room it is
/// given (the radius setting is an upper bound, as it is on the overlay).
struct LiveCompass: NSViewRepresentable {
    /// The slots on the visible page, in order.
    var bookmarks: [Bookmark]
    var page: Int
    var paging: RadialPaging
    var showsNumbers: Bool
    var radius: CGFloat
    var interactive = true
    var handle: CompassHandle?
    var onHover: (Bookmark?) -> Void = { _ in }
    var onActivate: (Bookmark) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> RadialMenuView {
        let view = RadialMenuView(frame: .zero)
        view.isEmbedded = true
        view.isInteractive = interactive
        view.requestedRadius = radius
        view.autoresizingMask = []
        context.coordinator.attach(view, self)
        view.configure(
            bookmarks: bookmarks,
            page: page,
            paging: paging,
            showsNumbers: showsNumbers,
            radius: radius
        )
        handle?.view = view
        // After the first layout, so the lid opens on a compass that already has its size.
        DispatchQueue.main.async { [weak view] in
            view?.fitEmbedded()
            view?.present()
        }
        return view
    }

    func updateNSView(_ view: RadialMenuView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        view.isInteractive = interactive
        handle?.view = view
        // The wear setting is global, so a change arrives here as a plain re-render.
        if coordinator.lastWorn != CompassTheme.isWorn {
            coordinator.lastWorn = CompassTheme.isWorn
            view.needsDisplay = true
        }

        let ids = bookmarks.map(\.id)
        let contentChanged = ids != coordinator.lastIDs || page != coordinator.lastPage
        let styleChanged = showsNumbers != coordinator.lastNumbers || radius != coordinator.lastRadius

        if styleChanged || contentChanged {
            view.requestedRadius = radius
            if contentChanged && !coordinator.lastIDs.isEmpty {
                // Turning a page (or adding a slot) plays the dial's own page-swap.
                view.showsNumbers = showsNumbers
                view.updatePage(bookmarks: bookmarks, page: page, paging: paging)
            } else {
                view.configure(
                    bookmarks: bookmarks,
                    page: page,
                    paging: paging,
                    showsNumbers: showsNumbers,
                    radius: radius
                )
            }
            view.fitEmbedded()
            coordinator.lastIDs = ids
            coordinator.lastPage = page
            coordinator.lastNumbers = showsNumbers
            coordinator.lastRadius = radius
        }
    }

    static func dismantleNSView(_ view: RadialMenuView, coordinator: Coordinator) {
        view.onActivate = nil
        view.onClose = nil
        view.onHoverSlice = nil
    }

    final class Coordinator {
        var parent: LiveCompass?
        var lastIDs: [UUID] = []
        var lastPage = 0
        var lastNumbers = true
        var lastRadius: CGFloat = 0
        var lastWorn = CompassTheme.isWorn

        func attach(_ view: RadialMenuView, _ owner: LiveCompass) {
            parent = owner
            lastIDs = owner.bookmarks.map(\.id)
            lastPage = owner.page
            lastNumbers = owner.showsNumbers
            lastRadius = owner.radius

            view.onHoverSlice = { [weak self] index in
                guard let self, let parent = self.parent else { return }
                if let index, parent.bookmarks.indices.contains(index) {
                    parent.onHover(parent.bookmarks[index])
                } else {
                    parent.onHover(nil)
                }
            }
            view.onActivate = { [weak self] bookmark in
                self?.parent?.onActivate(bookmark)
            }
            // The hub's ✕ closes the overlay. In a window there is nothing to close, so it shuts
            // the lid and flips it open again instead.
            view.onClose = { [weak view] in
                guard let view else { return }
                view.dismiss(animated: true) { [weak view] in view?.present() }
            }
        }
    }
}

/// Keys for the Dial tab: 1–9 open a slot, ← → turn the page.
///
/// A local monitor rather than SwiftUI key handling, because focus in this window moves between
/// text fields, the composer and buttons, and the dial's keys must work whenever none of those is
/// capturing text.
struct DialKeys: NSViewRepresentable {
    /// Return true when the event was used.
    var onKey: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(for: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onKey = onKey
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var onKey: ((NSEvent) -> Bool)?
        private var monitor: Any?

        func install(for view: NSView) {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self, weak view] event in
                guard let self, let view, let window = view.window,
                      event.window === window, window.isKeyWindow else { return event }
                // Typing in a field (or the shortcut recorder) owns the keyboard.
                if window.firstResponder is NSText { return event }
                let held = event.modifierFlags.intersection([.command, .control, .option])
                guard held.isEmpty else { return event }
                return (self.onKey?(event) ?? false) ? nil : event
            }
        }

        func remove() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { remove() }
    }
}
