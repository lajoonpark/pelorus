import AppKit
import Foundation
import RadialCore

/// The hard-edged half of the instrument's wear.
///
/// `CompassGrain`'s soft blots carry the tone of age; this carries its scars. Every function
/// takes a `map` from the layer's own units to the screen, so one routine draws the same mark
/// on the leaning case, the swinging lid and the card without knowing which it is on.
///
/// The light comes from the upper left throughout, as everywhere else on the instrument. That
/// is what makes a scratch read as cut metal and a dent as a dent: a bright lip on one side, a
/// shadow on the other, and the two always the same way round.
extension CompassRenderer {

    private static let scratchDark = NSColor(calibratedRed: 0.07, green: 0.05, blue: 0.02, alpha: 1)
    private static let scratchBright = NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.74, alpha: 1)
    private static let creaseDark = NSColor(calibratedRed: 0.27, green: 0.18, blue: 0.09, alpha: 1)
    private static let creaseBright = NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.88, alpha: 1)
    private static let rustCore = NSColor(calibratedRed: 0.60, green: 0.29, blue: 0.11, alpha: 1)

    private var damage: CGFloat { CompassTheme.damageGain }

    // MARK: - Primitives

    /// Scratches and creases. A bright one is bare metal (or pale fibre) in the groove with a
    /// shadow just below it; a dark one is a deeper cut with dirt in it.
    func drawScratches(
        _ list: [CompassGrain.Scratch],
        unit: CGFloat,
        map: (CGPoint) -> CGPoint,
        bright: NSColor = CompassRenderer.scratchBright,
        dark: NSColor = CompassRenderer.scratchDark,
        in context: CGContext
    ) {
        let base = max(0.55, unit * 0.0030)
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for scratch in list {
            let path = CGMutablePath()
            path.addLines(between: scratch.points.map { map(CGPoint(x: $0.x * unit, y: $0.y * unit)) })
            let width = base * scratch.width
            let alpha = min(1, scratch.alpha * damage)
            context.setLineWidth(width)
            if scratch.bright {
                context.saveGState()
                context.translateBy(x: width * 0.9, y: width * 0.9)
                context.addPath(path)
                context.setStrokeColor(dark.withAlphaComponent(alpha * 0.7).cgColor)
                context.strokePath()
                context.restoreGState()
                context.addPath(path)
                context.setStrokeColor(bright.withAlphaComponent(alpha).cgColor)
                context.strokePath()
            } else {
                context.addPath(path)
                context.setStrokeColor(dark.withAlphaComponent(alpha).cgColor)
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    /// Dents: a shadowed wall toward the light, a lit one away from it, and a hairline round the
    /// lip.
    func drawDents(
        _ list: [CompassGrain.Blot],
        unit: CGFloat,
        map: (CGPoint) -> CGPoint,
        in context: CGContext
    ) {
        for (index, dent) in list.enumerated() {
            let centre = CGPoint(x: dent.x * unit, y: dent.y * unit)
            let radius = dent.radius * unit
            // Never a clean circle: a dent is a lumpy oval, or it reads as a rivet.
            let phase = CGFloat(index) * 2.1
            let outline = (0..<24).map { step -> CGPoint in
                let angle = CGFloat(step) / 24 * 2 * .pi
                let lump = 1 + 0.20 * sin(2 * angle + phase) + 0.12 * sin(3 * angle + phase * 1.7)
                return map(CGPoint(x: centre.x + radius * 1.3 * lump * cos(angle),
                                   y: centre.y + radius * 0.85 * lump * sin(angle)))
            }
            let box = bounds(of: outline)
            let reach = max(box.width, box.height) / 2
            let middle = CGPoint(x: box.midX, y: box.midY)
            let alpha = min(1, dent.alpha * damage)

            let path = CGMutablePath()
            path.addLines(between: outline)
            path.closeSubpath()

            context.saveGState()
            context.addPath(path)
            context.clip()
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CompassRenderer.scratchDark.withAlphaComponent(0.46 * alpha).cgColor,
                    CompassRenderer.scratchDark.withAlphaComponent(0.05 * alpha).cgColor,
                    CompassRenderer.scratchBright.withAlphaComponent(0.03 * alpha).cgColor,
                    CompassRenderer.scratchBright.withAlphaComponent(0.40 * alpha).cgColor,
                ] as CFArray,
                locations: [0, 0.42, 0.58, 1]
            ) {
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: middle.x - reach * 0.7, y: middle.y - reach * 0.7),
                    end: CGPoint(x: middle.x + reach * 0.7, y: middle.y + reach * 0.7),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            context.restoreGState()

            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(CompassRenderer.scratchDark.withAlphaComponent(0.12 * alpha).cgColor)
            context.setLineWidth(0.7)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Chips: dark bare metal where the finish has gone, with a lit lip on the lower right.
    func drawChips(
        _ list: [CompassGrain.Chip],
        unit: CGFloat,
        map: (CGPoint) -> CGPoint,
        in context: CGContext
    ) {
        let alpha = min(1, 0.88 * damage)
        for chip in list {
            let outline = chip.shape.map { map(CGPoint(x: $0.x * unit, y: $0.y * unit)) }
            let path = CGMutablePath()
            path.addLines(between: outline)
            path.closeSubpath()

            // The lip first, offset toward the light's far side; the notch then covers all of it
            // but the sliver that shows below and to the right.
            context.saveGState()
            context.translateBy(x: 0.8, y: 0.8)
            context.addPath(path)
            context.setFillColor(CompassRenderer.scratchBright.withAlphaComponent(0.55 * alpha).cgColor)
            context.fillPath()
            context.restoreGState()

            context.saveGState()
            context.addPath(path)
            context.setFillColor(NSColor(calibratedRed: 0.17, green: 0.11, blue: 0.06, alpha: alpha).cgColor)
            context.fillPath()
            context.addPath(path)
            context.setStrokeColor(CompassRenderer.scratchDark.withAlphaComponent(0.6 * alpha).cgColor)
            context.setLineWidth(0.6)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// Rust pits: a faint stain round a hard little crater of orange-brown, with a dark floor and
    /// a speck of light on its lit edge.
    func drawPits(
        _ list: [CompassGrain.Blot],
        unit: CGFloat,
        map: (CGPoint) -> CGPoint,
        in context: CGContext
    ) {
        for pit in list {
            let centre = map(CGPoint(x: pit.x * unit, y: pit.y * unit))
            let radius = max(0.7, pit.radius * unit)
            let alpha = min(1, pit.alpha * damage)

            if let halo = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CompassTheme.rustBloom.withAlphaComponent(0.46 * alpha).cgColor,
                    CompassTheme.rust.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) {
                context.drawRadialGradient(
                    halo,
                    startCenter: centre, startRadius: 0,
                    endCenter: centre, endRadius: radius * 3.8,
                    options: []
                )
            }
            context.setFillColor(CompassRenderer.rustCore.withAlphaComponent(0.85 * alpha).cgColor)
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            let floor = radius * 0.55
            context.setFillColor(CompassRenderer.scratchDark.withAlphaComponent(0.45 * alpha).cgColor)
            context.fillEllipse(in: CGRect(x: centre.x - floor * 0.8, y: centre.y - floor * 0.8, width: floor * 2, height: floor * 2))
            let glint = radius * 0.28
            context.setFillColor(CompassRenderer.scratchBright.withAlphaComponent(0.40 * alpha).cgColor)
            context.fillEllipse(in: CGRect(x: centre.x + radius * 0.35 - glint, y: centre.y + radius * 0.35 - glint, width: glint * 2, height: glint * 2))
        }
    }

    /// Pores: tiny dark pits with no rust in them, the texture of old metal at a glance.
    func drawPores(
        _ list: [CompassGrain.Blot],
        unit: CGFloat,
        map: (CGPoint) -> CGPoint,
        in context: CGContext
    ) {
        for pore in list {
            let centre = map(CGPoint(x: pore.x * unit, y: pore.y * unit))
            let radius = max(0.5, pore.radius * unit)
            context.setFillColor(CompassRenderer.scratchDark.withAlphaComponent(min(1, pore.alpha * damage)).cgColor)
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private func bounds(of points: [CGPoint]) -> CGRect {
        var rect = CGRect(origin: points[0], size: .zero)
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect
    }

    // MARK: - The case

    /// Scuffs, scratches, dents, chips and rust on the bezel ring. Called inside the ring's clip.
    func drawCaseWear(in context: CGContext, state: State, metrics: CompassMetrics) {
        guard CompassTheme.isWorn else { return }
        let unit = metrics.cardRadius
        let z = metrics.cardDepth
        let map: (CGPoint) -> CGPoint = { state.camera.project(x: $0.x, y: $0.y, z: z) }

        // Grime packed into the seam against the card and down the reeding's roots.
        for (radius, width, alpha) in [
            (unit * 1.012, unit * 0.020, CGFloat(0.26)),
            (unit * 1.150, unit * 0.030, CGFloat(0.16)),
        ] {
            let ring = (0...120).map { step -> CGPoint in
                let angle = CGFloat(step) / 120 * 2 * .pi
                return map(CGPoint(x: radius * sin(angle), y: -radius * cos(angle)))
            }
            context.saveGState()
            context.setStrokeColor(CompassTheme.patina.withAlphaComponent(alpha * damage).cgColor)
            context.setLineWidth(width)
            context.addLines(between: ring)
            context.strokePath()
            context.restoreGState()
        }

        drawPores(grain.casePores, unit: unit, map: map, in: context)
        drawScratches(grain.caseScuffs, unit: unit, map: map, in: context)
        drawScratches(grain.caseScratches, unit: unit, map: map, in: context)
        drawDents(grain.caseDents, unit: unit, map: map, in: context)
        drawChips(grain.caseChips, unit: unit, map: map, in: context)
        drawPits(grain.casePits, unit: unit, map: map, in: context)
    }

    /// Scratches down the lug's stem and rust pitting round its ring.
    func drawLugWear(in context: CGContext, state: State, metrics: CompassMetrics, z: CGFloat) {
        guard CompassTheme.isWorn else { return }
        let unit = metrics.cardRadius
        let map: (CGPoint) -> CGPoint = { state.camera.project(x: $0.x, y: $0.y, z: z) }
        drawScratches(grain.lugScratches, unit: unit, map: map, in: context)
        drawPits(grain.lugPits, unit: unit, map: map, in: context)
    }

    /// Rust along the hinge pin.
    func drawHingeWear(in context: CGContext, state: State, metrics: CompassMetrics) {
        guard CompassTheme.isWorn else { return }
        let unit = metrics.cardRadius
        let y = state.lid.hingeY
        let z = state.lid.hingeZ
        let map: (CGPoint) -> CGPoint = { state.camera.project(x: $0.x, y: $0.y, z: z) }
        let pits = grain.hingePits.map {
            CompassGrain.Blot(x: $0.x, y: y / unit, radius: $0.radius, alpha: $0.alpha)
        }
        drawPits(pits, unit: unit, map: map, in: context)
    }

    // MARK: - The hub

    /// The centre boss: scratched where a thumb's nail finds it, and a couple of pits.
    func drawHubWear(in context: CGContext, state: State, metrics: CompassMetrics, boss: CGPath, z: CGFloat) {
        guard CompassTheme.isWorn else { return }
        let unit = metrics.hubRadius
        let map: (CGPoint) -> CGPoint = { state.camera.project(x: $0.x, y: $0.y, z: z) }
        context.saveGState()
        context.addPath(boss)
        context.clip()
        drawScratches(grain.hubScratches, unit: unit, map: map, in: context)
        drawPits(grain.hubPits, unit: unit, map: map, in: context)
        context.restoreGState()
    }

    // MARK: - The lid

    /// The outside of the lid. `map` takes lid-plane points, in the same units as the lid's
    /// cover radius, to the screen.
    func drawLidCoverWear(unit: CGFloat, map: (CGPoint) -> CGPoint, in context: CGContext) {
        guard CompassTheme.isWorn else { return }
        drawPores(grain.coverPores, unit: unit, map: map, in: context)
        drawScratches(grain.coverScuffs, unit: unit, map: map, in: context)
        drawScratches(grain.coverScratches, unit: unit, map: map, in: context)
        drawDents(grain.coverDents, unit: unit, map: map, in: context)
        drawChips(grain.coverChips, unit: unit, map: map, in: context)
        drawPits(grain.coverPits, unit: unit, map: map, in: context)
    }

    /// The engraved plate inside the lid.
    func drawLidFloorWear(unit: CGFloat, map: (CGPoint) -> CGPoint, in context: CGContext) {
        guard CompassTheme.isWorn else { return }
        drawScratches(grain.floorScuffs, unit: unit, map: map, in: context)
        drawScratches(grain.floorScratches, unit: unit, map: map, in: context)
        drawPits(grain.floorPits, unit: unit, map: map, in: context)
    }

    // MARK: - The card

    /// Folds, watermarks, rubbing at the edge and flyspecks. Drawn under the printing, inside the
    /// card's clip, and kept faint over the wedges so the names stay as legible as they were.
    func drawCardWear(in context: CGContext, state: State, metrics: CompassMetrics) {
        guard CompassTheme.isWorn else { return }
        let unit = metrics.cardRadius
        let z = metrics.cardDepth
        let map: (CGPoint) -> CGPoint = { state.camera.project(x: $0.x, y: $0.y, z: z) }

        // Watermarks: a soft tide of brown and a crisper line where it dried.
        let tide = NSColor(calibratedRed: 0.38, green: 0.26, blue: 0.12, alpha: 1)
        for line in grain.tideLines {
            let points = line.points.map { map(CGPoint(x: $0.x * unit, y: $0.y * unit)) }
            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addLines(between: points)
            context.setStrokeColor(tide.withAlphaComponent(0.26 * line.alpha * damage).cgColor)
            context.setLineWidth(unit * 0.045)
            context.strokePath()
            context.addLines(between: points)
            context.setStrokeColor(tide.withAlphaComponent(0.85 * line.alpha * damage).cgColor)
            context.setLineWidth(max(0.7, unit * 0.0045))
            context.strokePath()
            context.restoreGState()
        }

        drawCreases(grain.creases, unit: unit, map: map, in: context)

        // Rubbing at the edge, where the card has ridden against the brass: pale fibre bared by
        // the wear.
        drawScratches(grain.paperRubs, unit: unit, map: map,
                      bright: CompassRenderer.creaseBright, dark: CompassRenderer.creaseDark, in: context)

        let ink = NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.07, alpha: 1)
        for speck in grain.dirtSpecks {
            let centre = map(CGPoint(x: speck.x * unit, y: speck.y * unit))
            let radius = max(0.55, speck.radius * unit)
            context.setFillColor(ink.withAlphaComponent(min(1, speck.alpha * damage)).cgColor)
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    /// Folds in the card. Not a line with a shadow beside it: a fold is a soft ridge that wanders
    /// a little, breaks where the paper has flattened, and fades out at either end. The polyline
    /// is resampled and each short run is drawn at its own strength, so the fold comes and goes
    /// along its length the way a real one does.
    private func drawCreases(
        _ list: [CompassGrain.Scratch],
        unit: CGFloat,
        map: (CGPoint) -> CGPoint,
        in context: CGContext
    ) {
        let samples = 56
        context.saveGState()
        context.setLineCap(.round)
        for (index, crease) in list.enumerated() {
            let phaseA = CGFloat(index) * 2.7 + 0.6
            let phaseB = CGFloat(index) * 1.3 + 2.1
            let pts = crease.points
            guard pts.count >= 2 else { continue }

            // Resample along the polyline with a slow sideways wander.
            var line: [CGPoint] = []
            for step in 0...samples {
                let t = CGFloat(step) / CGFloat(samples)
                let f = t * CGFloat(pts.count - 1)
                let i = min(pts.count - 2, Int(f))
                let u = f - CGFloat(i)
                let a = pts[i], b = pts[i + 1]
                var x = a.x + (b.x - a.x) * u
                var y = a.y + (b.y - a.y) * u
                let dx = b.x - a.x, dy = b.y - a.y
                let length = max(0.001, hypot(dx, dy))
                let wander = 0.006 * (sin(t * 17 + phaseA) + 0.6 * sin(t * 41 + phaseB))
                x += -dy / length * wander
                y += dx / length * wander
                line.append(map(CGPoint(x: x * unit, y: y * unit)))
            }

            for step in 0..<samples {
                let t = (CGFloat(step) + 0.5) / CGFloat(samples)
                let envelope = pow(sin(.pi * t), 0.7)
                let breaks = min(1, max(0, 0.55 + 0.9 * sin(t * 23 + phaseA) * sin(t * 9 + phaseB)))
                let strength = crease.alpha * damage * envelope * breaks
                guard strength > 0.004 else { continue }
                let from = line[step], to = line[step + 1]

                context.move(to: from)
                context.addLine(to: to)
                context.setStrokeColor(CompassRenderer.creaseDark.withAlphaComponent(strength * 0.30).cgColor)
                context.setLineWidth(max(1.6, unit * 0.011))
                context.strokePath()

                context.move(to: from)
                context.addLine(to: to)
                context.setStrokeColor(CompassRenderer.creaseDark.withAlphaComponent(strength * 0.55).cgColor)
                context.setLineWidth(max(0.6, unit * 0.0026))
                context.strokePath()

                context.move(to: CGPoint(x: from.x + 1.1, y: from.y + 1.1))
                context.addLine(to: CGPoint(x: to.x + 1.1, y: to.y + 1.1))
                context.setStrokeColor(CompassRenderer.creaseBright.withAlphaComponent(strength * 0.70).cgColor)
                context.setLineWidth(max(0.6, unit * 0.0026))
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    // MARK: - The needle

    /// Lacquer worn off the needle's high points, showing the steel under it. Called inside the
    /// needle's clip; `at` places a point by distance along and across the needle.
    func drawNeedleWear(in context: CGContext, at: (CGFloat, CGFloat) -> CGPoint, tip: CGFloat, halfWidth: CGFloat) {
        guard CompassTheme.isWorn else { return }
        let steel = NSColor(calibratedRed: 0.62, green: 0.50, blue: 0.36, alpha: 1)
        let marks: [(along: CGFloat, across: CGFloat, size: CGFloat)] = [
            (0.97, 0.0, 0.55), (0.80, -0.35, 0.32), (0.52, 0.3, 0.38), (0.26, -0.2, 0.30), (-0.45, 0.1, 0.34),
        ]
        for mark in marks {
            let centre = at(mark.along * tip, mark.across * halfWidth)
            let radius = max(0.6, halfWidth * mark.size)
            context.setFillColor(steel.withAlphaComponent(min(1, 0.75 * damage)).cgColor)
            context.fillEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }
    }
}
