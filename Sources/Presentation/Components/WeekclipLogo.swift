import SwiftUI

/// The sizes the design system defines for the mark
/// (`.wc-logo--sm` / `.wc-logo` / `--lg` / `--xl` in
/// `weekclip-design-system/packages/web/src/components/logo.css`).
public enum WeekclipLogoSize: CGFloat, Sendable {
  case small = 20
  case medium = 28
  case large = 40
  case extraLarge = 64
}

/// The brand mark.
///
/// The artwork is `WeekclipLogo` in the app's asset catalog — the design
/// system's `logo.svg` verbatim, stored with `preserves-vector-representation`
/// so it stays sharp at any size, and with a template rendering intent so the
/// colour comes from the view rather than the file.
///
/// That template intent is the port of how web does it: `.wc-logo` is a
/// `mask-image` with `background-color` painting through it, so the mark takes
/// a token rather than carrying a colour. Here `foregroundStyle` plays that
/// part, and it defaults to the accent — which is the same token, since
/// `AccentColor` in the catalog is `color.accent.default`.
///
/// The asset lives in the *app* target while this view lives in a SwiftPM
/// module, so the lookup goes through `Bundle.main`. That is correct at runtime
/// and in the app-hosted test bundle. It does mean an Xcode preview rendered
/// from the package alone has no asset catalog to find, which is why the
/// previews below are not the thing that proves this works — `BrandAssetsTests`
/// is.
public struct WeekclipLogoMark: View {
  private let size: WeekclipLogoSize
  private let accessibilityLabelText: String?

  /// - Parameters:
  ///   - size: one of the design system's four sizes.
  ///   - accessibilityLabelText: what VoiceOver reads. Pass `nil` when the mark
  ///     sits beside the wordmark — ``WeekclipLogoLockup`` does, because the
  ///     wordmark is already text and labelling both announces the name twice.
  public init(size: WeekclipLogoSize = .medium, accessibilityLabelText: String? = "WeekClip") {
    self.size = size
    self.accessibilityLabelText = accessibilityLabelText
  }

  public var body: some View {
    Image("WeekclipLogo")
      .resizable()
      .scaledToFit()
      .frame(width: size.rawValue, height: size.rawValue)
      .foregroundStyle(Color.accentColor)
      .accessibilityIdentifier("brand-logo")
      .modifier(LogoAccessibility(label: accessibilityLabelText))
  }
}

/// `accessibilityLabel` takes a non-optional, and the two branches have
/// different types, so the choice is made in a modifier rather than with an
/// `if` in the view body.
private struct LogoAccessibility: ViewModifier {
  let label: String?

  func body(content: Content) -> some View {
    if let label {
      content.accessibilityLabel(Text(label))
    } else {
      content.accessibilityHidden(true)
    }
  }
}

/// Mark + "WeekClip" wordmark, the horizontal lockup.
///
/// The 8pt gap, the bold 16pt wordmark and its -0.01em tracking are
/// `.wc-logo-lockup`'s values. The wordmark is the *base* face (Inter), not the
/// heading face — web sets `font-family: var(--typography-font-family-base)`
/// there. Space Grotesk is for headings; a wordmark is neither.
///
/// Tracking is given in points because SwiftUI has no em unit: -0.01em at 16pt
/// is -0.16pt.
public struct WeekclipLogoLockup: View {
  private let size: WeekclipLogoSize

  public init(size: WeekclipLogoSize = .medium) {
    self.size = size
  }

  public var body: some View {
    HStack(spacing: 8) {
      WeekclipLogoMark(size: size, accessibilityLabelText: nil)
      Text(verbatim: "WeekClip")
        .font(.custom(WeekclipFontName.interBold.rawValue, size: 16, relativeTo: .body))
        .tracking(-0.16)
    }
    // One element reading "WeekClip", rather than a hidden image followed by a
    // text node.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "WeekClip"))
    .accessibilityIdentifier("brand-lockup")
  }
}
