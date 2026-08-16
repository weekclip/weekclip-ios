import SwiftUI

/// The brand faces, by PostScript name.
///
/// ## Why PostScript names and not a family name
///
/// Inter and Space Grotesk ship here as separate static instances, one file per
/// weight. Measured on the simulator (the numbers are in `BrandAssetsTests`):
///
///   · `UIFont(name: "Inter", size: 17)` resolves to **Inter-Regular**. A bare
///     family name reaches exactly one of the four faces, and it is not the one
///     you asked for unless you wanted Regular. Nothing reports an error.
///   · All four report `familyName == "Inter"` — CoreText uses the typographic
///     family (nameID 16), not the per-weight legacy family the files also
///     carry. So family name alone cannot distinguish them.
///   · A `UIFontDescriptor` with family + `.weight` *does* reach Inter-Medium.
///     That path works; it is simply not the one `Font.custom(_:size:)` takes,
///     and it is more machinery to reach a file that already has a unique name.
///
/// A PostScript name identifies exactly one file, which is why every entry
/// below is one. `BrandAssetsTests` iterates this enum and asserts each name
/// round-trips through `UIFont(name:size:)`, so a typo here fails a test
/// instead of quietly falling back to San Francisco.
public enum WeekclipFontName: String, CaseIterable, Sendable {
  case interRegular = "Inter-Regular"
  case interMedium = "Inter-Medium"
  case interSemiBold = "Inter-SemiBold"
  case interBold = "Inter-Bold"
  case spaceGroteskRegular = "SpaceGrotesk-Regular"
  case spaceGroteskMedium = "SpaceGrotesk-Medium"
  case spaceGroteskBold = "SpaceGrotesk-Bold"
}

/// The type roles this app uses, mapped onto the two brand faces.
///
/// The split mirrors `weekclip-design-system`'s two stacks and the Android
/// port's Typography: Space Grotesk for display/title roles, Inter for
/// everything that is read rather than scanned.
///
/// `headline` is Inter on purpose. On iOS `headline` is not a heading — it is
/// the emphasised body role that a `List` row title uses, and web renders those
/// in the base family. Android draws the same line at `titleMedium`.
///
/// CJK is deliberately not bundled; the platform fallback covers it. The
/// reasoning is in `docs/brand-assets.md` and in Android's `Type.kt`.
public enum WeekclipTextStyle: Sendable {
  case largeTitle
  case title
  case title2
  case title3
  case headline
  case subheadline
  case body
  case callout
  case footnote
  case caption

  fileprivate var face: WeekclipFontName {
    switch self {
    case .largeTitle, .title, .title2, .title3: return .spaceGroteskMedium
    case .headline: return .interSemiBold
    case .subheadline, .body, .callout, .footnote, .caption: return .interRegular
    }
  }

  /// Point size at the default (Large) content size — the same numbers Apple
  /// uses for the matching `Font.TextStyle`, so swapping the face does not also
  /// silently resize the app.
  fileprivate var size: CGFloat {
    switch self {
    case .largeTitle: return 34
    case .title: return 28
    case .title2: return 22
    case .title3: return 20
    case .headline: return 17
    case .subheadline: return 15
    case .body: return 17
    case .callout: return 16
    case .footnote: return 13
    case .caption: return 12
    }
  }

  /// The system style this scales against.
  ///
  /// Without this, a custom font is a *fixed* size: Dynamic Type stops working
  /// and the app ignores the user's text-size setting entirely. That is the
  /// single most common regression introduced by adopting a brand face, and it
  /// is invisible unless someone moves the slider.
  fileprivate var relativeTo: Font.TextStyle {
    switch self {
    case .largeTitle: return .largeTitle
    case .title: return .title
    case .title2: return .title2
    case .title3: return .title3
    case .headline: return .headline
    case .subheadline: return .subheadline
    case .body: return .body
    case .callout: return .callout
    case .footnote: return .footnote
    case .caption: return .caption
    }
  }
}

extension Font {
  /// A brand face in the given role, still scaling with Dynamic Type.
  ///
  /// Use this instead of `.font(.title3)` and friends — the system styles use
  /// San Francisco and will not pick up a bundled face on their own.
  public static func weekclip(_ style: WeekclipTextStyle) -> Font {
    .custom(style.face.rawValue, size: style.size, relativeTo: style.relativeTo)
  }
}
