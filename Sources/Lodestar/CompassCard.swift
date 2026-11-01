import AppKit
import Foundation
import RadialCore

/// What is printed on the card, and the things that sit proud of it.
///
/// Split out from the case because it is a different material with different rules: paper is
/// flat and its ink follows the depth scale, while a slice's wash has to stay behind the ink
/// it is lighting up.
extension CompassRenderer {

    // MARK: - Printing

    func drawCardPrinting(in context: CGContext, state: State, metrics: CompassMetrics) {
        let z = metrics.cardDepth
        let alpha = CGFloat(state.contentAlpha)
        let layout = layout(for: state)

        drawGuilloche(in: context, state: state, metrics: metrics, alpha: alpha)
        drawScale(in: context, state: state, metrics: metrics, alpha: alpha)
        drawSectorRules(in: context, state: state, metrics: metrics, alpha: alpha)
        if state.showsNumbers {
            drawNumerals(in: context, state: state, metrics: metrics, layout: layout)
        }

        // Quadrant pips, in the gaps between the numerals.
        for degrees in [45.0, 135.0, 225.0, 315.0] {
            let angle = CGFloat(degrees) * .pi / 180
            let anchor = state.camera.project(
                x: metrics.numeralRadius * sin(angle),
                y: -metrics.numeralRadius * cos(angle),
                z: z
            )
            drawText(
                "·",
                at: anchor,
                scale: inkScale(at: Point3D(radius: metrics.numeralRadius, angle: angle), state),
                font: CompassTheme.serif(max(7, metrics.cardRadius * 0.050)),
                colour: CompassTheme.inkRule.withAlphaComponent(0.50 * alpha),
                in: context
            )
        }
    }

    /// Fine concentric circles in the margin between the sectors and the scale — the engraved
    /// band that stops the card reading as a blank disc with wedges printed on it.
    private func drawGuilloche(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        for index in 0..<8 {
            let radius = metrics.sectorOutset + metrics.cardRadius * (0.005 + CGFloat(index) * 0.0075)
            let ring = (0...120).map { step -> CGPoint in
                let angle = CGFloat(step) / 120 * 2 * .pi
                return state.camera.project(x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth)
            }
            stroke(ring, context,
                   CompassTheme.inkRule.withAlphaComponent((0.16 - CGFloat(index) * 0.012) * alpha),
                   width: 0.7)
        }
    }

    /// The printed degree scale, interrupted at each slot's bearing.
    ///
    /// The interruptions are not decoration: they are the gate each slot numeral sits in, and
    /// they are what let the numerals live on cream paper (9.3:1) instead of on brass (4.3:1).
    /// These digits are the keyboard shortcut, so they are the least affordable thing on the
    /// dial to misread.
    private func drawScale(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        let z = metrics.cardDepth
        let sliceCount = max(1, state.slices.count)
        let stepDegrees = 360.0 / Double(sliceCount)

        for degrees in stride(from: 0, to: 360, by: CompassTheme.scaleStepDegrees) {
            let bearing = Double(degrees)
            var inGate = false
            for index in 0..<sliceCount {
                let centre = Double(index) * stepDegrees
                var delta = abs(bearing - centre).truncatingRemainder(dividingBy: 360)
                delta = min(delta, 360 - delta)
                if delta < stepDegrees * Double(CompassTheme.numeralGateHalf) {
                    inGate = true
                    break
                }
            }
            if inGate { continue }

            let angle = CGFloat(degrees) * .pi / 180
            let major = degrees % 15 == 0
            let inner = metrics.scaleInset + metrics.cardRadius * (major ? 0.008 : 0.032)
            let outer = metrics.scaleOutset
            let from = state.camera.project(x: inner * sin(angle), y: -inner * cos(angle), z: z)
            let to = state.camera.project(x: outer * sin(angle), y: -outer * cos(angle), z: z)
            line(from, to, context,
                 CompassTheme.inkRule.withAlphaComponent((major ? 0.55 : 0.26) * alpha),
                 width: major ? 1.05 : 0.7)
        }
    }

    /// The walls between slices: a dark hairline with a lit companion, so they read as cut
    /// into the paper rather than drawn over it.
    private func drawSectorRules(in context: CGContext, state: State, metrics: CompassMetrics, alpha: CGFloat) {
        let z = metrics.cardDepth
        let count = max(1, state.slices.count)
        let step = 2 * CGFloat.pi / CGFloat(count)
        for index in 0..<count {
            let angle = CGFloat(index) * step - step / 2
            let innerY = -(metrics.hubRadius + metrics.cardRadius * 0.02) * cos(angle)
            for (offset, colour, width) in [
                (CGFloat(1.7), NSColor.white.withAlphaComponent(0.40 * alpha), CGFloat(1.25)),
                (CGFloat(0), CompassTheme.inkRule.withAlphaComponent(0.42 * alpha), CGFloat(1.1)),
            ] {
                let from = state.camera.project(
                    x: (metrics.hubRadius + metrics.cardRadius * 0.02) * sin(angle),
                    y: innerY + offset,
                    z: z
                )
                let to = state.camera.project(
                    x: metrics.sectorOutset * sin(angle),
                    y: -metrics.sectorOutset * cos(angle) + offset,
                    z: z
                )
                line(from, to, context, colour, width: width)
            }
        }
    }

    /// The slot numerals, in their gates. The loudest ink on the card, because they are what
    /// the keyboard drives.
    private func drawNumerals(
        in context: CGContext,
        state: State,
        metrics: CompassMetrics,
        layout: RadialLayout
    ) {
        for index in 0..<max(1, state.slices.count) {
            let angle = layout.centerAngle(of: index)
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            let point = Point3D(radius: metrics.numeralRadius, angle: angle)
            let anchor = state.camera.project(x: point.x, y: point.y, z: metrics.cardDepth)
            drawText(
                RadialLayout.keyLabel(forSlice: index),
                at: anchor,
                scale: inkScale(at: point, state),
                font: CompassTheme.serif(metrics.numeralFontSize, .semibold),
                colour: hover > 0.3
                    ? CompassTheme.vermilion.withAlphaComponent(0.55 + 0.45 * Double(hover))
                    : CompassTheme.ink.withAlphaComponent(0.94),
                in: context
            )
        }
    }

    // MARK: - Slices

    /// The aimed wedge's wash. Warm light on paper rather than a lit surface: the card is the
    /// material, so hovering has to read as a highlight washing over print.
    func drawSliceWash(in context: CGContext, state: State, metrics: CompassMetrics) {
        let layout = layout(for: state)
        let alpha = CGFloat(state.contentAlpha)
        for index in 0..<max(1, state.slices.count) {
            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0
            guard hover > 0.008 else { continue }
            let path = wedge(
                index: index,
                inset: layout.step * 0.045,
                inner: metrics.sectorInset,
                outer: metrics.sectorOutset,
                layout: layout,
                state
            )
            context.saveGState()
            context.addPath(path)
            context.clip()
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.808, green: 0.647, blue: 0.365, alpha: 1)
                        .withAlphaComponent(0.30 * hover * alpha).cgColor,
                    NSColor(calibratedRed: 0.847, green: 0.706, blue: 0.424, alpha: 1)
                        .withAlphaComponent(0.24 * hover * alpha).cgColor,
                    NSColor(calibratedRed: 0.902, green: 0.784, blue: 0.549, alpha: 1)
                        .withAlphaComponent(0.10 * hover * alpha).cgColor,
                ] as CFArray,
                locations: [0, 0.62, 1]
            ) {
                context.drawRadialGradient(
                    gradient,
                    startCenter: .zero,
                    startRadius: metrics.sectorInset,
                    endCenter: .zero,
                    endRadius: metrics.sectorOutset,
                    options: []
                )
            }
            context.restoreGState()

            // A vermilion rule along the aimed wedge's rim, so the aim has a crisp edge as well
            // as a wash — the wash alone is ambiguous on a bright wallpaper.
            if hover > 0.25 {
                let drawn = layout.drawableRange(of: index, inset: layout.step * 0.045)
                let arc = (0...24).map { step -> CGPoint in
                    let angle = drawn.start + drawn.sweep * CGFloat(step) / 24
                    return state.camera.project(
                        x: metrics.sectorOutset * sin(angle),
                        y: -metrics.sectorOutset * cos(angle),
                        z: metrics.cardDepth
                    )
                }
                stroke(arc, context,
                       CompassTheme.vermilion.withAlphaComponent(0.70 * Double(hover) * alpha),
                       width: 1.6)
            }
        }
    }

    // MARK: - The needle

    func drawNeedle(in context: CGContext, state: State, metrics: CompassMetrics) {
        let angle = state.needleAngle
        let z = metrics.cardDepth + metrics.cardRadius * 0.004
        let tip = metrics.cardRadius * 0.78
        let tail = metrics.cardRadius * 0.62
        let halfWidth = metrics.cardRadius * 0.026

        func at(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            state.camera.project(
                x: along * sin(angle) - across * cos(angle),
                y: -along * cos(angle) - across * sin(angle),
                z: z
            )
        }

        let tipPoint = at(tip, 0)
        let leftPoint = at(0, -halfWidth)
        let backPoint = at(-tail, 0)
        let rightPoint = at(0, halfWidth)

        // A shadow a hair off, so the needle sits above the printing rather than in it.
        context.saveGState()
        context.translateBy(x: 1.1, y: 1.5)
        fill([tipPoint, leftPoint, backPoint, rightPoint], context,
             NSColor.black.withAlphaComponent(0.30))
        context.restoreGState()

        let path = CGMutablePath()
        path.addLines(between: [tipPoint, leftPoint, backPoint, rightPoint])
        path.closeSubpath()
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.vermilion.withAlphaComponent(0.8).cgColor,
                CompassTheme.vermilionLit.cgColor,
                CompassTheme.vermilion.cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: leftPoint,
                end: rightPoint,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        drawNeedleWear(in: context, at: { at($0, $1) }, tip: tip, halfWidth: halfWidth)
        context.restoreGState()

        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.50).cgColor)
        context.setLineWidth(0.8)
        context.strokePath()
        context.restoreGState()
    }

    // MARK: - Labels

    func drawSliceLabels(in context: CGContext, state: State, metrics: CompassMetrics) {
        let layout = layout(for: state)
        let alpha = CGFloat(state.contentAlpha)
        let pageShift = CGFloat((1 - Easing.outCubic(min(1, max(0, state.pageAlpha)))) * 9)
        // Where the sweep's leading edge is, as a fraction of a turn clockwise from 12 o'clock. It is
        // the same easing `drawSweep` uses, so each label lights as the edge reaches its bearing.
        let edge = Easing.outQuint(min(1, max(0, state.sweep)))
        let size = metrics.labelFontSize(sliceCount: state.slices.count)
        let radius = metrics.labelRadius

        for index in 0..<max(1, state.slices.count) {
            guard let bookmark = state.slices[safe: index] else { continue }
            let angle = layout.centerAngle(of: index)
            let anchor = state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth
            )
            let scale = inkScale(at: Point3D(radius: radius, angle: angle), state)

            let hover = index < state.hover.count ? min(1, max(0, state.hover[index])) : 0

            // The labels come in clockwise with the sweep. The reveal is measured against the edge scaled
            // by 1.22, so the last slot (a bearing under one turn) is fully inked before the sweep settles,
            // and slot 1 (bearing 0) starts dark. A hovered label is never dimmed by that.
            let bearing = Double(RadialLayout.normalize(angle)) / (2 * .pi)
            let revealed = Easing.smoothstep(min(1, max(0, (1.22 * edge - bearing) / 0.22)))
            let labelAlpha = alpha * CGFloat(max(Double(hover), revealed))

            let label = fittedLabel(
                bookmark.displayTitle,
                size: size,
                index: index,
                radius: radius,
                layout: layout,
                metrics: metrics
            )

            context.saveGState()
            // Clip to the wedge: glyph metrics vary with the font actually installed, and the
            // wedge is the authority on where a slice ends.
            context.addPath(wedge(
                index: index,
                inset: 0.05,
                inner: metrics.sectorInset,
                outer: metrics.sectorOutset,
                layout: layout,
                state
            ))
            context.clip()

            let box = CGRect(
                x: anchor.x - label.width / 2,
                y: anchor.y - label.height / 2 + pageShift,
                width: label.width,
                height: label.height
            )
            // Halo first, ink on top. The needle passes under the aimed name, and dark ink on
            // vermilion is unreadable without a pale rim to lift the letters off it.
            draw(squashed: label.halo(alpha: labelAlpha), in: box, scale: scale, context: context)
            draw(squashed: label.ink(alpha: labelAlpha), in: box, scale: scale, context: context)
            context.restoreGState()
        }
    }

    /// One wedge name, laid out at the page's shared size.
    private struct WedgeLabel {
        let text: String
        let size: CGFloat
        let wraps: Bool
        let width: CGFloat
        let height: CGFloat

        private func attributed(_ attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
            var all = attributes
            all[.font] = CompassTheme.label(size)
            all[.paragraphStyle] = paragraph
            return NSAttributedString(string: text, attributes: all)
        }

        func ink(alpha: CGFloat) -> NSAttributedString {
            attributed([.foregroundColor: CompassTheme.ink.withAlphaComponent(alpha)])
        }

        /// Stroke-only copy in paper colour. A positive `strokeWidth` draws the outline alone.
        func halo(alpha: CGFloat) -> NSAttributedString {
            attributed([
                .foregroundColor: NSColor.clear,
                .strokeColor: CompassTheme.paperLit.withAlphaComponent(0.78 * alpha),
                .strokeWidth: 18,
            ])
        }
    }

    /// Lays a name out at `size`: one line if the wedge has the room, otherwise two lines at
    /// the *same* size, with truncation only as the backstop.
    ///
    /// The old approach shrank the type until it fitted, which is what made labels differ in
    /// size. Here the size is fixed and the wedge's room is spent in height instead.
    private func fittedLabel(
        _ text: String,
        size: CGFloat,
        index: Int,
        radius: CGFloat,
        layout: RadialLayout,
        metrics: CompassMetrics
    ) -> WedgeLabel {
        let font = CompassTheme.label(size)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let cap = metrics.cardRadius * 0.60

        func room(lines: CGFloat) -> CGFloat {
            let limit = layout.labelWidthLimit(for: index, radius: radius, height: lineHeight * lines, pad: metrics.labelPad)
            return max(34, min(limit, cap))
        }
        func width(_ string: String) -> CGFloat {
            ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
        }

        let oneLine = room(lines: 1)
        let whole = width(text)
        if whole <= oneLine {
            return WedgeLabel(text: text, size: size, wraps: false, width: oneLine, height: lineHeight)
        }

        // Two lines only help if every word fits on one; a single long word has to truncate
        // on its own line rather than break mid-word.
        let twoLines = room(lines: 2)
        let longest = text.split(separator: " ").map { width(String($0)) }.max() ?? whole
        if longest <= twoLines, text.contains(" ") {
            return WedgeLabel(text: text, size: size, wraps: true, width: twoLines, height: lineHeight * 2)
        }
        return WedgeLabel(text: text, size: size, wraps: false, width: oneLine, height: lineHeight)
    }

    // MARK: - Hub

    /// The centre boss: a short brass cylinder standing on the card, with the readout window
    /// sunk into its top.
    ///
    /// It has real height so the lean shows on it. The wall comes into view on the side the case
    /// tips toward, the top slides against the print, and everything on the top (the readout and
    /// the ✕) is laid on that face with the camera's own foreshortening instead of being stamped
    /// flat on the screen.
    func drawHub(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.hubRadius
        let hover = min(1, max(0, state.hubHover))
        let base = metrics.cardDepth
        let top = base + metrics.hubHeight
        let well = top - metrics.hubHeight * 0.30
        let camera = state.camera

        drawHubWall(in: context, state: state, metrics: metrics, base: base, top: top)

        let boss = CGMutablePath()
        boss.addLines(between: circle(radius, state, z: top))
        boss.closeSubpath()
        let crown = camera.project(x: 0, y: 0, z: top)

        context.saveGState()
        context.addPath(boss)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.34, 0.72, 1]
        ) {
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: crown.x - radius * 0.34, y: crown.y - radius * 0.42),
                startRadius: radius * 0.05,
                endCenter: crown,
                endRadius: radius * 1.10,
                options: []
            )
            context.resetClip()
        }
        context.restoreGState()
        drawHubWear(in: context, state: state, metrics: metrics, boss: boss, z: top)

        // The turned edge: a bright line on the lit side, the dark outline all the way round.
        context.saveGState()
        context.addPath(boss)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()

        // The readout window, sunk below the top face.
        let window = CGMutablePath()
        window.addLines(between: circle(metrics.hubWindowRadius, state, z: well))
        window.closeSubpath()
        context.saveGState()
        context.addPath(window)
        context.setFillColor(CompassTheme.hubWindow.cgColor)
        context.fillPath()
        context.addPath(window)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.10 + 0.20 * Double(hover)).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()

        // Everything in the window lies on its floor: map a unit square of card space through the
        // camera, so the numerals squash and shear with the lean like the rest of the print.
        let origin = camera.project(x: 0, y: 0, z: well)
        let unitX = camera.project(x: 1, y: 0, z: well)
        let unitY = camera.project(x: 0, y: 1, z: well)
        let floor = CGAffineTransform(
            a: unitX.x - origin.x, b: unitX.y - origin.y,
            c: unitY.x - origin.x, d: unitY.y - origin.y,
            tx: origin.x, ty: origin.y
        )

        context.saveGState()
        context.concatenate(floor)
        let aimed = state.hoveredSlice
        let readout = aimed.map { String(format: "%02d", $0 + 1) } ?? "–"
        drawText(
            readout,
            at: .zero,
            scale: 1,
            font: CompassTheme.serif(radius * 0.62, .semibold),
            colour: CompassTheme.hubWindowInk,
            in: context
        )

        // Close affordance: an engraved ✕ that appears only when the hub is aimed at.
        if hover > 0.02 {
            let arm = radius * 0.30
            context.rotate(by: hover * .pi / 4)
            context.setStrokeColor(CompassTheme.hubWindowInk.withAlphaComponent(0.92 * Double(hover)).cgColor)
            context.setLineWidth(max(1.5, radius * 0.055))
            context.setLineCap(.round)
            context.move(to: CGPoint(x: -arm, y: -arm))
            context.addLine(to: CGPoint(x: arm, y: arm))
            context.move(to: CGPoint(x: arm, y: -arm))
            context.addLine(to: CGPoint(x: -arm, y: arm))
            context.strokePath()
        }
        context.restoreGState()
    }

    /// The boss's side, and the shadow it throws on the card.
    ///
    /// Only the segments facing the viewer are filled, so a level compass shows no wall at all
    /// and the lean brings it into view on the near side. The quads go into one path and fill
    /// once, which keeps seams from showing between neighbours.
    private func drawHubWall(
        in context: CGContext,
        state: State,
        metrics: CompassMetrics,
        base: CGFloat,
        top: CGFloat
    ) {
        let radius = metrics.hubRadius
        let lift = metrics.hubHeight
        let camera = state.camera

        // Light from the upper left, so the shadow falls down and to the right. Layered
        // offsets stand in for a blur.
        for (reach, alpha) in [(CGFloat(0.85), CGFloat(0.11)), (CGFloat(0.55), CGFloat(0.11)), (CGFloat(0.25), CGFloat(0.11))] {
            let shadow = CGMutablePath()
            shadow.addLines(between: circle(radius * (1 + 0.04 * reach), state, z: base).map {
                CGPoint(x: $0.x + lift * 0.9 * reach, y: $0.y + lift * 1.2 * reach)
            })
            shadow.closeSubpath()
            context.addPath(shadow)
            context.setFillColor(NSColor.black.withAlphaComponent(alpha).cgColor)
            context.fillPath()
        }

        let steps = 96
        let wall = CGMutablePath()
        for step in 0..<steps {
            let a0 = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let a1 = CGFloat(step + 1) / CGFloat(steps) * 2 * .pi
            let mid = (a0 + a1) / 2
            let facing = camera.rotate(Point3D(x: sin(mid), y: -cos(mid), z: 0)).z
            guard facing > 1e-4 else { continue }
            wall.addLines(between: [
                camera.project(x: radius * sin(a0), y: -radius * cos(a0), z: top),
                camera.project(x: radius * sin(a1), y: -radius * cos(a1), z: top),
                camera.project(x: radius * sin(a1), y: -radius * cos(a1), z: base),
                camera.project(x: radius * sin(a0), y: -radius * cos(a0), z: base),
            ])
            wall.closeSubpath()
        }
        guard !wall.isEmpty, let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        context.saveGState()
        context.addPath(wall)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: -radius, y: -radius),
            end: CGPoint(x: radius, y: radius),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    // MARK: - Opening sweep

    /// One orchestrated gesture as the compass appears: a needle of light runs once around the
    /// card and expires, explaining the clockwise order in a single beat.
    func drawSweep(in context: CGContext, state: State, metrics: CompassMetrics) {
        let progress = state.sweep
        guard progress > 0.002, progress < 0.998 else { return }
        let eased = Easing.outQuint(min(1, progress))
        // Slot 1 sits at 12 o'clock (`RadialLayout.centerAngle(of: 0)` is 0), so the sweep starts there
        // and runs clockwise, the same way the slots are numbered.
        let start: CGFloat = 0
        let end = start + 2 * .pi * CGFloat(eased)
        let radius = metrics.numeralRadius
        let fade = CGFloat(1 - Easing.outCubic(min(1, progress)))

        let arc = (0...48).map { step -> CGPoint in
            let angle = start + (end - start) * CGFloat(step) / 48
            return state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: metrics.cardDepth
            )
        }
        stroke(arc, context,
               CompassTheme.vermilion.withAlphaComponent(0.85 * fade * CGFloat(state.contentAlpha)),
               width: 2)
    }

    // MARK: - Helpers

    /// The layout the dial has always used, so labels, hit testing and keyboard firing cannot
    /// disagree about where a slice is.
    private func layout(for state: State) -> RadialLayout {
        RadialLayout(
            sliceCount: max(1, state.slices.count),
            centerRadius: state.metrics.hubRadius,
            outerRadius: state.metrics.sectorOutset
        )
    }

    /// Draws type at the depth scale of its anchor and squeezes it vertically, so it lies on
    /// the leaning card instead of floating above it.
    private func draw(squashed string: NSAttributedString, in box: CGRect, scale: CGFloat, context: CGContext) {
        context.saveGState()
        context.translateBy(x: box.midX, y: box.midY)
        context.scaleBy(x: 1, y: max(0.5, scale))
        string.draw(with: CGRect(
            x: -box.width / 2,
            y: -box.height / 2,
            width: box.width,
            height: box.height
        ), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        context.restoreGState()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
