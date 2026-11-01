import AppKit

/// Borderless overlay that can take key focus without activating the app.
///
/// Non-activating is the important part: the frontmost app stays frontmost, so closing the
/// menu hands focus straight back and ⌘R never steals you out of Safari.
final class RadialPanel: NSPanel {

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        animationBehavior = .none
        // `canBecomeMain` is already false, so the overlay never becomes *the* window of a
        // stage. `becomesKeyOnlyIfNeeded` keeps it from grabbing key focus back from a
        // transient field, and `.stationary` stops Mission Control / Stage Manager from
        // animating it as part of a stage switch — the visible half of the "⌘E throws me out
        // of my desktop" bug.
        becomesKeyOnlyIfNeeded = false
        worksWhenModal = true
        collectionBehavior.insert(.stationary)
    }

    /// Keeps the overlay glued to the screen it opened on, instead of being nudged around by
    /// the window server when the frame is the full screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
