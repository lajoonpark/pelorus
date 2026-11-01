import AppKit
import Foundation
import RadialCore

/// Draws the compass.
///
/// Structure mirrors the object: a brimmed brass case with a card seated in it, the card's
/// printing, the slices, and the needle, every one of them built in flat card space and pushed
/// through `CompassCamera` on the way to the page. Nothing is drawn in screen coordinates
/// except the scrim and the hints, so the whole instrument leans as one solid thing.
///
/// The lid is a separate pass on its own hinge, because it is a separate object that happens
/// to share a pivot.
final class CompassRenderer {

    struct State {
        var metrics: CompassMetrics
        var camera: CompassCamera
        var lid: CompassLid
        var slices: [Bookmark]
        var hoveredSlice: Int?
        var hover: [CGFloat]
        var press: [CGFloat]
        var hubHover: CGFloat
        var needleAngle: CGFloat
        var showsNumbers: Bool
        /// The print and what lights it: labels, card printing, the slice wash and the sweep.
        var contentAlpha: Double
        /// The case and everything in it. Applied once, to a transparency layer around the case.
        var caseAlpha: Double
        /// The scrim behind the instrument. It sits outside that layer.
        var scrimAlpha: Double
        /// How far the box has risen, 0 to 1. The contact shadow is wider while the instrument is still
        /// coming down and tightens to its settled size as it lands.
        var presence: Double = 1
        /// How far the box is still set down, in the units this context is drawn in (the caller has
        /// already applied the set-down scale). Applied after the scrim, so the backdrop does not move.
        var dropOffset: CGFloat = 0
        var sweep: Double
        var pageAlpha: Double
    }

    let grain = CompassGrain()

    func draw(_ state: State, in context: CGContext, at centre: CGPoint) {
        let m = state.metrics

        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)

        // The scrim is the backdrop the instrument fades into, so it stays outside the layer.
        drawScrim(in: context, state: state)
        // The set-down drop comes after the scrim, so the backdrop stays where it is while the
        // instrument lands. Everything below moves with it, the layer's bounds included.
        context.translateBy(x: 0, y: state.dropOffset)

        // The case fades as one object. Everything from the contact shadow to the lid is composited
        // into a single layer at `caseAlpha`, so no translucent pass inside it can stack on another
        // mid-fade. At rest the layer is skipped, so the settled instrument pays nothing for it.
        let layered = state.caseAlpha < 0.999
        if layered {
            context.setAlpha(CGFloat(state.caseAlpha))
            context.beginTransparencyLayer(in: instrumentBounds(state), auxiliaryInfo: nil)
        }
        drawContactShadow(in: context, state: state)

        // From here down everything is in card space: origin at the hub, y down, projected.
        drawCaseWall(in: context, state: state, metrics: m)
        drawLug(in: context, state: state, metrics: m)
        drawBrass(in: context, state: state, metrics: m)
        drawCard(in: context, state: state, metrics: m)
        drawCardPrinting(in: context, state: state, metrics: m)
        drawSliceWash(in: context, state: state, metrics: m)
        drawNeedle(in: context, state: state, metrics: m)
        drawSliceLabels(in: context, state: state, metrics: m)
        drawHub(in: context, state: state, metrics: m)
        drawSweep(in: context, state: state, metrics: m)
        // Last, because it is genuinely the topmost thing here: shut, it lies just above the
        // card; swinging, its lower half passes in front of the card's near edge. Drawing it
        // before the card (as this used to) let the card paint over the lid, so the lid looked
        // clipped along a straight line for the whole first half of the opening swing.
        //
        // Its shadow goes down first, over everything printed on the case top, and the hinge goes on
        // after it, because the barrel is what the lid hangs from: the knuckles stand proud of the
        // case's back edge and the lid turns about them.
        drawLidShadow(in: context, state: state)
        drawLid(in: context, state: state)
        drawHinge(in: context, state: state, metrics: m)
        if layered {
            context.endTransparencyLayer()
        }

        context.restoreGState()
    }
}

// MARK: - Geometry helpers

extension CompassRenderer {

    /// A circle in card space, sampled densely enough that the projection shows no facets.
    func circle(_ radius: CGFloat, _ state: State, z: CGFloat = 0, steps: Int = 96) -> [CGPoint] {
        (0...steps).map { step in
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            return state.camera.project(x: radius * sin(angle), y: -radius * cos(angle), z: z)
        }
    }

    /// An annulus as two subpaths of opposite winding; fill it with `.evenOdd`.
    func annulus(outer: CGFloat, inner: CGFloat, _ state: State) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: circle(outer, state))
        path.closeSubpath()
        path.addLines(between: circle(inner, state).reversed())
        path.closeSubpath()
        return path
    }

    /// A wedge, from the dial's tested `RadialLayout` — the same geometry hit testing uses.
    func wedge(
        index: Int,
        inset: CGFloat,
        inner: CGFloat,
        outer: CGFloat,
        layout: RadialLayout,
        _ state: State
    ) -> CGPath {
        let drawn = layout.drawableRange(of: index, inset: inset)
        let path = CGMutablePath()
        let steps = max(3, Int((drawn.sweep / (.pi / 20)).rounded(.up)))
        let outerArc = (0...steps).map { step -> CGPoint in
            let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
            return state.camera.project(x: outer * sin(angle), y: -outer * cos(angle))
        }
        let innerArc = stride(from: steps, through: 0, by: -1).map { step -> CGPoint in
            let angle = drawn.start + drawn.sweep * CGFloat(step) / CGFloat(steps)
            return state.camera.project(x: inner * sin(angle), y: -inner * cos(angle))
        }
        path.addLines(between: outerArc + innerArc)
        path.closeSubpath()
        return path
    }

    /// Depth scale at a card-space point, bounded so type never gets silly at the far rim.
    func inkScale(at point: Point3D, _ state: State) -> CGFloat {
        min(1.06, max(0.94, state.camera.depthScale(at: point)))
    }

    func fill(_ points: [CGPoint], _ context: CGContext, _ colour: NSColor, rule: CGPathFillRule = .winding) {
        let path = CGMutablePath()
        path.addLines(between: points)
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(colour.cgColor)
        context.fillPath(using: rule)
    }

    func stroke(_ points: [CGPoint], _ context: CGContext, _ colour: NSColor, width: CGFloat) {
        let path = CGMutablePath()
        path.addLines(between: points)
        context.addPath(path)
        context.setStrokeColor(colour.cgColor)
        context.setLineWidth(width)
        context.setLineJoin(.round)
        context.setLineCap(.round)
        context.strokePath()
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ context: CGContext, _ colour: NSColor, width: CGFloat) {
        stroke([a, b], context, colour, width: width)
    }

    /// Type laid on the instrument: centred on `point`, squeezed vertically by the depth scale
    /// so it sits *on* the leaning surface rather than floating above it.
    func drawText(
        _ text: String,
        at point: CGPoint,
        scale: CGFloat,
        font: NSFont,
        colour: NSColor,
        in context: CGContext
    ) {
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: colour,
        ])
        let size = string.size()
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.scaleBy(x: 1, y: max(0.5, scale))
        string.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        context.restoreGState()
    }

    /// The page the instrument can paint on, in view space. The case layer is clipped to this, so
    /// it has to reach the lid at its highest under the current tilt, the contact shadow (drawn flat
    /// in view space, 1.5 case radii out, further while it is landing, and dropped 0.12 below the
    /// centre) and the lug.
    private func instrumentBounds(_ state: State) -> CGRect {
        let m = state.metrics
        let margin = m.cardRadius * 0.05
        // The pan has depth, so its highest point is the cover's edge, not the rim.
        let lidTop = (0...96).map { step -> CGFloat in
            let angle = CGFloat(step) / 96 * 2 * .pi
            let rim = state.lid.point(radius: state.lid.radius, angle: angle)
            let cover = state.lid.point(radius: m.lidCoverRadius, angle: angle, height: m.lidDepth)
            return min(state.camera.project(state.lid.swing(rim)).point.y,
                       state.camera.project(state.lid.swing(cover)).point.y)
        }.min() ?? 0
        let spread = contactShadowSpread(state)
        let half = m.caseRadius * 1.5 * spread
        let top = min(lidTop, -half) - margin
        let bottom = max(m.lugReach, m.caseRadius * (0.12 + 1.5 * 1.06 * spread)) + margin
        return CGRect(x: -half - margin, y: top, width: (half + margin) * 2, height: bottom - top)
    }
}

// MARK: - Scrim and shadows

extension CompassRenderer {

    private func scrimRadius(_ state: State) -> CGFloat {
        max(state.metrics.caseRadius * 2.9, 460)
    }

    private func drawScrim(in context: CGContext, state: State) {
        // Warm dark, and only under the instrument: dimming the whole screen would make this
        // a modal instead of an overlay you can still see past.
        let radius = scrimRadius(state)
        let alpha = state.scrimAlpha
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
            startCenter: .zero,
            startRadius: 0,
            endCenter: .zero,
            endRadius: radius,
            options: []
        )
    }

    /// How far the contact shadow reaches, relative to its settled size: 1.15 at presence 0 (the box
    /// not yet risen), easing to 1 as the instrument lands. Written as `1 + k * (1 - p)` so the rest
    /// value is exactly 1.
    private func contactShadowSpread(_ state: State) -> CGFloat {
        CGFloat(1 + 0.15 * (1 - state.presence))
    }

    private func drawContactShadow(in context: CGContext, state: State) {
        let m = state.metrics
        let radius = m.caseRadius * 1.5 * contactShadowSpread(state)
        let centre = CGPoint(x: 0, y: m.caseRadius * 0.12)
        let colours = [
            NSColor.black.withAlphaComponent(0.62).cgColor,
            NSColor.black.withAlphaComponent(0.30).cgColor,
            NSColor.black.withAlphaComponent(0).cgColor,
        ] as CFArray
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colours,
            locations: [0, 0.62, 1] as [CGFloat]
        ) else { return }
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.scaleBy(x: 0.95, y: 1.06)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: m.caseRadius * 0.5,
            endCenter: .zero,
            endRadius: radius,
            options: []
        )
        context.restoreGState()
    }

    /// The lid's shadow on the case top, in two parts.
    ///
    /// The cast part is the lid's silhouette thrown along the key light onto the case's crest. It
    /// is attached at the hinge, slides across the dial as the lid rises, and thins out as the
    /// lid stands clear, which is how a real shadow behaves and what makes the swing read as an
    /// object passing over the card. The contact part is a darkening under the hinge that stays
    /// once the lid is open: a leaning lid still shades the brass beneath it, and without it the
    /// lid reads as hovering. Both are clipped to the case, so they land on the object rather than
    /// in the air.
    private func drawLidShadow(in context: CGContext, state: State) {
        let angle = state.lid.angle
        guard angle > 0.04 else { return }
        let m = state.metrics
        let lid = state.lid
        let crest = lid.hingeZ

        context.saveGState()
        let silhouette = (0...96).map { step -> CGPoint in
            let a = CGFloat(step) / 96 * 2 * .pi
            return state.camera.project(
                x: m.caseRadius * sin(a), y: -m.caseRadius * cos(a), z: m.cardDepth
            )
        }
        let clip = CGMutablePath()
        clip.addLines(between: silhouette)
        clip.closeSubpath()
        context.addPath(clip)
        context.clip()

        // Cast shadow: the pan's rim and its top edge, thrown down the light.
        let drift = CGPoint(x: 0.34, y: 0.46)
        var thrown: [CGPoint] = []
        for height in [CGFloat(0), m.lidDepth] {
            for step in 0..<48 {
                let a = CGFloat(step) / 48 * 2 * .pi
                let world = lid.swing(lid.point(radius: m.lidRadius, angle: a, height: height))
                let up = max(0, world.z - crest)
                thrown.append(state.camera.project(
                    Point3D(x: world.x + drift.x * up, y: world.y + drift.y * up, z: crest)
                ).point)
            }
        }
        let hull = convexHull(thrown)
        if hull.count >= 3 {
            var centre = CGPoint.zero
            for point in hull {
                centre.x += point.x
                centre.y += point.y
            }
            centre.x /= CGFloat(hull.count)
            centre.y /= CGFloat(hull.count)
            // A high lid throws a faint, wide shadow: fade it as the lid lifts clear.
            let fade = max(0, 1 - max(0, angle - 0.35) / 1.15)
            // Soft edge by stacking slightly larger copies, which costs nothing and needs no blur.
            for pass in 0..<5 {
                let grow = 1 + CGFloat(pass) * 0.035
                let outline = CGMutablePath()
                outline.addLines(between: hull.map {
                    CGPoint(x: centre.x + ($0.x - centre.x) * grow, y: centre.y + ($0.y - centre.y) * grow)
                })
                outline.closeSubpath()
                context.addPath(outline)
                context.setFillColor(
                    NSColor(calibratedRed: 0.055, green: 0.035, blue: 0.016, alpha: 0.085 * fade).cgColor
                )
                context.fillPath()
            }
        }

        // Contact shadow under the hinge.
        let near = min(1, max(0, (CGFloat(sin(angle)) - 0.12) / 0.6))
        if near > 0 {
            let hinge = state.camera.project(Point3D(x: 0, y: lid.hingeY, z: 0)).point
            let top = hinge.y - m.caseRadius * 0.02
            let shade = NSColor(calibratedRed: 0.094, green: 0.063, blue: 0.031, alpha: 1)
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    shade.withAlphaComponent(0.34 * near).cgColor,
                    shade.withAlphaComponent(0.14 * near).cgColor,
                    shade.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 0.45, 1] as [CGFloat]
            ) {
                context.clip(to: CGRect(x: -m.caseRadius, y: top, width: m.caseRadius * 2, height: m.caseRadius * 0.36))
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: top),
                    end: CGPoint(x: 0, y: top + m.caseRadius * 0.30),
                    options: []
                )
            }
        }
        context.restoreGState()
    }

    /// The convex hull of a point set (Andrew's monotone chain): the outline of a shadow thrown by a
    /// solid, however many rims went into it.
    private func convexHull(_ input: [CGPoint]) -> [CGPoint] {
        let points = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard points.count > 2 else { return points }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [CGPoint] = []
        for point in points {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [CGPoint] = []
        for point in points.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}

// MARK: - The lid

// Light. The key comes from the upper left and toward the viewer. The fill is the pale card
// throwing warm light back up, which is why the inside of a leaning lid glows instead of going
// to mud. (View space: x right, y down, z toward the viewer.)
private func unitVector(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> Point3D {
    let length = sqrt(x * x + y * y + z * z)
    return Point3D(x: x / length, y: y / length, z: z / length)
}

private func dotProduct(_ a: Point3D, _ b: Point3D) -> CGFloat {
    a.x * b.x + a.y * b.y + a.z * b.z
}

private let lidKeyLight = unitVector(-0.42, -0.58, 0.70)
private let lidFillLight = unitVector(0.10, 0.78, 0.55)
private let lidHalfVector = unitVector(lidKeyLight.x, lidKeyLight.y, lidKeyLight.z + 1)

/// How much light a face with this view-space normal catches, 0 to 1.
private func lidIntensity(_ normal: Point3D, shine: CGFloat) -> CGFloat {
    let key = max(0, dotProduct(normal, lidKeyLight))
    let fill = max(0, dotProduct(normal, lidFillLight))
    let spec = pow(max(0, dotProduct(normal, lidHalfVector)), 26)
    return 0.20 + 0.56 * key + 0.36 * fill + shine * spec
}

/// Brass as a function of how much light it catches. Warm throughout: the highlights stay cream
/// and the shadows go olive rather than grey.
private func lidBrass(_ intensity: CGFloat, alpha: CGFloat = 1) -> NSColor {
    let stops: [(at: CGFloat, r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.00, 26, 19, 10), (0.22, 58, 44, 24), (0.42, 96, 74, 40), (0.60, 133, 101, 56),
        (0.78, 179, 145, 90), (0.92, 213, 192, 143), (1.00, 238, 223, 180),
    ]
    let t = min(1, max(0, intensity))
    var k = 1
    while k < stops.count - 1 && stops[k].at < t { k += 1 }
    let from = stops[k - 1]
    let to = stops[k]
    let u = (t - from.at) / (to.at - from.at)
    return NSColor(
        calibratedRed: (from.r + (to.r - from.r) * u) / 255,
        green: (from.g + (to.g - from.g) * u) / 255,
        blue: (from.b + (to.b - from.b) * u) / 255,
        alpha: alpha
    )
}

/// Cheap, stable pseudo-noise, so no two ridges of the milled wall are quite alike.
private func lidWobble(_ index: Int) -> CGFloat {
    let s = sin(Double(index) * 12.9898 + 4.1) * 43758.5453
    return CGFloat(s - s.rounded(.down))
}

/// A soft radial blot of colour: the building block of tarnish, polish and bloom.
private func lidGlow(
    _ context: CGContext,
    at point: CGPoint,
    radius: CGFloat,
    stops: [(at: CGFloat, colour: NSColor)]
) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: stops.map { $0.colour.cgColor } as CFArray,
        locations: stops.map { $0.at }
    ) else { return }
    context.drawRadialGradient(
        gradient,
        startCenter: point, startRadius: 0,
        endCenter: point, endRadius: radius,
        options: []
    )
}

/// One face of the lid's mesh, placed in view space.
private struct LidFace {
    enum Kind { case wall, shoulder, rim, inner, cover, floor }
    let kind: Kind
    let index: Int
    /// The outward normal, in view space.
    let normal: Point3D
    /// View-space depth of the face's centre. Larger is nearer.
    let depth: CGFloat
    let points: [CGPoint]
}

extension CompassRenderer {

    /// The lid as a mesh, in its own frame, swung about the hinge and placed for the camera.
    ///
    /// A shallow pan: a milled wall, a chamfered shoulder, a flat cover on the outside, and on the
    /// inside the engraved plate and the wall's lip. Faces that point away from the eye are
    /// dropped and the rest are sorted far to near, which is all the depth handling a shape this
    /// simple needs. It is also why the lid can show its cover on the way up, turn edge-on and
    /// come over to show the engraving.
    private func lidFaces(_ state: State) -> [LidFace] {
        let m = state.metrics
        let lid = state.lid
        let camera = state.camera
        let eye = camera.eyeDistance
        let segments = 144
        var faces: [LidFace] = []

        func add(_ kind: LidFace.Kind, _ index: Int, _ local: [Point3D], _ normal: Point3D) {
            var view: [Point3D] = []
            view.reserveCapacity(local.count)
            var sum = Point3D.zero
            for point in local {
                let v = camera.rotate(lid.swing(point))
                view.append(v)
                sum.x += v.x
                sum.y += v.y
                sum.z += v.z
            }
            let count = CGFloat(local.count)
            let centre = Point3D(x: sum.x / count, y: sum.y / count, z: sum.z / count)
            let facing = camera.rotate(lid.swingDirection(normal))
            // Visible only if it points at the eye. The eye is at `eye` on the view axis, so under
            // perspective this has to be measured from the face, not from the axis.
            let toEye = Point3D(x: -centre.x, y: -centre.y, z: eye - centre.z)
            guard dotProduct(facing, toEye) > 0 else { return }
            let points = view.map { v -> CGPoint in
                let scale = eye / (eye - v.z)
                return CGPoint(x: v.x * scale, y: v.y * scale)
            }
            faces.append(LidFace(kind: kind, index: index, normal: facing, depth: centre.z, points: points))
        }

        func at(_ radius: CGFloat, _ angle: CGFloat, _ height: CGFloat) -> Point3D {
            lid.point(radius: radius, angle: angle, height: height)
        }

        let outer = m.lidRadius
        for index in 0..<segments {
            let a0 = CGFloat(index) / CGFloat(segments) * 2 * .pi
            let a1 = CGFloat(index + 1) / CGFloat(segments) * 2 * .pi
            let mid = (a0 + a1) / 2
            let rx = sin(mid)
            let ry = -cos(mid)
            add(.wall, index, [
                at(outer, a0, 0), at(outer, a1, 0),
                at(outer, a1, m.lidShoulderHeight), at(outer, a0, m.lidShoulderHeight),
            ], Point3D(x: rx, y: ry, z: 0))
            add(.shoulder, index, [
                at(outer, a0, m.lidShoulderHeight), at(outer, a1, m.lidShoulderHeight),
                at(m.lidCoverRadius, a1, m.lidDepth), at(m.lidCoverRadius, a0, m.lidDepth),
            ], Point3D(x: rx * 0.707, y: ry * 0.707, z: 0.707))
            add(.rim, index, [
                at(outer, a0, 0), at(outer, a1, 0),
                at(m.lidFloorRadius, a1, 0), at(m.lidFloorRadius, a0, 0),
            ], Point3D(x: 0, y: 0, z: -1))
            add(.inner, index, [
                at(m.lidFloorRadius, a0, 0), at(m.lidFloorRadius, a1, 0),
                at(m.lidFloorRadius, a1, m.lidFloorHeight), at(m.lidFloorRadius, a0, m.lidFloorHeight),
            ], Point3D(x: -rx, y: -ry, z: 0))
        }
        let coverRing = (0..<segments).map {
            at(m.lidCoverRadius, CGFloat($0) / CGFloat(segments) * 2 * .pi, m.lidDepth)
        }
        add(.cover, 0, coverRing, Point3D(x: 0, y: 0, z: 1))
        let floorRing = (0..<segments).map {
            at(m.lidFloorRadius, CGFloat($0) / CGFloat(segments) * 2 * .pi, m.lidFloorHeight)
        }
        add(.floor, 0, floorRing, Point3D(x: 0, y: 0, z: -1))

        return faces.sorted { $0.depth < $1.depth }
    }

    private func drawLid(in context: CGContext, state: State) {
        let faces = lidFaces(state)
        for face in faces {
            switch face.kind {
            case .cover: paintLidCover(face, in: context, state: state)
            case .floor: paintLidFloor(face, in: context, state: state)
            default: paintLidBand(face, in: context)
            }
        }
        paintLidEdges(faces, in: context, state: state)
    }

    /// A strip of the wall, shoulder or rim: flat colour from the light it catches.
    private func paintLidBand(_ face: LidFace, in context: CGContext) {
        var intensity = lidIntensity(face.normal, shine: face.kind == .shoulder ? 0.30 : 0.10)
        switch face.kind {
        case .wall:
            // Milled edge: alternate ridges, with a little unevenness so it is not a printed pattern.
            intensity *= (face.index % 2 == 0 ? 1.02 : 0.95) * (0.985 + lidWobble(face.index) * 0.03)
        case .shoulder:
            intensity += 0.05
        case .inner:
            intensity *= 0.78
        case .rim:
            intensity *= 0.92
        default:
            break
        }
        let colour = lidBrass(intensity)
        fill(face.points, context, colour)
        // The same colour as a hairline: adjacent polygons otherwise leave seams of backdrop.
        stroke(face.points + [face.points[0]], context, colour, width: 0.7)
    }

    /// The line where the lid meets the case, and the lit crest of the shoulder.
    private func paintLidEdges(_ faces: [LidFace], in context: CGContext, state: State) {
        let radius = state.metrics.cardRadius
        for face in faces where face.kind == .wall {
            line(face.points[0], face.points[1], context,
                 NSColor(calibratedRed: 0.071, green: 0.047, blue: 0.020, alpha: 0.55),
                 width: max(0.9, radius * 0.006))
        }
        for face in faces where face.kind == .shoulder {
            let lit = min(1, max(0, lidIntensity(face.normal, shine: 0.5) - 0.35))
            line(face.points[3], face.points[2], context,
                 NSColor(calibratedRed: 1, green: 0.953, blue: 0.831, alpha: 0.10 + 0.55 * lit),
                 width: max(0.8, radius * 0.005))
            line(face.points[0], face.points[1], context,
                 NSColor(calibratedRed: 1, green: 0.925, blue: 0.769, alpha: 0.06 + 0.30 * lit),
                 width: max(0.8, radius * 0.005))
        }
    }

    private func bounds(of points: [CGPoint]) -> CGRect {
        var rect = CGRect(origin: points[0], size: .zero)
        for point in points { rect = rect.union(CGRect(origin: point, size: .zero)) }
        return rect
    }

    /// The outside of the lid: a spun cover with a rolled border, a thumb-polished patch where the
    /// hand takes it, and the tarnish a cover collects from a century in a pocket. Lighter than
    /// the inside, because this is the side that gets handled and wiped.
    private func paintLidCover(_ face: LidFace, in context: CGContext, state: State) {
        let m = state.metrics
        let lid = state.lid
        let radius = m.lidCoverRadius
        let height = m.lidDepth
        func lidPoint(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
            state.camera.project(lid.swing(lid.point(radius: r, angle: angle, height: height))).point
        }
        func lidFlat(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            state.camera.project(lid.swing(Point3D(x: x, y: y, z: lid.hingeZ + height))).point
        }
        let box = bounds(of: face.points)
        let centre = CGPoint(x: box.midX, y: box.midY)

        context.saveGState()
        let outline = CGMutablePath()
        outline.addLines(between: face.points)
        outline.closeSubpath()
        context.addPath(outline)
        context.setFillColor(lidBrass(lidIntensity(face.normal, shine: 0.24)).cgColor)
        context.fillPath()
        context.addPath(outline)
        context.clip()

        // Spun finish.
        for step in 0..<30 {
            let t = CGFloat(step) / 30
            let ring = (0...72).map { lidPoint(CGFloat($0) / 72 * 2 * .pi, radius * (0.10 + 0.88 * t)) }
            let strength = 0.045 * (1 - t * 0.5)
            let colour: NSColor = step % 2 == 0
                ? NSColor.black.withAlphaComponent(strength * 1.1)
                : NSColor(calibratedRed: 1, green: 0.965, blue: 0.878, alpha: strength)
            stroke(ring, context, colour, width: max(0.6, radius * 0.0036))
        }

        // The sheen follows the light across the plate as it turns.
        if let sheen = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 1, green: 0.965, blue: 0.863, alpha: 0.22).cgColor,
                NSColor(calibratedRed: 1, green: 0.965, blue: 0.863, alpha: 0.05).cgColor,
                NSColor(calibratedRed: 0.078, green: 0.055, blue: 0.027, alpha: 0.16).cgColor,
            ] as CFArray,
            locations: [0, 0.45, 1] as [CGFloat]
        ) {
            let lit = lidFlat(-radius * 0.38, -radius * 0.34)
            context.drawRadialGradient(
                sheen,
                startCenter: lit, startRadius: radius * 0.03,
                endCenter: lit, endRadius: radius * 1.05,
                options: [.drawsAfterEndLocation]
            )
        }

        // Rolled border, and a central roundel.
        for (k, colour, width) in [
            (CGFloat(0.900), NSColor.black.withAlphaComponent(0.30), CGFloat(1.1)),
            (CGFloat(0.885), NSColor.white.withAlphaComponent(0.16), CGFloat(0.8)),
            (CGFloat(0.300), NSColor.black.withAlphaComponent(0.20), CGFloat(0.9)),
            (CGFloat(0.288), NSColor.white.withAlphaComponent(0.12), CGFloat(0.8)),
        ] {
            let ring = (0...96).map { lidPoint(CGFloat($0) / 96 * 2 * .pi, radius * k) }
            stroke(ring, context, colour, width: width)
        }
        let cream = NSColor(calibratedRed: 1, green: 0.957, blue: 0.839, alpha: 1)
        lidGlow(context, at: lidFlat(0, 0), radius: radius * 0.10, stops: [
            (0, cream.withAlphaComponent(0.16)),
            (0.6, NSColor(calibratedRed: 0.47, green: 0.376, blue: 0.220, alpha: 0.10)),
            (1, NSColor(calibratedRed: 0.118, green: 0.078, blue: 0.031, alpha: 0.20)),
        ])

        // Thumb polish at the front edge.
        lidGlow(context, at: lidPoint(.pi, radius * 0.80), radius: radius * 0.36, stops: [
            (0, cream.withAlphaComponent(0.20)),
            (0.5, cream.withAlphaComponent(0.07)),
            (1, cream.withAlphaComponent(0)),
        ])

        // Tarnish, broad then sharp.
        for blotch in grain.lidUnevenness(radius: radius) {
            lidGlow(context, at: lidFlat(-blotch.x * radius, blotch.y * radius),
                    radius: blotch.radius * radius * 1.3, stops: [
                (0, CompassTheme.patina.withAlphaComponent(blotch.alpha * CompassTheme.wearGain * 0.38)),
                (1, CompassTheme.patina.withAlphaComponent(0)),
            ])
        }
        for blot in grain.lidPatina(radius: radius) {
            drawWear(blot, at: lidFlat(-blot.x * radius, -blot.y * radius), unit: radius * 1.15,
                     colour: CompassTheme.patina, alpha: CompassTheme.wearGain * 0.45, in: context)
        }

        drawLidCoverWear(unit: radius, map: { lidFlat(-$0.x, $0.y) }, in: context)

        // The cover rolls over into its shoulder.
        if let vignette = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.094, green: 0.067, blue: 0.035, alpha: 0).cgColor,
                NSColor(calibratedRed: 0.094, green: 0.067, blue: 0.035, alpha: 0.30).cgColor,
            ] as CFArray,
            locations: [0, 1] as [CGFloat]
        ) {
            context.drawRadialGradient(
                vignette,
                startCenter: centre, startRadius: radius * 0.6,
                endCenter: centre, endRadius: radius * 1.04,
                options: [.drawsAfterEndLocation]
            )
        }
        context.restoreGState()
    }

    /// The inside of the lid: the engraved plate, lit mostly by the card below it.
    private func paintLidFloor(_ face: LidFace, in context: CGContext, state: State) {
        let m = state.metrics
        let lid = state.lid
        let radius = m.lidFloorRadius
        let height = m.lidFloorHeight
        func lidPoint(_ angle: CGFloat, _ r: CGFloat) -> CGPoint {
            state.camera.project(lid.swing(lid.point(radius: r, angle: angle, height: height))).point
        }
        func lidFlat(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            state.camera.project(lid.swing(Point3D(x: x, y: y, z: lid.hingeZ + height))).point
        }
        let box = bounds(of: face.points)
        let centre = CGPoint(x: box.midX, y: box.midY)
        let extent = max(box.width, box.height)

        context.saveGState()
        let outline = CGMutablePath()
        outline.addLines(between: face.points)
        outline.closeSubpath()
        context.addPath(outline)
        context.setFillColor(lidBrass(lidIntensity(face.normal, shine: 0.10) * 0.94).cgColor)
        context.fillPath()
        context.addPath(outline)
        context.clip()

        // Depth: the plate is darker toward the far end of the dish, which is further from the
        // card's glow.
        if let depth = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 1, green: 0.941, blue: 0.784, alpha: 0.05).cgColor,
                NSColor(calibratedRed: 0.157, green: 0.110, blue: 0.047, alpha: 0).cgColor,
                NSColor(calibratedRed: 0.110, green: 0.075, blue: 0.031, alpha: 0.30).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 1] as [CGFloat]
        ) {
            context.drawLinearGradient(
                depth,
                start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        // Turned finish: bands rather than rings. A spun surface catches light on each ridge.
        for step in 0..<26 {
            let t = CGFloat(step) / 26
            let groove = radius * (0.16 + 0.82 * pow(t, 0.86))
            let ring = (0...72).map { lidPoint(CGFloat($0) / 72 * 2 * .pi, groove) }
            let fade = 1 - t * 0.55
            let colour: NSColor = step % 2 == 0
                ? NSColor(calibratedRed: 0.118, green: 0.086, blue: 0.043, alpha: 0.045 * fade)
                : NSColor(calibratedRed: 1, green: 0.969, blue: 0.878, alpha: 0.030 * fade)
            stroke(ring, context, colour, width: max(0.6, radius * 0.0038))
        }
        // Tool chatter: a few bright arcs, off-centre, as though the plate was spun by hand.
        for (from, to, alpha) in [(CGFloat(0.30), CGFloat(0.52), CGFloat(0.05)),
                                  (CGFloat(0.55), CGFloat(0.86), CGFloat(0.04)),
                                  (CGFloat(0.74), CGFloat(0.97), CGFloat(0.035))] {
            let arc = (0...40).map { lidPoint(from + (to - from) * CGFloat($0) / 40, radius * 0.90) }
            stroke(arc, context, NSColor(calibratedRed: 1, green: 0.973, blue: 0.894, alpha: alpha),
                   width: radius * 0.010)
        }

        // The card's glow, pooled low in the plate, and a soft shoulder into the wall.
        if let glow = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 1, green: 0.933, blue: 0.784, alpha: 0.15).cgColor,
                NSColor(calibratedRed: 1, green: 0.933, blue: 0.784, alpha: 0.04).cgColor,
                NSColor(calibratedRed: 0.078, green: 0.055, blue: 0.027, alpha: 0.10).cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1] as [CGFloat]
        ) {
            context.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: centre.x, y: box.maxY - box.height * 0.18), startRadius: radius * 0.05,
                endCenter: centre, endRadius: extent * 0.62,
                options: [.drawsAfterEndLocation]
            )
        }
        if let vignette = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.094, green: 0.067, blue: 0.035, alpha: 0).cgColor,
                NSColor(calibratedRed: 0.094, green: 0.067, blue: 0.035, alpha: 0.10).cgColor,
                NSColor(calibratedRed: 0.094, green: 0.067, blue: 0.035, alpha: 0.38).cgColor,
            ] as CFArray,
            locations: [0, 0.72, 1] as [CGFloat]
        ) {
            context.drawRadialGradient(
                vignette,
                startCenter: centre, startRadius: radius * 0.55,
                endCenter: centre, endRadius: radius * 1.02,
                options: [.drawsAfterEndLocation]
            )
        }

        // Engraved double border inside the wall: a dark cut with a lit lower lip.
        for (k, colour, width) in [
            (CGFloat(0.855), NSColor.black.withAlphaComponent(0.30), CGFloat(1.1)),
            (CGFloat(0.815), NSColor.black.withAlphaComponent(0.22), CGFloat(0.9)),
            (CGFloat(0.800), NSColor.white.withAlphaComponent(0.13), CGFloat(0.8)),
        ] {
            let ring = (0...96).map { lidPoint(CGFloat($0) / 96 * 2 * .pi, radius * k) }
            stroke(ring, context, colour, width: width)
        }

        drawLidRose(in: context, radius: radius, point: lidPoint, flat: lidFlat)

        // Maker's mark, struck into the plate below the rose.
        drawText(
            "SAFARI  RADIAL",
            at: lidFlat(0, radius * 0.705),
            scale: min(1.0, max(0.62, abs(cos(lid.angle)) + 0.55)),
            font: CompassTheme.serif(max(5.2, radius * 0.044), .semibold),
            colour: NSColor.black.withAlphaComponent(0.34),
            in: context
        )

        // Even tarnish across the plate, warm rather than grey.
        if let tarnish = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.376, green: 0.290, blue: 0.157, alpha: 0.02).cgColor,
                NSColor(calibratedRed: 0.345, green: 0.259, blue: 0.141, alpha: 0.10).cgColor,
                NSColor(calibratedRed: 0.298, green: 0.220, blue: 0.118, alpha: 0.20).cgColor,
                NSColor(calibratedRed: 0.227, green: 0.173, blue: 0.094, alpha: 0.30).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 0.86, 1] as [CGFloat]
        ) {
            context.drawRadialGradient(
                tarnish,
                startCenter: centre, startRadius: radius * 0.10,
                endCenter: centre, endRadius: radius * 1.02,
                options: [.drawsAfterEndLocation]
            )
        }

        // Broad mottling first, then the sharper patina over it.
        for blotch in grain.lidUnevenness(radius: radius) {
            lidGlow(context, at: lidFlat(blotch.x * radius, blotch.y * radius),
                    radius: blotch.radius * radius * 1.1, stops: [
                (0, CompassTheme.patina.withAlphaComponent(blotch.alpha * CompassTheme.wearGain)),
                (1, CompassTheme.patina.withAlphaComponent(0)),
            ])
        }
        for blot in grain.lidPatina(radius: radius) {
            drawWear(blot, at: lidFlat(blot.x * radius, blot.y * radius), unit: radius * 1.15,
                     colour: CompassTheme.patina, alpha: CompassTheme.wearGain, in: context)
        }

        // Rust creeps from the hinge seam toward the plate, and is spotted only where moisture
        // collects.
        let rustColour = NSColor(calibratedRed: 0.478, green: 0.243, blue: 0.118, alpha: 1)
        lidGlow(context, at: lidPoint(.pi, radius), radius: radius * 0.52, stops: [
            (0, rustColour.withAlphaComponent(0.30)),
            (0.30, rustColour.withAlphaComponent(0.13)),
            (0.62, rustColour.withAlphaComponent(0.04)),
            (1, rustColour.withAlphaComponent(0)),
        ])
        for spot in grain.rust(radius: radius) {
            drawWear(spot, at: lidFlat(spot.x * radius, spot.y * radius), unit: radius,
                     colour: CompassTheme.rust, alpha: CompassTheme.wearGain, in: context)
        }
        drawLidFloorWear(unit: radius, map: { lidFlat($0.x, $0.y) }, in: context)
        context.restoreGState()
    }
}

extension CompassRenderer {

    /// One soft blot of wear — tarnish or rust — as a radial gradient.
    private func drawWear(
        _ blot: CompassGrain.Blot,
        at point: CGPoint,
        unit: CGFloat,
        colour: NSColor,
        alpha: CGFloat,
        in context: CGContext
    ) {
        let spread = blot.radius * unit
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                colour.withAlphaComponent(blot.alpha * alpha).cgColor,
                colour.withAlphaComponent(blot.alpha * 0.5 * alpha).cgColor,
                colour.withAlphaComponent(0).cgColor,
            ] as CFArray,
            locations: [0, 0.52, 1] as [CGFloat]
        ) else { return }
        context.saveGState()
        context.translateBy(x: point.x, y: point.y)
        context.drawRadialGradient(
            gradient,
            startCenter: .zero, startRadius: 0,
            endCenter: .zero, endRadius: spread,
            options: []
        )
        context.restoreGState()
    }

    /// The engraved compass rose on the lid's plate.
    ///
    /// An open compass shows its lid, and a lid with nothing on it reads as a blank disc no
    /// matter how well it is shaded — this is the detail that makes it an instrument. Cut
    /// rather than inked: every line is a shadow with a thin light edge under it.
    private func drawLidRose(
        in context: CGContext,
        radius: CGFloat,
        point: (CGFloat, CGFloat) -> CGPoint,
        flat: (CGFloat, CGFloat) -> CGPoint
    ) {
        let outer = radius * 0.555
        let waist = radius * 0.125

        // Degree ticks between the rose and the bead. Struck, not painted: each is a dark
        // cut with a lit edge on its far side, which is what makes them survive the shallow
        // angle the lid is seen at.
        for index in 0..<72 {
            let angle = CGFloat(index) / 72 * 2 * .pi
            let isLong = index % 9 == 0
            let inner = radius * (isLong ? 0.845 : 0.872)
            let outerR = radius * 0.905
            let a = point(angle, inner)
            let b = point(angle, outerR)
            context.saveGState()
            let tickAlpha: CGFloat = isLong ? 0.40 : 0.24
            context.setStrokeColor(NSColor.black.withAlphaComponent(tickAlpha).cgColor)
            context.setLineWidth(isLong ? 1.0 : 0.7)
            context.move(to: a)
            context.addLine(to: b)
            context.strokePath()
            context.restoreGState()
        }

        // The plate the rose is cut into sits a hair proud of the field and a touch lighter.
        // Without it the points have nothing to be raised *above* and read as a drawing on a
        // disc rather than as struck metal.
        let plateCentre = flat(0, 0)
        if let plate = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.886, green: 0.808, blue: 0.651, alpha: 0.10).cgColor,
                NSColor(calibratedRed: 0.839, green: 0.753, blue: 0.588, alpha: 0.05).cgColor,
                NSColor(calibratedRed: 0.706, green: 0.612, blue: 0.439, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 0.7, 1] as [CGFloat]
        ) {
            context.saveGState()
            let path = CGMutablePath()
            path.addLines(between: (0...96).map { point(CGFloat($0) / 96 * 2 * .pi, outer * 1.06) })
            path.closeSubpath()
            context.addPath(path)
            context.clip()
            context.drawRadialGradient(
                plate, startCenter: plateCentre, startRadius: 0,
                endCenter: plateCentre, endRadius: outer * 1.06, options: []
            )
            context.restoreGState()
        }

        // The rose itself. Four long points and four short ones, alternating.
        for index in 0..<8 {
            let angle = CGFloat(index) / 8 * 2 * .pi
            let isLong = index % 2 == 0
            let tip = isLong ? outer : outer * 0.62
            let w = isLong ? waist * 0.68 : waist * 0.62
            let lit: CGFloat = isLong ? 0.19 : 0.13
            let dark: CGFloat = isLong ? 0.39 : 0.30
            let apex = point(angle, tip)
            let left = point(angle - .pi / 2, w)
            let right = point(angle + .pi / 2, w)
            let spine = point(angle, w * 0.35)

            let star = CGMutablePath()
            star.addLines(between: [left, apex, right])
            star.closeSubpath()
            context.addPath(star)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.46).cgColor)
            context.setLineWidth(max(0.8, tip * 0.012))
            context.strokePath()

            // Split down the spine: one half of each point catches the light and the other
            // holds shadow. Without the split the rose is a drawn star, not cut metal.
            let litFace = CGMutablePath()
            litFace.addLines(between: [spine, apex, left])
            litFace.closeSubpath()
            context.addPath(litFace)
            context.setFillColor(NSColor.white.withAlphaComponent(lit).cgColor)
            context.fillPath()

            let darkFace = CGMutablePath()
            darkFace.addLines(between: [spine, apex, right])
            darkFace.closeSubpath()
            context.addPath(darkFace)
            context.setFillColor(NSColor.black.withAlphaComponent(dark).cgColor)
            context.fillPath()
        }

        // The cut circle the points sit inside.
        for (r, colour, width) in [
            (outer * 1.045, NSColor.black.withAlphaComponent(0.34), CGFloat(max(1.0, radius * 0.012))),
            (outer * 1.020, NSColor.white.withAlphaComponent(0.14), CGFloat(max(0.8, radius * 0.008))),
        ] {
            let ring = (0...96).map { point(CGFloat($0) / 96 * 2 * .pi, r) }
            stroke(ring, context, colour, width: width)
        }

        // Central boss. Every point's spine converges at the middle, and without a struck
        // disc over the crossing the rose reads as a tangle of lines.
        let bossR = radius * 0.072
        let boss = (0...40).map { point(CGFloat($0) / 40 * 2 * .pi, bossR) }
        let centre = flat(0, 0)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.78, green: 0.67, blue: 0.45, alpha: 0.55).cgColor,
                NSColor(calibratedRed: 0.47, green: 0.38, blue: 0.22, alpha: 0.45).cgColor,
                NSColor(calibratedRed: 0.18, green: 0.13, blue: 0.07, alpha: 0.55).cgColor,
            ] as CFArray,
            locations: [0, 0.65, 1] as [CGFloat]
        ) {
            context.saveGState()
            let path = CGMutablePath()
            path.addLines(between: boss)
            path.closeSubpath()
            context.addPath(path)
            context.clip()
            context.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: centre.x - bossR * 0.3, y: centre.y + bossR * 0.3),
                startRadius: bossR * 0.1,
                endCenter: centre,
                endRadius: bossR,
                options: []
            )
            context.restoreGState()
        }
        stroke(boss, context, NSColor.black.withAlphaComponent(0.40), width: 0.9)
    }


}

// MARK: - The case

extension CompassRenderer {

    /// The side of the case: a strip from the top rim down by the wall depth. Drawn before the
    /// top face so it reads as being *under* it.
    private func drawCaseWall(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.caseRadius
        let steps = 72
        var band: [CGPoint] = []
        for step in 0...steps {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            band.append(state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: -metrics.wallDepth
            ))
        }
        for step in stride(from: steps, through: 0, by: -1) {
            let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
            band.append(state.camera.project(
                x: radius * sin(angle), y: -radius * cos(angle), z: -metrics.cardDepth
            ))
        }
        let path = CGMutablePath()
        path.addLines(between: band)
        path.closeSubpath()
        context.addPath(path)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.4, 1]
        ) {
            context.saveGState()
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: -radius, y: -radius),
                end: CGPoint(x: radius, y: radius),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context.restoreGState()
        }
    }

    private func drawBrass(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        let inner = metrics.cardRadius
        let ring = annulus(outer: outer, inner: inner, state)

        context.saveGState()
        context.addPath(ring)
        context.setFillColor(CompassTheme.brassLit.cgColor)
        context.fillPath(using: .evenOdd)

        // Cross-case light from the upper left, as in the reference.
        context.addPath(ring)
        context.clip(using: .evenOdd)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.18, 0.46, 0.70, 0.88, 1]
        ) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: -outer * 0.72, y: -outer * 0.78),
                end: CGPoint(x: outer * 0.72, y: outer * 0.78),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }

        grain.fill(in: context, scale: state.metrics.cardRadius)

        drawPatina(in: context, state: state, metrics: metrics)
        drawBuffMarks(in: context, state: state, metrics: metrics)
        drawTarnishBand(in: context, state: state, metrics: metrics)
        drawReeding(in: context, state: state, metrics: metrics)
        drawCaseWear(in: context, state: state, metrics: metrics)

        context.restoreGState()

        // Rim lines: the outer edge, the card's seat, and a lit inner lip.
        context.saveGState()
        for (radius, colour, width) in [
            (outer, NSColor.black.withAlphaComponent(0.60), CGFloat(1.2)),
            (inner, NSColor.black.withAlphaComponent(0.50), CGFloat(1.3)),
            (inner * 0.986, NSColor.white.withAlphaComponent(0.13), CGFloat(1)),
        ] {
            let path = CGMutablePath()
            path.addLines(between: circle(radius, state))
            path.closeSubpath()
            context.addPath(path)
            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(width)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// Age on the metal: soft olive blotches along the outer third, never rust spots.
    private func drawPatina(in context: CGContext, state: State, metrics: CompassMetrics) {
        for blot in grain.patina(radius: metrics.cardRadius) {
            let point = state.camera.project(Point3D(
                x: blot.x * metrics.cardRadius,
                y: blot.y * metrics.cardRadius,
                z: metrics.cardDepth
            ))
            let radius = blot.radius * metrics.cardRadius * point.depthScale
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    CompassTheme.patina.withAlphaComponent(blot.alpha * CompassTheme.wearGain).cgColor,
                    CompassTheme.patina.withAlphaComponent(blot.alpha * 0.55 * CompassTheme.wearGain).cgColor,
                    CompassTheme.patina.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 0.6, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.point.x, y: point.point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: radius,
                options: []
            )
            context.restoreGState()
        }
    }

    /// Burnished arcs where a thumb keeps polishing the metal bright.
    private func drawBuffMarks(in context: CGContext, state: State, metrics: CompassMetrics) {
        for buff in grain.buffs(radius: metrics.cardRadius) {
            let from = state.camera.project(Point3D(x: buff.radius * sin(buff.angle), y: -buff.radius * cos(buff.angle), z: metrics.cardDepth))
            let to = state.camera.project(Point3D(x: buff.radius * sin(buff.angle + buff.length), y: -buff.radius * cos(buff.angle + buff.length), z: metrics.cardDepth))
            context.saveGState()
            context.setStrokeColor(CompassTheme.brassHi.withAlphaComponent(buff.alpha * CompassTheme.wearGain).cgColor)
            context.setLineWidth(max(1.4, metrics.cardRadius * 0.012))
            context.setLineCap(.round)
            context.move(to: from.point)
            context.addLine(to: to.point)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// The dark film that collects just inside the reeding, where a thumb never reaches.
    private func drawTarnishBand(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.patina.withAlphaComponent(0).cgColor,
                CompassTheme.tarnishWarm.withAlphaComponent(0.10).cgColor,
                CompassTheme.patina.withAlphaComponent(0.22).cgColor,
                CompassTheme.patina.withAlphaComponent(0.44).cgColor,
            ] as CFArray,
            locations: [0, 0.55, 0.82, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: outer * 0.86,
            endCenter: .zero,
            endRadius: outer,
            options: []
        )
        context.restoreGState()

        // Hands. The two places a pocket compass is held are the case's lower edge and the
        // thumb-grip beside the hinge, so those two arcs are worn brighter than the rest of a
        // tarnished rim. Drawn as broad, very soft crescents under the tarnish, because polish
        // is a thinning of the film, not a paint.
        for (from, to) in [(CGFloat(0.52), CGFloat(0.86)), (CGFloat(1.42), CGFloat(1.62))] {
            var arc: [CGPoint] = []
            for step in 0...40 {
                let t = from + (to - from) * CGFloat(step) / 40
                arc.append(state.camera.project(
                    x: outer * 0.975 * sin(t * .pi), y: -outer * 0.975 * cos(t * .pi), z: 0
                ))
            }
            context.saveGState()
            context.setLineCap(.round)
            context.setStrokeColor(CompassTheme.brassHi.withAlphaComponent(0.16).cgColor)
            context.setLineWidth(outer * 0.075)
            context.addLines(between: arc)
            context.strokePath()
            context.restoreGState()
        }
    }

    /// The knurled edge: alternating lit and shadowed ridges, drawn from the card's plane so
    /// they lean with everything else.
    private func drawReeding(in context: CGContext, state: State, metrics: CompassMetrics) {
        let outer = metrics.caseRadius
        let count = 190
        context.saveGState()
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * 2 * .pi
            let from = state.camera.project(Point3D(x: outer * 0.952 * sin(angle), y: -outer * 0.952 * cos(angle), z: metrics.cardDepth))
            let to = state.camera.project(Point3D(x: outer * sin(angle), y: -outer * cos(angle), z: metrics.cardDepth))
            let lit = index % 2 == 0
            context.setStrokeColor(
                (lit ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.22))
                    .withAlphaComponent(lit ? 0.15 : 0.22)
                    .cgColor
            )
            context.setLineWidth(1)
            context.move(to: from.point)
            context.addLine(to: to.point)
            context.strokePath()
        }
        context.restoreGState()
    }
}

// MARK: - Lug and hinge

extension CompassRenderer {

    private func drawLug(in context: CGContext, state: State, metrics: CompassMetrics) {
        let z = -metrics.wallDepth * 0.45

        // Stem.
        let width = metrics.lugWidth
        let stem = [
            state.camera.project(x: -width, y: metrics.lugStemTop, z: z),
            state.camera.project(x: width, y: metrics.lugStemTop, z: z),
            state.camera.project(x: width * 0.78, y: metrics.lugStemBottom, z: z),
            state.camera.project(x: -width * 0.78, y: metrics.lugStemBottom, z: z),
        ]
        let stemPath = CGMutablePath()
        stemPath.addLines(between: stem)
        stemPath.closeSubpath()
        context.addPath(stemPath)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.brassDark.cgColor,
                CompassTheme.brassLit.cgColor,
                CompassTheme.brassMid.cgColor,
                CompassTheme.brassDeep.cgColor,
            ] as CFArray,
            locations: [0, 0.28, 0.60, 1]
        ) {
            context.saveGState()
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: -width, y: 0),
                end: CGPoint(x: width, y: 0),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            context.restoreGState()
        }
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.strokePath()

        // Bow: a circle in card space, so it projects as the same ellipse as the case.
        let bowCentre = metrics.lugBowCenter
        let bowRadius = metrics.lugBowRadius
        let bow = (0...64).map { step -> CGPoint in
            let angle = CGFloat(step) / CGFloat(64) * 2 * .pi
            return state.camera.project(
                x: bowRadius * sin(angle),
                y: bowCentre - bowRadius * cos(angle),
                z: z
            )
        }
        context.saveGState()
        let bowPath = CGMutablePath()
        bowPath.addLines(between: bow)
        bowPath.closeSubpath()
        context.addPath(bowPath)
        context.setStrokeColor(CompassTheme.brassMid.cgColor)
        context.setLineWidth(metrics.cardRadius * 0.020)
        context.setLineCap(.round)
        context.strokePath()

        // A highlight along the upper left of the band, so the ring reads round.
        let highlight = (0...24).map { step -> CGPoint in
            let angle = -CGFloat.pi * 0.75 + (CGFloat.pi * 0.9) * CGFloat(step) / 24
            return state.camera.project(
                x: (bowRadius + metrics.cardRadius * 0.004) * sin(angle),
                y: bowCentre - (bowRadius + metrics.cardRadius * 0.004) * cos(angle),
                z: z
            )
        }
        stroke(highlight, context, NSColor.white.withAlphaComponent(0.40), width: 1.1)
        drawLugWear(in: context, state: state, metrics: metrics, z: z)
        context.restoreGState()
    }

    /// The hinge barrel across the back of the case: five knuckles on one pin, alternately the
    /// case's and the lid's. It is what makes the lid read as hung on the box rather than hovering
    /// over it, and it is drawn after the lid because the lid is what turns about it.
    private func drawHinge(in context: CGContext, state: State, metrics: CompassMetrics) {
        let lid = state.lid
        let y = lid.hingeY
        let z = lid.hingeZ
        let radius = metrics.cardRadius * 0.040
        let span = metrics.cardRadius * 0.34
        let gap = metrics.cardRadius * 0.004
        let edges = [-span, -span * 0.6, -span * 0.2, span * 0.2, span * 0.6, span]

        for knuckle in 0..<5 {
            let x0 = edges[knuckle] + gap
            let x1 = edges[knuckle + 1] - gap
            let from = state.camera.project(Point3D(x: x0, y: y, z: z))
            let to = state.camera.project(Point3D(x: x1, y: y, z: z))
            let half = radius * (from.depthScale + to.depthScale) / 2
            let ownedByLid = knuckle % 2 == 1
            let centreY = (from.point.y + to.point.y) / 2
            let rect = CGRect(x: from.point.x, y: centreY - half, width: to.point.x - from.point.x, height: half * 2)

            // CoreGraphics requires the corner radius to fit the rect, which a tilted, foreshortened
            // knuckle can briefly violate.
            let capsuleRadius = max(0, min(half, rect.width / 2, rect.height / 2))
            // A capsule along the pin, shaded like a cylinder lit from above.
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: capsuleRadius, cornerHeight: capsuleRadius, transform: nil))
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    (ownedByLid ? NSColor(calibratedRed: 0.886, green: 0.804, blue: 0.596, alpha: 1)
                                : CompassTheme.brassHi).cgColor,
                    CompassTheme.brassLit.cgColor,
                    CompassTheme.brassMid.cgColor,
                    CompassTheme.brassDeep.cgColor,
                ] as CFArray,
                locations: [0, 0.35, 0.7, 1] as [CGFloat]
            ) {
                context.clip()
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: rect.midX, y: rect.minY),
                    end: CGPoint(x: rect.midX, y: rect.maxY),
                    options: []
                )
            }
            context.restoreGState()
            context.saveGState()
            context.addPath(CGPath(roundedRect: rect, cornerWidth: capsuleRadius, cornerHeight: capsuleRadius, transform: nil))
            context.setStrokeColor(NSColor(calibratedRed: 0.094, green: 0.063, blue: 0.031, alpha: 0.55).cgColor)
            context.setLineWidth(0.9)
            context.strokePath()
            context.restoreGState()

            // Rust on the knuckle itself, where water sits and the lacquer gives up first. Small, and
            // a stain on the metal rather than a wash over it: at larger sizes the blooms merged
            // into one orange band across the case, which read as a painted stripe.
            let mid = state.camera.project(Point3D(x: (x0 + x1) / 2, y: y, z: z))
            context.saveGState()
            context.translateBy(x: mid.point.x, y: mid.point.y)
            context.scaleBy(x: 1.5, y: 0.7)
            lidGlow(context, at: .zero, radius: metrics.cardRadius * 0.07 * mid.depthScale, stops: [
                (0, CompassTheme.rustBloom.withAlphaComponent(0.34)),
                (0.5, CompassTheme.rust.withAlphaComponent(0.14)),
                (1, CompassTheme.rust.withAlphaComponent(0)),
            ])
            context.restoreGState()
        }

        drawHingeWear(in: context, state: state, metrics: metrics)

        // The pin's end caps.
        for sign in [CGFloat(-1), CGFloat(1)] {
            let end = state.camera.project(Point3D(x: sign * (span + gap), y: y, z: z))
            let r = radius * end.depthScale * 0.62
            context.saveGState()
            context.addEllipse(in: CGRect(x: end.point.x - r, y: end.point.y - r, width: r * 2, height: r * 2))
            context.setFillColor(CompassTheme.brassDark.cgColor)
            context.fillPath()
            context.addEllipse(in: CGRect(x: end.point.x - r, y: end.point.y - r, width: r * 2, height: r * 2))
            context.setStrokeColor(NSColor(calibratedRed: 0.094, green: 0.063, blue: 0.031, alpha: 0.6).cgColor)
            context.setLineWidth(0.8)
            context.strokePath()
            context.restoreGState()
        }
    }
}

// MARK: - The card

extension CompassRenderer {

    private func drawCard(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        let circlePath = CGMutablePath()
        circlePath.addLines(between: circle(radius, state))
        circlePath.closeSubpath()

        context.saveGState()
        context.addPath(circlePath)
        context.clip()

        // Paper: lit upper left, aged at the rim, browned where it meets brass.
        let light = CGPoint(x: -radius * 0.30, y: -radius * 0.36)
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                CompassTheme.paperLit.cgColor,
                CompassTheme.paper.cgColor,
                CompassTheme.paperDeep.cgColor,
                CompassTheme.paperEdge.cgColor,
            ] as CFArray,
            locations: [0, 0.34, 0.72, 1]
        ) {
            context.drawRadialGradient(
                gradient,
                startCenter: light,
                startRadius: radius * 0.06,
                endCenter: .zero,
                endRadius: radius * 1.04,
                options: [.drawsBeforeStartLocation]
            )
        }

        grain.fill(in: context, scale: radius)
        drawRubRing(in: context, metrics: metrics)
        drawAgeing(in: context, state: state, metrics: metrics)
        drawCardWear(in: context, state: state, metrics: metrics)
        drawSeatGrime(in: context, state: state, metrics: metrics)
        context.restoreGState()

        // A hairline where paper meets brass, so the seat reads as a gap not a blend.
        context.saveGState()
        context.addPath(circlePath)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.38).cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    /// A century of the lid closing on the same spot has polished the paper just outside the
    /// hub. It is the wear mark that most says "used" rather than "reproduced".
    private func drawRubRing(in context: CGContext, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedWhite: 1, alpha: 0.10).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0.05).cgColor,
                NSColor(calibratedWhite: 1, alpha: 0).cgColor,
            ] as CFArray,
            locations: [0, 0.5, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: radius * 0.22,
            endCenter: .zero,
            endRadius: radius * 0.46,
            options: []
        )
        context.restoreGState()
    }

    /// Foxing and uneven ageing, so no two square inches of the card are the same tone.
    private func drawAgeing(in context: CGContext, state: State, metrics: CompassMetrics) {
        // Broad mottling first, under the sharp foxing: at a glance this is most of what makes
        // the card read as old paper rather than as a printed gradient.
        for blotch in grain.cardUnevenness(radius: metrics.cardRadius) {
            let point = state.camera.project(Point3D(
                x: blotch.x * metrics.cardRadius,
                y: blotch.y * metrics.cardRadius,
                z: metrics.cardDepth
            ))
            let radius = blotch.radius * metrics.cardRadius * point.depthScale
            let tone = NSColor(calibratedRed: 0.439, green: 0.314, blue: 0.165, alpha: 1)
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    tone.withAlphaComponent(blotch.alpha * CompassTheme.wearGain).cgColor,
                    tone.withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.point.x, y: point.point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero, startRadius: 0,
                endCenter: .zero, endRadius: radius,
                options: []
            )
            context.restoreGState()
        }

        for spot in grain.ageSpots(radius: metrics.cardRadius) {
            let point = state.camera.project(Point3D(
                x: spot.x * metrics.cardRadius,
                y: spot.y * metrics.cardRadius,
                z: metrics.cardDepth
            ))
            let radius = spot.radius * metrics.cardRadius * point.depthScale
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    NSColor(calibratedRed: 0.478, green: 0.369, blue: 0.212, alpha: 1)
                        .withAlphaComponent(spot.alpha * CompassTheme.wearGain).cgColor,
                    NSColor(calibratedRed: 0.478, green: 0.369, blue: 0.212, alpha: 1).withAlphaComponent(0).cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { continue }
            context.saveGState()
            context.translateBy(x: point.point.x, y: point.point.y)
            context.drawRadialGradient(
                gradient,
                startCenter: .zero,
                startRadius: 0,
                endCenter: .zero,
                endRadius: radius,
                options: []
            )
            context.restoreGState()
        }
    }

    /// Grime where the card has sat against the brass for decades: darkest at the very edge,
    /// heaviest at the bottom where dust settles.
    private func drawSeatGrime(in context: CGContext, state: State, metrics: CompassMetrics) {
        let radius = metrics.cardRadius
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor(calibratedRed: 0.259, green: 0.196, blue: 0.110, alpha: 1).withAlphaComponent(0).cgColor,
                NSColor(calibratedRed: 0.259, green: 0.196, blue: 0.110, alpha: 1).withAlphaComponent(0.10).cgColor,
                NSColor(calibratedRed: 0.208, green: 0.149, blue: 0.078, alpha: 1).withAlphaComponent(0.34).cgColor,
            ] as CFArray,
            locations: [0, 0.72, 1]
        ) else { return }
        context.saveGState()
        context.drawRadialGradient(
            gradient,
            startCenter: .zero,
            startRadius: radius * 0.80,
            endCenter: CGPoint(x: 0, y: radius * 0.05),
            endRadius: radius * 1.02,
            options: []
        )
        context.restoreGState()
    }
}
