import AppKit
import Foundation
import RadialCore

/// Draws and animates the compass.
///
/// Geometry comes from `CompassMetrics`, `CompassCamera` and `RadialLayout` (all unit tested);
/// this view owns pixels, springs and input, and nothing else. Three rules keep it honest:
///
/// 1. Every animated value is a spring or an eased scalar, so nothing moves linearly.
/// 2. The aimed wedge is the only element allowed to be saturated, and it *washes* — the card
///    is paper, so aiming lights the print rather than lifting a panel.
/// 3. The lid is a real pivot, not an animation: it swings on `CompassLid`, and the pointer
///    cannot reach the card until the lid has actually cleared it.
final class RadialMenuView: NSView {

    // MARK: - Model

    private(set) var bookmarks: [Bookmark] = []
    private(set) var page = 0
    private(set) var paging = RadialPaging(total: 0)
    var showsNumbers = true
    var menuRadius: CGFloat = 200

    var onActivate: ((Bookmark) -> Void)?
    var onClose: (() -> Void)?
    var onClickOutside: (() -> Void)?

    // MARK: - Embedding

    /// Set when the compass lives inside a window (the manager's Dial tab) rather than on the
    /// full-screen overlay: no backdrop, no hint row, and it sizes itself to fit its own bounds.
    var isEmbedded = false
    /// A non-interactive compass (the Settings preview) draws and tilts to nothing: it ignores
    /// the pointer entirely.
    var isInteractive = true
    /// The radius the user asked for. While embedded `menuRadius` is the fitted result, which can
    /// be smaller: the setting is an upper bound, as it is on the overlay.
    var requestedRadius: CGFloat = 200
    /// Told which slice the pointer is over (nil when it leaves), so a SwiftUI sidebar can follow.
    var onHoverSlice: ((Int?) -> Void)?

    // MARK: - Animation state

    private let driver = FrameDriver()
    /// How far the box has risen: 0 when hidden, 1 when fully open. Closing aims a little below
    /// zero (see `dismiss`), so the spring crosses zero decisively instead of trailing off.
    private var openProgress = SpringValue(0, stiffness: 300, damping: 30)
    /// The compass sweep that plays once as the dial appears.
    private var sweepProgress = SpringValue(0, stiffness: 300, damping: 34)
    private var sliceHover: [SpringValue] = []
    private var slicePress: [SpringValue] = []
    private var hubHover = SpringValue(0, stiffness: 380, damping: 28)
    private var hubPress = SpringValue(0, stiffness: 500, damping: 30)
    private var pageSwap = SpringValue(0, stiffness: 420, damping: 30)
    private var needle = SpringValue(0, stiffness: 300, damping: 26)
    /// Pitch and roll of the instrument, in radians, driven by where the pointer is.
    /// Springs rather than direct assignment so the compass leans with weight instead of
    /// tracking the cursor rigidly.
    private var tiltPitch = SpringValue(0, stiffness: 170, damping: 26)
    private var tiltRoll = SpringValue(0, stiffness: 170, damping: 26)
    /// The lid, on its hinge: a small physical model, not a spring (see `LidHinge`).
    ///
    /// It is flicked on the very first frame, clears the card (0.55 open) by ~135ms, goes over
    /// vertical, falls onto its stop at ~290ms and gives one small bounce, and is at rest by
    /// ~520ms. The box finishes rising by ~250ms, so the stop lands just as the case settles: the
    /// two read as one gesture, and the lid is never behind the box. Closing is a push, and the
    /// lid is shut by ~175ms, before the box is gone at ~200ms.
    ///
    /// The stop is also what the hand feels: `advance` turns each landing into a tap on the case.
    private var hinge = LidHinge()
    /// Set once the sweep has been released, so the opening beat only ever plays one time.
    private var sweepStarted = false
    /// The needle is held counter-clockwise of its aim until the card is reachable, so it swings onto
    /// the aim as the card is revealed. Only its value is held: the target is always the real aim.
    private var needleParked = false
    /// Set while the needle is on its underdamped release spring, until it settles or the pointer
    /// moves to another slice.
    private var needleSettling = false
    /// How far counter-clockwise the needle is held while parked.
    private static let needleParkOffset: Double = 0.5
    /// Fired when a closing motion actually finishes, instead of after a guessed delay.
    private var closeCompletion: (() -> Void)?
    /// Where the hub was on the last `present()`. A summon that lands on the same spot while the box
    /// is still up is a reversal rather than a fresh open.
    private var lastPresentedRingCenter: CGPoint?

    private let renderer = CompassRenderer()

    private var hoveredSlice: Int?
    private var pressedSlice: Int?
    private var pressedHub = false
    private var pressStartedOutside = false
    private var trackingArea: NSTrackingArea?
    private var isClosing = false

    /// Where the hub sits in view coordinates.
    var ringCenter: CGPoint?

    private var ringOrigin: CGPoint {
        ringCenter ?? CGPoint(x: bounds.midX, y: bounds.midY)
    }

    /// The instrument's proportions. `menuRadius` is the *card* radius, which is the one number
    /// the rest of the object is built from.
    private var metrics: CompassMetrics {
        CompassMetrics(cardRadius: menuRadius)
    }

    /// The same layout the hit test uses, so labels and clicks cannot disagree.
    private var ringLayout: RadialLayout {
        RadialLayout(
            sliceCount: max(1, bookmarks.count),
            centerRadius: metrics.hubRadius,
            outerRadius: metrics.sectorOutset
        )
    }

    /// How far the box has risen, clamped to 0...1. Closing aims below zero and opening overshoots
    /// past one, so the clamp keeps the set-down terms inside their ranges.
    private var presence: Double { min(1, max(0, openProgress.value)) }

    /// How far the instrument leans back while the box is still rising: about 8°, gone once open.
    private static let setDownTipBack: Double = 0.14
    /// The steepest lean allowed in total, tip-back included. Past about 20° the far wedges
    /// foreshorten into slivers (see `RadialTilt`).
    private static let maxTotalPitch: CGFloat = 20 * .pi / 180

    /// The live tilt: the two springs, plus the set-down tip-back. The tip-back lives here rather
    /// than in the springs, so the renderer and every unprojection read the same lean.
    private var tilt: RadialTilt {
        let pitch = CGFloat(tiltPitch.value + (1 - presence) * RadialMenuView.setDownTipBack)
        return RadialTilt(
            pitch: min(RadialMenuView.maxTotalPitch, max(-RadialMenuView.maxTotalPitch, pitch)),
            roll: CGFloat(tiltRoll.value),
            eyeDistance: menuRadius * RadialTilt.eyeDistanceRatio
        )
    }

    /// The camera, derived from the same tilt the inverse uses.
    private var camera: CompassCamera { CompassCamera(tilt: tilt) }

    private var lid: CompassLid {
        CompassLid(metrics: metrics, openness: CGFloat(hinge.openness))
    }

    /// How hard a landing on the lid's stop taps the case, in tilt velocity per unit of impact
    /// speed. A landing at the usual 5.5 rad/s tips the case about a degree, and the tilt spring
    /// settles it back.
    private static let stopTapTilt: Double = 0.12

    /// Whether the pointer may act on the card yet.
    ///
    /// The lid starts shut and clears the card (0.55 open) about 75ms after `present()`. Without
    /// this gate a fast summon followed by an immediate click would fire whatever slice happened
    /// to be under the cursor while the box was still opening — the one failure mode a menu like
    /// this cannot have.
    private var cardIsReachable: Bool { lid.revealsCard }

    /// Sets the tilt the pointer asks for, and lets the springs do the rest.
    private func aimTilt(at point: CGPoint, animated: Bool) {
        // Ease in relative to the *ring* radius (wedges start where the hub ends), but use the
        // same eye distance the renderer uses, so the angle solved here produces exactly the
        // perspective the projection applies.
        let target = RadialTilt(
            leaningToward: point,
            radius: menuRadius * 1.1,
            eyeDistance: menuRadius * RadialTilt.eyeDistanceRatio
        )
        if animated {
            tiltPitch.target = Double(target.pitch)
            tiltRoll.target = Double(target.roll)
        } else {
            tiltPitch.snap(to: Double(target.pitch))
            tiltRoll.snap(to: Double(target.roll))
        }
    }

    private var scaleFactor: CGFloat { max(0.78, min(1.0, menuRadius / 200)) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        fitEmbedded()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        fitEmbedded()
    }

    /// Sizes the instrument to this view, lid open, and centres it vertically.
    ///
    /// The overlay does the same sum against the screen (`RadialController.show`); here the
    /// bounds are the window's, so the open compass is fitted to them in both directions.
    func fitEmbedded() {
        guard isEmbedded, bounds.height > 40, bounds.width > 40 else { return }
        var fitted = CompassMetrics(cardRadius: requestedRadius).fitted(toHeight: bounds.height - 12)
        // The lid, not the case, is the widest part once it is open.
        let widthRatio = max(fitted.caseRadius, fitted.lidHalfWidth()) / fitted.cardRadius
        let widest = (bounds.width - 16) / 2 / widthRatio
        if fitted.cardRadius > widest, widest > 40 {
            fitted = CompassMetrics(cardRadius: widest)
        }
        menuRadius = fitted.cardRadius
        let top = max(0, (bounds.height - fitted.openHeight) / 2)
        ringCenter = CGPoint(x: bounds.midX, y: top + fitted.lidReach())
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isInteractive ? super.hitTest(point) : nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    func configure(bookmarks: [Bookmark], page: Int, paging: RadialPaging, showsNumbers: Bool, radius: CGFloat) {
        self.bookmarks = bookmarks
        self.page = page
        self.paging = paging
        self.showsNumbers = showsNumbers
        self.menuRadius = radius
        resizeSprings(count: bookmarks.count)
        resetHover()
        needsDisplay = true
    }

    /// Whether the hub is where the last presentation put it, to within half a point. A summon
    /// anywhere else (the pointer moved, or the screen changed) is a fresh open, not a reversal.
    private var ringCenterIsUnchanged: Bool {
        guard let previous = lastPresentedRingCenter, let current = ringCenter else { return false }
        return abs(previous.x - current.x) <= 0.5 && abs(previous.y - current.y) <= 0.5
    }

    func present() {
        // Summoned again while the box is still up (closing, or not yet fully down) at the same spot:
        // that is a reversal, and the springs carry on from where they are.
        let reversing = (isClosing || openProgress.value > 0.02) && ringCenterIsUnchanged
        lastPresentedRingCenter = ringCenter
        // Either way the pending close is abandoned. Its completion must not fire and tear down the
        // menu that is now being shown.
        isClosing = false
        closeCompletion = nil
        // Opening tuning. `dismiss(animated:)` swaps in the closing constants, so they are set
        // again here every time.
        openProgress.stiffness = 300
        openProgress.damping = 30

        if reversing {
            // Nothing is snapped or kicked. A sweep that finished stays finished, a sweep that had not
            // started starts through its usual gate, and the needle keeps the state it is in. The
            // lid is flicked open from wherever it is, with enough speed to clear vertical.
            openProgress.target = 1
            hinge.release()
            beginAnimating()
            return
        }

        openProgress.snap(to: 0)
        sweepProgress.snap(to: 0)
        hinge.snapShut()
        sweepStarted = false
        needle.stiffness = 300
        needle.damping = 26
        needleSettling = false
        // Everything moves from this instant. There used to be a 0.28s timer here that held the
        // print back until the lid had cleared; because the lid spring also started from rest,
        // the visible result was the box appearing, pausing, and *then* opening. The card is
        // now revealed by the lid's own angle (`printProgress`), so the two cannot desynchronise
        // and there is nothing to wait for.
        openProgress.target = 1
        // The box is kicked rather than released from rest. A spring at rest spends its first
        // frames accelerating from zero, which reads as the box appearing and then pausing before
        // anything flips. The lid needs no kick: the latch lets go with a pop on the first frame,
        // so the box and the lid leave together, in one gesture.
        openProgress.kick(velocity: 6)
        hinge.release()
        needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        primeHoverFromPointer()
        // Park the needle under the lid. The aim (the target) is kept, and only the value is moved
        // back, so nothing has to re-aim it when the card is revealed.
        let aim = needle.target
        needle.snap(to: aim - RadialMenuView.needleParkOffset)
        needle.target = aim
        needleParked = true
        beginAnimating()
    }

    /// How much of the card's print is visible.
    ///
    /// Derived from the lid angle rather than from a clock, so the print can never glow through
    /// a shut lid or lag behind one that has already cleared.
    ///
    /// The window is wide on purpose. A narrow one (the first attempt spanned 0.18...0.52 of
    /// the lid's travel) put the whole reveal inside ~35ms, which reads as a flicker rather
    /// than a fade, because the lid's spring crosses that band almost instantly. Starting while
    /// the lid still hides the card costs nothing — the lid is painted over everything until it
    /// swings clear — and finishing near the lid's landing lets the print resolve with it.
    private var printProgress: Double {
        // Saturates at 0.74 open (about 89°), so the lid's bounce on its stop, which only moves it
        // a few degrees, cannot make the print flicker.
        let reveal = (hinge.openness - 0.12) / 0.62
        return min(1, max(0, reveal))
    }

    /// The dial opens under the cursor, so whatever slice is there should already be lit
    /// and the needle should already point at it.
    private func primeHoverFromPointer() {
        // A compass that ignores the pointer starts level, aimed at slot one.
        guard isInteractive else {
            needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
            return
        }
        let point = convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)
        let relative = relativePoint(point)
        aimTilt(at: relative, animated: false)
        let hit = ringLayout.hitTest(relative)
        switch hit {
        case .slice(let index) where index < bookmarks.count:
            hoveredSlice = index
            needle.snap(to: Double(ringLayout.centerAngle(of: index)))
            hubHover.snap(to: 0)
        case .close:
            hoveredSlice = nil
            hubHover.snap(to: 1)
        default:
            hoveredSlice = nil
            hubHover.snap(to: 0)
            needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        }
        for index in sliceHover.indices {
            sliceHover[index].snap(to: index == hoveredSlice ? 1 : 0)
        }
        hubHover.target = hit == .close ? 1 : 0
    }

    func dismiss(animated: Bool, completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        hoveredSlice = nil
        pressedSlice = nil
        pressedHub = false
        // A press that began before the close must not resolve as an outside click on a menu that was
        // summoned again while the close was still running.
        pressStartedOutside = false
        closeCompletion = completion
        releasePressSprings()
        if animated {
            // Closing has no kick and is quicker than opening. The lid shuts first, and the box
            // sinks through zero after it. Both targets sit below rest, so each spring crosses its
            // threshold decisively instead of easing into it.
            openProgress.stiffness = 380
            openProgress.damping = 34
            openProgress.target = -0.06
            hinge.shut()
            beginAnimating()
        } else {
            openProgress.snap(to: 0)
            hinge.snapShut()
            closeCompletion = nil
            isClosing = false
            completion?()
        }
    }

    func updatePage(bookmarks: [Bookmark], page: Int, paging: RadialPaging) {
        self.bookmarks = bookmarks
        self.page = page
        self.paging = paging
        resizeSprings(count: bookmarks.count)
        resetHover()
        needle.snap(to: Double(ringLayout.centerAngle(of: 0)))
        pageSwap.snap(to: 0)
        pageSwap.target = 1
        beginAnimating()
    }

    private func resizeSprings(count: Int) {
        if sliceHover.count != count {
            sliceHover = (0..<count).map { _ in SpringValue(0, stiffness: 420, damping: 30) }
            slicePress = (0..<count).map { _ in SpringValue(0, stiffness: 520, damping: 34) }
        }
    }

    private func resetHover() {
        hoveredSlice = nil
        for index in sliceHover.indices {
            sliceHover[index].target = 0
            slicePress[index].target = 0
        }
        hubHover.target = 0
    }

    // MARK: - Animation loop

    private func beginAnimating() {
        driver.start { [weak self] dt in
            self?.advance(dt)
        }
    }

    private func advance(_ dt: Double) {
        var moving = false

        openProgress.step(dt)
        sweepProgress.step(dt)
        hubHover.step(dt)
        hubPress.step(dt)
        pageSwap.step(dt)
        // A parked needle holds its value until the card is reachable.
        if !needleParked { needle.step(dt) }
        tiltPitch.step(dt)
        tiltRoll.step(dt)
        // The lid's landing on a stop taps the case. Only the opening one is felt: the closing one
        // happens as the box is already going.
        let landing = hinge.step(dt)
        if landing > 0, !isClosing {
            tiltPitch.impulse(landing * RadialMenuView.stopTapTilt)
        }

        // The sweep is part of the opening gesture, not a separate beat: it fires the moment
        // the card is revealed behind the lid, so the print, the needle of light and the lid
        // landing all resolve together.
        if !sweepStarted, !isClosing, printProgress >= 0.98 {
            sweepStarted = true
            sweepProgress.target = 1
        }

        // The needle is released the first frame the card is reachable, on a lightly underdamped
        // spring (zeta about 0.5): it overshoots its aim by about 15%, roughly 4 degrees, and settles.
        if needleParked, cardIsReachable {
            needleParked = false
            needleSettling = true
            needle.stiffness = 220
            needle.damping = 15
        }
        if needleSettling, !needle.isAnimating {
            endNeedleSettle()
        }

        // A parked needle is not moving on its own: the lid is what it is waiting for, and that
        // keeps the driver running.
        if openProgress.isAnimating || sweepProgress.isAnimating
            || hubHover.isAnimating || hubPress.isAnimating || pageSwap.isAnimating
            || (needle.isAnimating && !needleParked)
            || tiltPitch.isAnimating || tiltRoll.isAnimating || hinge.isMoving {
            moving = true
        }

        for index in sliceHover.indices {
            sliceHover[index].step(dt)
            slicePress[index].step(dt)
            if sliceHover[index].isAnimating || slicePress[index].isAnimating { moving = true }
        }

        needsDisplay = true

        // A closing menu is finished once the box has sunk below zero, not once every spring has
        // run out of its asymptote. Waiting for `isAnimating` held the panel on screen long after
        // the lid had shut, because a spring spends most of its life in the last few percent of
        // its travel. The close target sits just under zero (see `dismiss`), so the box crosses
        // zero at a useful speed, and at zero there is nothing left to paint.
        let closedEnough = isClosing && openProgress.value <= 0
        if !moving || closedEnough {
            driver.stop()
            if isClosing {
                // Park both springs at rest, so the ticker has nothing in flight and a later
                // wake-up cannot carry them on toward their below-zero targets.
                openProgress.snap(to: 0)
                hinge.snapShut()
                isClosing = false
                let completion = closeCompletion
                closeCompletion = nil
                completion?()
            }
        }
    }

    /// Hands the needle back to its normal spring, once it has settled or the pointer has moved on.
    private func endNeedleSettle() {
        guard needleSettling else { return }
        needleSettling = false
        needle.stiffness = 300
        needle.damping = 26
    }

    // MARK: - Pointer handling

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard isInteractive else { return }
        handlePointer(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        guard isInteractive else { return }
        if hoveredSlice != nil { endNeedleSettle() }
        if hoveredSlice != nil { onHoverSlice?(nil) }
        hoveredSlice = nil
        // Off the menu, the disc settles back to level: holding the last lean would leave it
        // tilted toward empty space while the pointer is somewhere else entirely.
        tiltPitch.target = 0
        tiltRoll.target = 0
        applyHoverTargets()
    }

    private func handlePointer(_ point: CGPoint) {
        // A closing compass takes no pointer input, so a slice cannot light up on its way out.
        guard !isClosing else { return }
        // Nothing on the card may react while the lid is still over it.
        guard cardIsReachable else {
            hoveredSlice = nil
            applyHoverTargets()
            return
        }
        // The pointer arrives in screen space, but the dial is drawn tilted and set down. Undo both
        // before hit testing, or the slice you click is not the slice under the cursor — which gets
        // worse the further from the centre you aim.
        let relative = cardPoint(point)
        aimTilt(at: relative, animated: true)
        let hit = ringLayout.hitTest(relative)

        let newHover: Int?
        switch hit {
        case .slice(let index) where index < bookmarks.count:
            newHover = index
        default:
            newHover = nil
        }

        if newHover != hoveredSlice {
            endNeedleSettle()
            hoveredSlice = newHover
            applyHoverTargets()
            onHoverSlice?(newHover)
        }
        if let newHover {
            needle.target = Double(ringLayout.centerAngle(of: newHover))
        }
        hubHover.target = hit == .close ? 1 : 0
        beginAnimating()
    }

    /// A slice fired from the keyboard should spring back out, not stay held down.
    private func releasePressSprings() {
        for index in slicePress.indices {
            slicePress[index].target = 0
        }
        hubPress.target = 0
    }

    private func applyHoverTargets() {
        for index in sliceHover.indices {
            sliceHover[index].target = (index == hoveredSlice) ? 1 : 0
        }
        beginAnimating()
    }

    override func mouseDown(with event: NSEvent) {
        // A closing compass takes no presses: nothing on it may fire or dismiss on its way out.
        guard !isClosing else { return }
        let relative = cardPoint(convert(event.locationInWindow, from: nil))
        // While the lid is still moving, a press can only dismiss: it may not fire a slice the
        // user has not seen yet. Escape is not the only way out of the opening beat.
        guard cardIsReachable else {
            pressStartedOutside = true
            return
        }
        let hit = ringLayout.hitTest(relative)

        pressStartedOutside = false
        switch hit {
        case .close:
            pressedHub = true
            hubPress.target = 1
            beginAnimating()
        case .slice(let index) where index < bookmarks.count:
            pressedSlice = index
            slicePress[index].target = 1
            beginAnimating()
        default:
            pressStartedOutside = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let relative = cardPoint(convert(event.locationInWindow, from: nil))
        guard cardIsReachable else {
            let escaped = pressStartedOutside && ringLayout.hitTest(relative) == .none
            pressStartedOutside = false
            if escaped { onClickOutside?() }
            return
        }
        let hit = ringLayout.hitTest(relative)

        let closedOnHub = pressedHub
        if pressedHub { hubPress.target = 0 }

        if let pressed = pressedSlice {
            slicePress[pressed].target = 0
            pressedSlice = nil
            // Only fire when the pointer is released over the same slice: dragging off
            // cancels, which is what people expect from a menu.
            if case .slice(let index) = hit, index == pressed, index < bookmarks.count {
                fire(index)
                releasePressSprings()
                beginAnimating()
                return
            }
        }
        beginAnimating()

        if closedOnHub {
            pressedHub = false
            pressStartedOutside = false
            if hit == .close {
                onClose?()
                return
            }
        }

        if hit == .none && pressStartedOutside {
            onClickOutside?()
        }
        pressedHub = false
        pressStartedOutside = false
    }

    private func relativePoint(_ point: CGPoint) -> CGPoint {
        let origin = ringOrigin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// The set-down scale `draw` applies about the hub.
    private var setDownScale: CGFloat { 0.965 + 0.035 * CGFloat(presence) }
    /// Screen-space lift; negative is up (the view is flipped).
    private var setDownLift: CGFloat { -CGFloat(1 - presence) * 10 * scaleFactor }
    /// A view point in card space: undo the set-down lift and scale, then the tilt.
    private func cardPoint(_ point: CGPoint) -> CGPoint {
        let r = relativePoint(point)
        return tilt.unproject(CGPoint(x: r.x / setDownScale, y: (r.y - setDownLift) / setDownScale))
    }

    private func fire(_ index: Int) {
        guard index < bookmarks.count else { return }
        onActivate?(bookmarks[index])
    }

    /// Keyboard-driven press feedback, so keys and clicks feel like the same action.
    func flashSlice(_ index: Int) {
        guard slicePress.indices.contains(index) else { return }
        slicePress[index].snap(to: 1.4)
        slicePress[index].target = 0
        beginAnimating()
    }

// MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let open = openProgress.value
        guard open > 0.001 else { return }

        let content = Easing.outCubic(printProgress)
        // The case and the scrim follow the box's own spring, not the lid or the print. The case is
        // solid once the box is half open. The spring already eases, so the scrim follows it directly:
        // an outCubic on top ran well ahead of it, putting the backdrop at about 14% on the first frame.
        let caseAlpha = Easing.smoothstep(min(1, presence / 0.5))
        let scrimAlpha = presence

        // The compass is set down in the palm rather than placed: it opens a touch smaller, higher and
        // tipped back (the tip-back is in `tilt`), then lands. All three are neutral once it is open.
        // The scale covers the scrim as well as the case, but the drop does not: the drop is applied
        // after the scrim, so the backdrop stays where it is while the instrument lands.
        let scale = setDownScale
        // The view is flipped, so +y runs down the screen and a negative offset lifts the case. The
        // drop is applied inside the scale, so it is divided by it to land at the same place on screen.
        let drop = setDownLift / scale

        context.saveGState()
        context.translateBy(x: ringOrigin.x, y: ringOrigin.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -ringOrigin.x, y: -ringOrigin.y)

        if bookmarks.isEmpty {
            if isEmbedded {
                // Nothing to draw: the window shows its own empty state.
                context.restoreGState()
                return
            }
            drawScrim(in: context, alpha: scrimAlpha)
            // The text stands in for the dial, so it lifts with the box. The backdrop does not.
            context.translateBy(x: 0, y: drop)
            drawEmptyState(alpha: content)
        } else {
            let state = CompassRenderer.State(
                metrics: metrics,
                camera: camera,
                lid: lid,
                slices: bookmarks,
                hoveredSlice: hoveredSlice,
                hover: sliceHover.map { CGFloat(min(1, max(0, $0.value))) },
                press: slicePress.map { CGFloat(min(1, max(0, $0.value))) },
                hubHover: CGFloat(min(1, max(0, hubHover.value))),
                needleAngle: CGFloat(needle.value),
                showsNumbers: showsNumbers,
                contentAlpha: content,
                caseAlpha: caseAlpha,
                scrimAlpha: isEmbedded ? 0 : scrimAlpha,
                presence: presence,
                dropOffset: drop,
                sweep: sweepProgress.value,
                pageAlpha: pageSwap.value
            )
            renderer.draw(state, in: context, at: ringOrigin)
        }

        context.restoreGState()

        // The furniture comes in last: it waits for the print to be half resolved, then rises into
        // place. The view is flipped, so +y is down the screen, and the rise starts 6pt (scaled) lower.
        let arrived = Easing.smoothstep(min(1, max(0, (printProgress - 0.5) / 0.5)))
        let furnitureCentre = CGPoint(x: ringOrigin.x, y: ringOrigin.y + CGFloat(1 - arrived) * 6 * scaleFactor)
        let furnitureAlpha = caseAlpha * arrived
        // The window draws its own pager and key hints around an embedded compass.
        guard !isEmbedded else { return }
        if paging.pageCount > 1 {
            drawPagePips(in: context, center: furnitureCentre, alpha: furnitureAlpha)
        }
        drawHints(in: context, center: furnitureCentre, alpha: furnitureAlpha)
    }

    private func drawScrim(in context: CGContext, alpha: Double) {
        let outer = max(metrics.caseRadius * 2.9, 460)
        let colours = [
            CompassTheme.shadow.withAlphaComponent(CompassTheme.backdropAlpha * CGFloat(alpha)).cgColor,
            CompassTheme.shadow.withAlphaComponent(CompassTheme.backdropMidAlpha * CGFloat(alpha)).cgColor,
            CompassTheme.shadow.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours,
            locations: [0, 0.46, 1] as [CGFloat]
        ) else { return }
        context.drawRadialGradient(
            gradient,
            startCenter: ringOrigin,
            startRadius: 0,
            endCenter: ringOrigin,
            endRadius: outer,
            options: []
        )
    }

    private func drawEmptyState(alpha: Double) {
        let title = NSAttributedString(string: "No bookmarks yet", attributes: [
            .font: CompassTheme.serif(15 * scaleFactor, .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: CGFloat(alpha)),
        ])
        let subtitle = NSAttributedString(string: "Add one from the menu bar", attributes: [
            .font: CompassTheme.serif(10.5 * scaleFactor),
            .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 0.72 * CGFloat(alpha)),
        ])
        let titleSize = title.size()
        let subtitleSize = subtitle.size()
        title.draw(at: CGPoint(x: ringOrigin.x - titleSize.width / 2, y: ringOrigin.y - 18))
        subtitle.draw(at: CGPoint(x: ringOrigin.x - subtitleSize.width / 2, y: ringOrigin.y + 4))
    }

    // MARK: Furniture around the instrument

    private func drawPagePips(in context: CGContext, center: CGPoint, alpha: Double) {
        let count = paging.pageCount
        let spacing: CGFloat = 15
        // Sits below the lanyard bow, so it can never land on the case.
        let y = center.y + metrics.lugReach + 22
        let totalWidth = CGFloat(count - 1) * spacing

        for page in 0..<count {
            let x = center.x - totalWidth / 2 + CGFloat(page) * spacing
            let isCurrent = page == self.page
            let string = NSAttributedString(string: "\(page + 1)", attributes: [
                .font: CompassTheme.serif(10 * scaleFactor, isCurrent ? .semibold : .regular),
                .foregroundColor: (isCurrent
                    ? CompassTheme.vermilionLit
                    : NSColor(calibratedWhite: 0.96, alpha: 0.62)
                ).withAlphaComponent(CGFloat(alpha)),
            ])
            let size = string.size()
            string.draw(at: CGPoint(x: x - size.width / 2, y: y - size.height / 2))
            if isCurrent {
                context.saveGState()
                context.setStrokeColor(CompassTheme.vermilionLit.withAlphaComponent(0.8 * CGFloat(alpha)).cgColor)
                context.setLineWidth(1.5)
                context.setLineCap(.round)
                context.move(to: CGPoint(x: x - 4, y: y + 8))
                context.addLine(to: CGPoint(x: x + 4, y: y + 8))
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private func drawHints(in context: CGContext, center: CGPoint, alpha: Double) {
        // The hint names the keys that are actually live: on a three-slot dial, "1–9" promises
        // six slots that do not exist.
        let keys = bookmarks.count == 1 ? "1" : "1–\(min(bookmarks.count, RadialLayout.maxSlicesPerPage))"
        let labels: [String]
        if paging.pageCount > 1 {
            labels = ["← →", keys, "esc"]
        } else {
            labels = [keys, "esc"]
        }

        let font = CompassTheme.serif(10.5 * scaleFactor, .semibold)
        let height: CGFloat = 20
        let gap: CGFloat = 7
        let widths = labels.map { label -> CGFloat in
            max(20, (label as NSString).size(withAttributes: [.font: font]).width + 14)
        }
        let total = widths.reduce(0, +) + gap * CGFloat(labels.count - 1)
        let y = center.y + metrics.lugReach + (paging.pageCount > 1 ? 48 : 44)

        var x = center.x - total / 2
        for (index, label) in labels.enumerated() {
            let width = widths[index]
            let rect = CGRect(x: x, y: y - height / 2, width: width, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
            context.saveGState()
            context.addPath(path)
            context.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.06 * CGFloat(alpha)).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.16 * CGFloat(alpha)).cgColor)
            context.setLineWidth(1)
            context.strokePath()
            context.restoreGState()

            let string = NSAttributedString(string: label, attributes: [
                .font: font,
                .foregroundColor: NSColor(calibratedWhite: 0.95, alpha: 0.70 * CGFloat(alpha)),
            ])
            let size = string.size()
            string.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))

            x += width + gap
        }
    }
}
