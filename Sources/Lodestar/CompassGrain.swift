import AppKit
import Foundation

/// The instrument's wear, as deterministic data.
///
/// Every blotch, scuff and age spot on the compass is generated from a fixed seed, so the same
/// object appears every time the menu opens. That matters more than it sounds: random wear
/// re-rolled per frame would crawl, and re-rolled per open would make the compass a different
/// object each time — which reads as a rendering artefact rather than as a worn tool.
///
/// Values are in card-radius units, so the wear scales with the instrument and a 140pt dial
/// wears exactly like a 320pt one.
final class CompassGrain {

    struct Blot { let x: CGFloat; let y: CGFloat; let radius: CGFloat; let alpha: CGFloat }
    struct Buff { let angle: CGFloat; let radius: CGFloat; let length: CGFloat; let alpha: CGFloat }

    private let patinaBlots: [Blot]
    /// Broad, very soft patches across the whole card, so no part of it is one flat tone.
    private let cardBlotches: [Blot]
    /// The same, for the inside of the lid. It is a plate of the same brass handled by the same
    /// decades, so it has to carry the same unevenness; without this the open lid read as a new
    /// plate held above an old box.
    private let lidBlotches: [Blot]
    private let buffs: [Buff]
    private let spots: [Blot]
    private let lidBlots: [Blot]
    private let rustSpots: [Blot]
    private let tile: NSImage

    // Hard-edged damage. The layers above are all soft gradients, which read as lighting rather
    // than as wear; these are the marks a pocket and a thumb actually leave. Coordinates are in
    // card-radius units (lid units for the lid's layers), like everything else here.

    /// A scratch or a crease: a short polyline.
    struct Scratch {
        let points: [CGPoint]
        let alpha: CGFloat
        /// A multiple of the base hairline width.
        let width: CGFloat
        /// Bare bright metal (or a pale fibre) in the groove, with a shadow beside it, as opposed to
        /// a deep scratch packed with dirt.
        let bright: Bool
    }

    /// A notch where plating or lacquer has come away, as a closed outline.
    struct Chip { let shape: [CGPoint] }

    let caseScratches: [Scratch]
    let caseScuffs: [Scratch]
    let caseDents: [Blot]
    let caseChips: [Chip]
    let casePits: [Blot]
    /// Fine pitting in the metal: the pores a century of tarnish opens up.
    let casePores: [Blot]
    let coverPores: [Blot]
    let coverScratches: [Scratch]
    let coverScuffs: [Scratch]
    let coverDents: [Blot]
    let coverChips: [Chip]
    let coverPits: [Blot]
    let floorScratches: [Scratch]
    let floorScuffs: [Scratch]
    let floorPits: [Blot]
    let hubScratches: [Scratch]
    let hubPits: [Blot]
    let lugScratches: [Scratch]
    let lugPits: [Blot]
    let hingePits: [Blot]
    let creases: [Scratch]
    let tideLines: [Scratch]
    let paperRubs: [Scratch]
    let dirtSpecks: [Blot]

    // Per-layer weights, baked into the alphas above rather than applied where they are drawn.
    // A blot's weight is a property of what it represents — brass tarnish sits heavier on metal
    // than foxing does on paper — so it belongs with the data. That leaves exactly one number to
    // tune the whole instrument, `CompassTheme.wearGain`, and keeps the web harness in step: it
    // generates the same numbers and applies the same single gain.
    private static let brassPatinaWeight: CGFloat = 1.7
    private static let buffWeight: CGFloat = 1.4
    private static let foxingWeight: CGFloat = 1.5
    private static let lidPatinaWeight: CGFloat = 2.6
    private static let cardBlotchWeight: CGFloat = 1.9
    private static let lidBlotchWeight: CGFloat = 2.4

    /// Enough of a tile that the repeat does not read as a grid, small enough to build once.
    private static let tileSize = 96

    init(seed: UInt64 = 20_261_029) {
        var random = SplitMix64(seed: seed)

        // Patina: along the outer third, where a hand brushes and sweat sits.
        patinaBlots = (0..<30).map { _ in
            let angle = random.unit() * 2 * .pi
            let radius = 0.94 + random.unit() * 0.20
            return Blot(
                x: radius * sin(angle),
                y: -radius * cos(angle),
                radius: 0.10 + random.unit() * 0.20,
                alpha: (0.05 + random.unit() * 0.10) * CompassGrain.brassPatinaWeight
            )
        }

        // Broad unevenness across the card. These overlap into a single mottled field rather
        // than reading as separate marks — that is what separates aged paper from a printed
        // gradient, and it is the layer that does most of the work at a glance.
        cardBlotches = (0..<9).map { _ in
            Blot(
                x: (random.unit() - 0.5) * 1.4,
                y: (random.unit() - 0.5) * 1.4,
                radius: 0.16 + random.unit() * 0.30,
                alpha: (0.030 + random.unit() * 0.045) * CompassGrain.cardBlotchWeight
            )
        }

        // Burnished arcs: the high points a thumb keeps wiping clean.
        buffs = (0..<11).map { _ in
            Buff(
                angle: random.unit() * 2 * .pi,
                radius: 1.02 + random.unit() * 0.10,
                length: 0.25 + random.unit() * 0.55,
                alpha: (0.06 + random.unit() * 0.10) * CompassGrain.buffWeight
            )
        }

        // Foxing on the paper: small, brown, faint.
        spots = (0..<26).map { _ in
            Blot(
                x: (random.unit() - 0.5) * 1.5,
                y: (random.unit() - 0.5) * 1.5,
                radius: 0.010 + random.unit() * 0.045,
                alpha: (0.05 + random.unit() * 0.10) * CompassGrain.foxingWeight
            )
        }

        // Tarnish inside the lid. Weighted to the outer third, where a thumb never reaches
        // past the bead, so the plate's centre stays recognisably brighter than its edge.
        lidBlots = (0..<17).map { _ in
            let angle = random.unit() * 2 * .pi
            let radius = 0.42 + random.unit() * 0.52
            return Blot(
                x: radius * sin(angle),
                y: -radius * cos(angle),
                radius: 0.10 + random.unit() * 0.20,
                alpha: (0.04 + random.unit() * 0.08) * CompassGrain.lidPatinaWeight
            )
        }

        // Broad unevenness across the lid's face, as on the card. The open lid is a plate of the
        // same brass and has been handled by the same decades; without this it read as a new
        // plate held above an old box.
        lidBlotches = (0..<7).map { _ in
            let angle = random.unit() * 2 * .pi
            let radius = random.unit() * 0.55
            return Blot(
                x: radius * sin(angle),
                y: -radius * cos(angle),
                radius: 0.18 + random.unit() * 0.26,
                alpha: (0.035 + random.unit() * 0.040) * CompassGrain.lidBlotchWeight
            )
        }

        // Rust: a few spots only, sitting along the hinge-side seam where moisture collects.
        // Deliberately scarce and never on the face's middle — the brief was old and worn, not
        // damaged, and rust in the middle of a lid reads as damage.
        rustSpots = (0..<5).map { _ in
            let x = (random.unit() - 0.5) * 1.2
            return Blot(
                x: x,
                y: 0.62 + random.unit() * 0.30,
                radius: 0.018 + random.unit() * 0.035,
                alpha: 0.12 + random.unit() * 0.10
            )
        }

        tile = CompassGrain.makeTile(size: CompassGrain.tileSize, seed: &random)

        // Everything below is drawn from the generator after the layers above, so adding or
        // retuning damage never moves a blot that was already there.

        func ring(_ inner: CGFloat, _ outer: CGFloat) -> (inout SplitMix64) -> CGPoint {
            { r in
                let angle = r.unit() * 2 * .pi
                let radius = inner + r.unit() * (outer - inner)
                return CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
            }
        }
        func disc(_ extent: CGFloat) -> (inout SplitMix64) -> CGPoint {
            { r in
                let angle = r.unit() * 2 * .pi
                let radius = sqrt(r.unit()) * extent
                return CGPoint(x: radius * sin(angle), y: -radius * cos(angle))
            }
        }

        // The case ring, from the card's seat (1.0) out to the reeding (1.175).
        caseScratches = CompassGrain.scratches(
            46, &random, start: ring(1.0, 1.175), length: 0.05...0.60, alpha: 0.34...0.66)
        caseScuffs = CompassGrain.scratches(
            300, &random, start: ring(1.0, 1.175), length: 0.012...0.055, bend: 0.8,
            alpha: 0.12...0.30, width: 0.55...0.95, headings: [])
        caseDents = (0..<5).map { _ in
            let p = ring(1.03, 1.15)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.016 + random.unit() * 0.016, alpha: 0.55 + random.unit() * 0.3)
        }
        caseChips = CompassGrain.chips(9, &random, radius: 1.156...1.168)
        casePits = CompassGrain.pits(around: caseChips, perChip: 4...8, extra: 16,
                                     extraAt: ring(1.01, 1.17), &random)
        casePores = (0..<160).map { _ in
            let p = ring(1.0, 1.175)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.0016 + random.unit() * 0.003, alpha: 0.25 + random.unit() * 0.3)
        }

        // The lid's outside, where the hand takes it and the pocket wears it.
        coverScratches = CompassGrain.scratches(
            30, &random, start: disc(0.94), length: 0.08...0.65, alpha: 0.26...0.55)
        coverScuffs = CompassGrain.scratches(
            110, &random, start: disc(0.94), length: 0.015...0.07, bend: 0.8,
            alpha: 0.10...0.26, width: 0.55...0.95, headings: [])
        coverDents = (0..<4).map { _ in
            let p = disc(0.8)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.020 + random.unit() * 0.022, alpha: 0.5 + random.unit() * 0.3)
        }
        coverChips = CompassGrain.chips(5, &random, radius: 0.88...0.93)
        coverPits = CompassGrain.pits(around: coverChips, perChip: 4...6, extra: 8,
                                      extraAt: disc(0.9), &random)
        coverPores = (0..<90).map { _ in
            let p = disc(0.95)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.0016 + random.unit() * 0.003, alpha: 0.2 + random.unit() * 0.25)
        }

        // The engraved plate inside is protected, so it is scuffed rather than gouged.
        floorScratches = CompassGrain.scratches(
            14, &random, start: disc(0.9), length: 0.06...0.45, alpha: 0.18...0.38)
        floorScuffs = CompassGrain.scratches(
            60, &random, start: disc(0.9), length: 0.012...0.05, bend: 0.8,
            alpha: 0.08...0.20, width: 0.55...0.95, headings: [])
        floorPits = (0..<9).map { _ in
            let p = disc(0.92)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.003 + random.unit() * 0.005, alpha: 0.5 + random.unit() * 0.4)
        }

        // The centre boss, in boss-radius units.
        hubScratches = CompassGrain.scratches(
            7, &random, start: disc(0.9), length: 0.2...0.9, alpha: 0.30...0.55)
        hubPits = (0..<3).map { _ in
            let p = disc(0.8)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.04 + random.unit() * 0.05, alpha: 0.5 + random.unit() * 0.3)
        }

        // The suspension lug, in card-radius units: a stem running down from the case and a
        // ring on the end of it, which is where a chain's links have been wearing for decades.
        lugScratches = CompassGrain.scratches(
            7, &random,
            start: { r in CGPoint(x: (r.unit() - 0.5) * 0.12, y: 1.12 + r.unit() * 0.12) },
            length: 0.03...0.10, alpha: 0.30...0.55, headings: [1.4, 1.75])
        lugPits = (0..<4).map { _ in
            let angle = random.unit() * 2 * .pi
            let r = 0.062 + (random.unit() - 0.5) * 0.008
            return Blot(x: r * sin(angle), y: 1.303 - r * cos(angle),
                        radius: 0.004 + random.unit() * 0.004, alpha: 0.6 + random.unit() * 0.3)
        }
        // Along the hinge pin, where water sits: x in card-radius units, y is the pin's own.
        hingePits = (0..<7).map { _ in
            Blot(x: (random.unit() - 0.5) * 0.66, y: 0,
                 radius: 0.003 + random.unit() * 0.004, alpha: 0.55 + random.unit() * 0.35)
        }

        // The card. Faint folds, old watermarks, edge rubbing and flyspecks.
        creases = [
            Scratch(points: [CGPoint(x: -0.99, y: -0.16 + random.unit() * 0.1),
                             CGPoint(x: 0.0, y: 0.05 + random.unit() * 0.08),
                             CGPoint(x: 0.99, y: 0.26 + random.unit() * 0.1)],
                    alpha: 0.30, width: 1.0, bright: true),
            Scratch(points: [CGPoint(x: 0.34 + random.unit() * 0.1, y: -0.99),
                             CGPoint(x: 0.28 + random.unit() * 0.1, y: -0.55),
                             CGPoint(x: 0.22 + random.unit() * 0.1, y: -0.18)],
                    alpha: 0.22, width: 0.9, bright: true),
        ]
        tideLines = (0..<2).map { index in
            let start = (index == 0 ? 0.55 : 3.7) + random.unit() * 0.5
            let sweep = 1.0 + random.unit() * 0.9
            let base = 0.66 + random.unit() * 0.16
            let steps = 22
            let points = (0...steps).map { step -> CGPoint in
                let t = CGFloat(step) / CGFloat(steps)
                let angle = start + sweep * t
                let wobble = 1 + 0.035 * sin(t * 9 + CGFloat(index) * 2) + (random.unit() - 0.5) * 0.02
                return CGPoint(x: base * wobble * sin(angle), y: -base * wobble * cos(angle))
            }
            return Scratch(points: points, alpha: 0.30 - CGFloat(index) * 0.08, width: 1, bright: false)
        }
        paperRubs = CompassGrain.scratches(
            26, &random, start: ring(0.93, 0.995), length: 0.04...0.16, bend: 0.1,
            alpha: 0.22...0.42, width: 1.4...2.6, headings: [])
        dirtSpecks = (0..<70).map { _ in
            let p = disc(0.98)(&random)
            return Blot(x: p.x, y: p.y, radius: 0.0018 + random.unit() * 0.005, alpha: 0.25 + random.unit() * 0.3)
        }
    }

    func patina(radius: CGFloat) -> [Blot] { patinaBlots }
    func buffs(radius: CGFloat) -> [Buff] { self.buffs }
    func ageSpots(radius: CGFloat) -> [Blot] { spots }
    /// Broad mottling on the card, in card-radius units.
    func cardUnevenness(radius: CGFloat) -> [Blot] { cardBlotches }
    /// Broad mottling on the lid's face, in lid-plane units.
    func lidUnevenness(radius: CGFloat) -> [Blot] { lidBlotches }
    /// Tarnish on the inside of the lid, in lid-plane units (origin at the lid's boss).
    func lidPatina(radius: CGFloat) -> [Blot] { lidBlots }
    /// Rust in the hinge seam, in lid-plane units.
    func rust(radius: CGFloat) -> [Blot] { rustSpots }

    /// Fibre grain, tiled. A single noise fill under an affine transform: full per-pixel grain
    /// through the perspective divide would cost more than the whole rest of the frame and is
    /// invisible at this scale.
    func fill(in context: CGContext, scale: CGFloat) {
        context.saveGState()
        context.setFillColor(NSColor(patternImage: tile).cgColor)
        let extent = scale * 1.4
        context.fill(CGRect(x: -extent, y: -extent, width: extent * 2, height: extent * 2))
        context.restoreGState()
    }

    /// Scratches that run the way a pocket rubs them: most along a couple of shared directions,
    /// a minority anywhere. Random headings alone read as noise rather than as use. Lengths are
    /// weighted short, with the occasional long one.
    private static func scratches(
        _ count: Int,
        _ random: inout SplitMix64,
        start: (inout SplitMix64) -> CGPoint,
        length: ClosedRange<CGFloat>,
        bend: CGFloat = 0.35,
        alpha: ClosedRange<CGFloat>,
        width: ClosedRange<CGFloat> = 0.7...1.4,
        headings: [CGFloat] = [0.55, 2.35]
    ) -> [Scratch] {
        (0..<count).map { _ in
            var point = start(&random)
            var heading: CGFloat
            if !headings.isEmpty, random.unit() < 0.7 {
                heading = headings[random.unit() < 0.5 ? 0 : headings.count - 1] + (random.unit() - 0.5) * 0.5
            } else {
                heading = random.unit() * 2 * .pi
            }
            let total = length.lowerBound + pow(random.unit(), 2.4) * (length.upperBound - length.lowerBound)
            let step = total / 3
            var points = [point]
            for _ in 0..<3 {
                heading += (random.unit() - 0.5) * bend
                point = CGPoint(x: point.x + step * cos(heading), y: point.y + step * sin(heading))
                points.append(point)
            }
            return Scratch(
                points: points,
                alpha: alpha.lowerBound + random.unit() * (alpha.upperBound - alpha.lowerBound),
                width: width.lowerBound + random.unit() * (width.upperBound - width.lowerBound),
                bright: random.unit() < 0.78
            )
        }
    }

    /// Notches hugging a circular edge: wider along the edge than across it, and ragged.
    private static func chips(_ count: Int, _ random: inout SplitMix64, radius: ClosedRange<CGFloat>) -> [Chip] {
        (0..<count).map { _ in
            let angle = random.unit() * 2 * .pi
            let r = radius.lowerBound + random.unit() * (radius.upperBound - radius.lowerBound)
            let centre = CGPoint(x: r * sin(angle), y: -r * cos(angle))
            let tangent = CGPoint(x: cos(angle), y: sin(angle))
            let outward = CGPoint(x: sin(angle), y: -cos(angle))
            let along = 0.020 + random.unit() * 0.028
            let across = 0.008 + random.unit() * 0.011
            let sides = 7
            let shape = (0..<sides).map { k -> CGPoint in
                let theta = (CGFloat(k) + (random.unit() - 0.5) * 0.5) / CGFloat(sides) * 2 * .pi
                let a = along * cos(theta) * (0.65 + random.unit() * 0.7)
                let c = across * sin(theta) * (0.65 + random.unit() * 0.7)
                return CGPoint(x: centre.x + tangent.x * a + outward.x * c,
                               y: centre.y + tangent.y * a + outward.y * c)
            }
            return Chip(shape: shape)
        }
    }

    /// Rust pits: a little cluster at every chip, because bare iron-bearing brass is where it
    /// starts, and a few strays along the seam.
    private static func pits(
        around chips: [Chip],
        perChip: ClosedRange<Int>,
        extra: Int,
        extraAt: (inout SplitMix64) -> CGPoint,
        _ random: inout SplitMix64
    ) -> [Blot] {
        var all: [Blot] = []
        for chip in chips {
            let centre = CGPoint(
                x: chip.shape.map(\.x).reduce(0, +) / CGFloat(chip.shape.count),
                y: chip.shape.map(\.y).reduce(0, +) / CGFloat(chip.shape.count)
            )
            let n = perChip.lowerBound + Int(random.unit() * CGFloat(perChip.count))
            for _ in 0..<n {
                all.append(Blot(
                    x: centre.x + (random.unit() - 0.5) * 0.07,
                    y: centre.y + (random.unit() - 0.5) * 0.07,
                    radius: 0.004 + random.unit() * 0.008,
                    alpha: 0.6 + random.unit() * 0.4
                ))
            }
        }
        for _ in 0..<extra {
            let p = extraAt(&random)
            all.append(Blot(x: p.x, y: p.y, radius: 0.003 + random.unit() * 0.006, alpha: 0.5 + random.unit() * 0.4))
        }
        return all
    }

    private static func makeTile(size: Int, seed: inout SplitMix64) -> NSImage {
        let image = NSImage(size: NSSize(width: CGFloat(size), height: CGFloat(size)))
        image.lockFocus()
        defer { image.unlockFocus() }
        guard let context = NSGraphicsContext.current?.cgContext else { return image }
        for _ in 0..<(size * size / 3) {
            let x = CGFloat(seed.unit()) * CGFloat(size)
            let y = CGFloat(seed.unit()) * CGFloat(size)
            let value = 0.5 + (seed.unit() - 0.5) * 0.26
            let warm = seed.unit() < 0.5
            context.setFillColor(
                NSColor(
                    calibratedWhite: value,
                    alpha: warm ? 0.10 : 0.07
                ).cgColor
            )
            context.fill(CGRect(x: x, y: y, width: 1.2, height: 1.2))
        }
        return image
    }
}

/// A small deterministic generator.
///
/// `SystemRandomNumberGenerator` would be the obvious choice and is the wrong one here: this
/// data has to be identical across launches, and stable across Swift versions for the tests
/// around it to mean anything. SplitMix64 is three lines and exact.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in `[0, 1)`.
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(1 << 53)
    }
}
