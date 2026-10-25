import SwiftUI
import UIKit

// MARK: - Hex entry point

extension Color {
    /// The single way a literal colour enters the app.
    ///
    /// Every value below is sRGB. Keeping one initialiser means a palette change is a one-line edit
    /// rather than a search for four different `Color(red:green:blue:)` spellings.
    init(taptionHex value: UInt32) {
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Primitives

/// Raw palette. Nothing outside this file should reference these — use `TaptionTheme` instead.
///
/// The ramp is a single hue family (teal-slate, ~195°) plus one warm accent. Every step is a
/// hand-picked value that already shipped; the names describe lightness, not usage, so a semantic
/// token can be re-pointed without renaming the palette.
enum TaptionColor {
    static let ink1000 = Color(taptionHex: 0x0B1B21)
    static let ink900 = Color(taptionHex: 0x0F191E)
    static let ink800 = Color(taptionHex: 0x182931)
    static let ink700 = Color(taptionHex: 0x1D333D)
    static let ink600 = Color(taptionHex: 0x203E48)
    static let ink500 = Color(taptionHex: 0x2F4650)
    static let ink400 = Color(taptionHex: 0x526E7A)
    static let ink300 = Color(taptionHex: 0x78909B)
    static let ink200 = Color(taptionHex: 0x9AAFBA)
    static let ink100 = Color(taptionHex: 0xE8F3F7)

    /// The one palette step that clears 3:1 against every surface (3.70:1 on `surface`).
    /// It exists for control boundaries — see `TaptionTheme.focusBorder` and §3.4 F1 of the
    /// design-system document.
    static let focus500 = Color(taptionHex: 0x628391)

    static let cyan500 = Color(taptionHex: 0x6DD0E5)
    static let coral500 = Color(taptionHex: 0xEBA58B)
    static let mint500 = Color(taptionHex: 0x91CBB6)
    static let amber500 = Color(taptionHex: 0xE5C184)
}

// MARK: - Semantic colours

/// The colour contract the UI codes against.
///
/// Names describe a role, never an appearance: `border` is "the hairline around a surface", so
/// re-pointing it to a different primitive is not a breaking change. Every value here was already
/// in production; this type only gives the existing palette a name and a place to live.
enum TaptionTheme {
    static let appBackground = TaptionColor.ink900
    static let surface = TaptionColor.ink800
    static let elevatedSurface = TaptionColor.ink700
    static let selectedSurface = TaptionColor.ink600
    static let border = TaptionColor.ink500
    static let strongBorder = TaptionColor.ink400
    /// The border for anything interactive or focused. `border` stays decorative; this is
    /// the one that carries WCAG 1.4.11's 3:1 control-boundary requirement (§3.4 F1).
    static let focusBorder = TaptionColor.focus500
    static let primaryText = TaptionColor.ink100
    static let mutedText = TaptionColor.ink200
    static let disabledText = TaptionColor.ink300
    static let accent = TaptionColor.cyan500
    static let accentButtonText = TaptionColor.ink1000
    static let coral = TaptionColor.coral500
    static let success = TaptionColor.mint500
    static let reward = TaptionColor.amber500

    static let cardContentPadding: CGFloat = 12
}

// MARK: - Typography

/// Text styles, expressed as Dynamic Type styles rather than fixed sizes.
///
/// The app has to stay readable when the user turns text size up, so nothing here pins a point
/// size. `monospacedDigit` is called out separately because progress readouts jitter when the
/// digits change width.
enum TaptionType {
    static let screenTitle = Font.title2.weight(.bold)
    static let sectionTitle = Font.title3.weight(.semibold)
    static let rowTitle = Font.body.weight(.semibold)
    static let body = Font.body
    static let secondary = Font.subheadline
    static let caption = Font.caption
    static let button = Font.body.weight(.semibold)
    static let compactButton = Font.caption.weight(.semibold)
    static let numeric = Font.body.monospacedDigit()
    static let numericCaption = Font.caption.monospacedDigit()

    /// Header text shrinks one step on dense layouts instead of truncating.
    static func header(compact: Bool) -> Font {
        compact ? .subheadline : .title3
    }

    static func button(compact: Bool) -> Font {
        compact ? compactButton : button
    }
}

// MARK: - Spacing

/// A 4 pt grid with the few half-steps the layout actually uses.
///
/// The home screen computes most of its spacing from a scale factor, so these constants are for
/// fixed chrome — padding inside a card, the gap between a label and its value — not for the
/// proportional layout in `HomeLayoutMetrics`.
enum TaptionSpacing {
    static let hairline: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let s: CGFloat = 8
    static let sm: CGFloat = 10
    static let m: CGFloat = 12
    static let ml: CGFloat = 14
    static let l: CGFloat = 18
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

// MARK: - Radius

enum TaptionRadius {
    /// Chips and small badges.
    static let small: CGFloat = 4
    /// The default: cards, banners, buttons. 81 call sites already agree on it.
    static let medium: CGFloat = 8
    static let large: CGFloat = 18
    /// Fully rounded, for pill-shaped controls.
    static let pill: CGFloat = 999

    static let card = medium
    static let control = medium
}

// MARK: - Motion

/// Durations and curves for state changes.
///
/// The app animates a lot of small things (banner slides, card expansion). Keeping the numbers in
/// one place is what stops "0.22" and "0.2" from both existing.
enum TaptionMotion {
    /// Hover, highlight, colour changes.
    static let quick = Animation.easeOut(duration: 0.16)
    /// The default for layout changes.
    static let standard = Animation.easeOut(duration: 0.22)
    /// Sheets and full-screen transitions.
    static let slow = Animation.easeInOut(duration: 0.35)
    /// Spring for anything the finger directly moves.
    static let interactive = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// The curve to actually run, given the Reduce Motion setting (§7).
    ///
    /// A spring overshoots and settles, which is exactly the travel the setting asks us to drop, so
    /// it becomes an instant change rather than a shorter spring. `nil` is accepted by both
    /// `withAnimation` and `.animation(_:value:)`.
    static func spring(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// A transition that carries travel (a slide, a zoom) collapses to a cross-fade. One that is
    /// already a fade passes through untouched, so callers can route every transition through here
    /// without having to remember which is which.
    static func transition(_ transition: AnyTransition, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : transition
    }
}

// MARK: - Elevation

/// Shadow recipes. The palette is dark, so elevation is carried by surface lightness first and by
/// shadow only where a view floats above content.
enum TaptionElevation {
    static let card = Shadow(color: .black.opacity(0.18), radius: 6, y: 2)
    static let floating = Shadow(color: .black.opacity(0.28), radius: 16, y: 6)

    struct Shadow {
        let color: Color
        let radius: CGFloat
        let y: CGFloat
    }
}

extension View {
    func taptionShadow(_ shadow: TaptionElevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: 0, y: shadow.y)
    }
}

// MARK: - Device classes

/// The shapes the layout has to serve.
///
/// The app ships one binary to iPhones, iPads and the foldable, and the foldable changes class
/// while it is running. Deriving the class from geometry (rather than the idiom) is what lets the
/// same code answer correctly before and after an unfold — see `HomeLayoutMetrics`.
enum TaptionDeviceClass: Equatable {
    /// A normal iPhone, folded or not.
    case phone
    /// A folded foldable: wider and markedly shorter than any iPhone.
    case foldableOuter
    /// An unfolded foldable: iPad-sized, still reporting `.phone`.
    case foldableInner
    /// A real iPad.
    case pad

    /// Height-to-width ratio below which a compact screen is treated as a folded foldable.
    ///
    /// An iPhone 18 Pro Max is 956/440 ≈ 2.17 tall; the Duo outer display is 678/466 ≈ 1.46. 1.75
    /// sits in the gap with room on both sides.
    static let foldedAspectThreshold: CGFloat = 1.75

    static func resolve(size: CGSize, userInterfaceIdiom: UIUserInterfaceIdiom) -> TaptionDeviceClass {
        let shortSide = min(size.width, size.height)
        let longSide = max(size.width, size.height)
        let isWide = HomeLayoutMetrics.usesWideLayout(size: size, userInterfaceIdiom: userInterfaceIdiom)

        if userInterfaceIdiom == .pad && shortSide >= 700 {
            return .pad
        }
        if isWide {
            return .foldableInner
        }
        if shortSide > 0, longSide / shortSide < foldedAspectThreshold {
            return .foldableOuter
        }
        return .phone
    }

    var isWide: Bool {
        self == .pad || self == .foldableInner
    }

    /// How much of the vertical rhythm to keep. The outer display is 678 pt tall, which is shorter
    /// than any modern iPhone, so it gets the dense spacing rather than the comfortable one.
    var verticalRhythm: CGFloat {
        switch self {
        case .phone, .pad: return 1
        case .foldableOuter: return 0.85
        case .foldableInner: return 1
        }
    }
}
