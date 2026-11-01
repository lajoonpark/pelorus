import AppKit
import SwiftUI
import RadialCore

/// The compass's materials.
///
/// Every colour here was measured, not eyeballed, because the dial is read in a glance at an
/// arbitrary place on someone's screen. Ratios in the comments are against the surface the ink
/// is actually printed on, using the same WCAG formula the rest of the app's palette is set by.
///
/// The one rule borrowed from the old instrument theme: exactly one saturated colour (the
/// vermilion needle) and it is only ever used for what you are aiming at. Everything else is
/// paper, brass, or the ink that sits on them.
enum CompassTheme {

    // MARK: - Wear

    /// How strongly the instrument reads as used.
    ///
    /// Every wear layer in `CompassGrain` is generated with its own alpha, and those alphas are
    /// individually tiny — 0.04-0.10 — because they were tuned on a bright new brass ramp where
    /// anything heavier looked like dirt. Once the ramp was aged down the wear stopped reading
    /// at all and the compass went back to looking new, which is the one thing the brief rules
    /// out. Scaling the whole family by one number keeps their relative weights intact and
    /// leaves a single place to tune. 1.3 is the point where the outer third of the card is
    /// visibly uneven in tone while no single blot is identifiable as a stain; the web harness
    /// (`preview/compass-preview.html?age=`) uses the same number, so what is approved there is
    /// what ships.
    static let wearGain: CGFloat = 1.3

    /// How strongly the hard-edged marks read: scratches, dents, chips, rust pits, creases.
    ///
    /// Separate from `wearGain` because the two kinds of wear fail differently. Soft blots turned
    /// up become a stain; sharp marks turned up become damage. Keeping them apart means the
    /// tonal ageing and the scars can be tuned independently. 1 is a compass that has been
    /// carried and used; past about 1.6 it starts to look dropped.
    static let damageGain: CGFloat = 1.0

    /// Whether the hard-edged wear is drawn at all, from the "Worn brass" setting.
    ///
    /// A process-wide switch rather than a parameter, because the renderer is reached through
    /// the overlay, the manager's embedded dial and the welcome art, and all of them should look
    /// the same at any moment. `SettingsModel` is the only writer. Off, the compass is the one
    /// that had only soft ageing: tarnish, foxing and buffing, none of the scars.
    static var isWorn = Preferences.default.compassWorn

    // MARK: - Paper

    /// The card itself. Aged cream, never white: white paper reads as a new print.
    static let paper = NSColor(calibratedRed: 0.863, green: 0.804, blue: 0.667, alpha: 1)
    /// Where the light falls on it.
    /// The card's highlight. Pulled down from near-white while ageing the instrument: the old
    /// value (0.918/0.867/0.745) made the middle of the dial the brightest thing on screen,
    /// which is what made a century-old card still read as fresh stock.
    static let paperLit = NSColor(calibratedRed: 0.878, green: 0.820, blue: 0.694, alpha: 1)
    /// Aged, toward the rim.
    static let paperDeep = NSColor(calibratedRed: 0.741, green: 0.659, blue: 0.494, alpha: 1)
    /// The browned edge where card meets brass.
    static let paperEdge = NSColor(calibratedRed: 0.529, green: 0.439, blue: 0.290, alpha: 1)

    // MARK: - Ink

    /// Slice names. 9.3:1 on `paper`, 6.3:1 on the aged rim.
    static let ink = NSColor(calibratedRed: 0.200, green: 0.149, blue: 0.102, alpha: 1)
    /// The printed degree scale and the engraved rules. Decoration, so it may sit lower.
    static let inkRule = NSColor(calibratedRed: 0.227, green: 0.173, blue: 0.102, alpha: 1)

    // MARK: - Signal

    /// The needle, the aimed numeral, the aimed wedge's rule. Deep vermilion rather than the
    /// old orange: 5.0:1 on `paper` and 5.9:1 on the numeral gate, where orange managed 2.3:1
    /// on the old hovered fill and made the aimed label the least readable thing on screen.
    static let vermilion = NSColor(calibratedRed: 0.561, green: 0.196, blue: 0.133, alpha: 1)
    /// A lighter vermilion for the needle's lit edge, where it is a line rather than ink.
    static let vermilionLit = NSColor(calibratedRed: 0.706, green: 0.267, blue: 0.180, alpha: 1)

    // MARK: - Brass

    /// Tarnished, not polished. Highlights stay warm rather than white and the shadows go
    /// olive rather than chocolate, which is the difference between "carried for years" and
    /// "polished this morning".
    /// The brass ramp, aged. A new instrument is a bright yellow-gold with a pale highlight;
    /// this one has been carried for a century, so the highlight is a warm bone rather than
    /// white and the two middle stops are pulled down and slightly grey. The *spread* between
    /// the stops is what still reads as polished metal — flattening it makes the case look like
    /// painted plastic — so the highlights barely move and the mids do most of the darkening.
    static let brassHi = NSColor(calibratedRed: 0.835, green: 0.752, blue: 0.560, alpha: 1)
    static let brassLit = NSColor(calibratedRed: 0.702, green: 0.570, blue: 0.342, alpha: 1)
    static let brassMid = NSColor(calibratedRed: 0.522, green: 0.398, blue: 0.216, alpha: 1)
    static let brassDark = NSColor(calibratedRed: 0.352, green: 0.264, blue: 0.145, alpha: 1)
    static let brassDeep = NSColor(calibratedRed: 0.186, green: 0.152, blue: 0.092, alpha: 1)
    /// The olive-grey bloom of age on brass. Not rust: this is a cool, matte film.
    static let patina = NSColor(calibratedRed: 0.268, green: 0.252, blue: 0.170, alpha: 1)

    /// The warm bloom that tarnish leaves where the lacquer has gone. Distinct from `patina`:
    /// the film on brass is cool and matte, this is the brown it turns where a hand has been
    /// resting for decades. Used as a broad, very faint wash, never as a spot.
    static let tarnishWarm = NSColor(calibratedRed: 0.400, green: 0.286, blue: 0.150, alpha: 1)

    /// Rust, used sparingly and only in seams and around steel pins.
    ///
    /// Warm red-brown, well short of orange: at full strength orange on brass reads as paint.
    /// Kept to a few small spots, because the brief was "old and worn, not damaged" — rust
    /// spread across a plate looks like neglect, whereas rust in a hinge seam looks like use.
    static let rust = NSColor(calibratedRed: 0.451, green: 0.231, blue: 0.118, alpha: 1)
    /// The dark bloom rust leaves in the metal around the spot itself.
    static let rustBloom = NSColor(calibratedRed: 0.322, green: 0.176, blue: 0.098, alpha: 1)

    /// Inside the lid: smoke-stained and darker than the case.
    static let lidRecessInner = NSColor(calibratedRed: 0.427, green: 0.353, blue: 0.220, alpha: 1)
    static let lidRecessOuter = NSColor(calibratedRed: 0.200, green: 0.161, blue: 0.102, alpha: 1)

    // MARK: - Hub

    /// The readout window in the centre boss. 10.3:1 for `brassHi` on it, so the aimed slot
    /// number is the most legible thing on the instrument.
    static let hubWindow = NSColor(calibratedRed: 0.180, green: 0.129, blue: 0.075, alpha: 1)
    static let hubWindowInk = NSColor(calibratedRed: 0.929, green: 0.878, blue: 0.749, alpha: 1)

    // MARK: - Backdrop

    /// The scrim under the instrument. Warm and dark, never neutral grey.
    static let shadow = NSColor(calibratedRed: 0.075, green: 0.059, blue: 0.039, alpha: 1)
    static let backdropAlpha: CGFloat = 0.90
    static let backdropMidAlpha: CGFloat = 0.62

    // MARK: - Type

    /// A serif for anything printed on the card.
    ///
    /// Baskerville ships on every Mac and is the face the reference photo's card is lettered
    /// in. Palatino is the fallback, then Times, so this degrades rather than failing if a
    /// machine is trimmed down.
    static func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        let candidates: [String]
        switch weight {
        case .bold, .heavy, .black:
            candidates = ["Baskerville-SemiBold", "Baskerville-Bold", "Palatino-Bold"]
        case .semibold, .medium:
            candidates = ["Baskerville-SemiBold", "Baskerville", "Palatino-Roman"]
        default:
            candidates = ["Baskerville", "Palatino-Roman", "TimesNewRomanPSMT"]
        }
        for name in candidates {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// The face wedge names are printed in: Baskerville Bold, because the semibold's hairlines
    /// disappear into the card's grain at dial sizes.
    static func label(_ size: CGFloat) -> NSFont {
        for name in ["Baskerville-Bold", "Palatino-Bold", "TimesNewRomanPS-BoldMT"] {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    // MARK: - Printing

    /// Degrees between the card's scale ticks.
    static let scaleStepDegrees = 5
    /// Half-width of the clear gate cut through the tick ring for each slate numeral, as a
    /// fraction of one slice's arc. Real compass cards interrupt the scale the same way.
    static let numeralGateHalf: CGFloat = 0.30
}

/// The same materials, for SwiftUI.
///
/// `CompassTheme` is an `NSColor` palette because the instrument is drawn on an `NSView` canvas.
/// The manager's mini dial and the welcome art are SwiftUI `Canvas`es, whose `GraphicsContext`
/// refuses anything but `Color`, and there is no implicit conversion between the two on Darwin.
///
/// Alpha is a parameter rather than `.opacity(…)` on purpose: `opacity(_:)` is SwiftUI's, so
/// `NSColor.opacity(0.3)` does not compile — the shade has to be applied with
/// `withAlphaComponent` before the colour crosses over.
extension NSColor {
    func swiftUI(alpha: CGFloat = 1) -> Color {
        Color(nsColor: alpha >= 1 ? self : withAlphaComponent(alpha))
    }
}
