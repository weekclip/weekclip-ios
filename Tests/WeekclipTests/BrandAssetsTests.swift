import Foundation
import Testing
import UIKit
import WeekclipPresentation

/// Brand assets, asserted against the built app bundle.
///
/// Every failure this suite covers is silent by construction — that is the
/// whole reason it exists:
///
///   · a face bundled but missing from `UIAppFonts` does not error, it renders
///     as San Francisco;
///   · a PostScript name with a typo does not error, `Font.custom` falls back
///     to the system face;
///   · an asset-catalog icon that failed to compile leaves an app that installs
///     with a white square;
///   · a logo asset without `template-rendering-intent` ignores
///     `foregroundStyle` and draws in its own colour.
///
/// None of those fail a build, a lint, or a maestro flow. They just look
/// slightly wrong to whoever opens the app, months later.
///
/// This runs in the app-hosted test bundle, so `Bundle.main` is the real app —
/// the same registration path the app itself takes. The Android port makes the
/// equivalent claims in `BrandAssetsTest.kt` and `scripts/check-brand-assets.sh`.
@MainActor
@Suite("brand assets")
struct BrandAssetsTests {

  // MARK: - Fonts

  @Test("every brand PostScript name resolves to a registered face")
  func fontsResolve() {
    for name in WeekclipFontName.allCases {
      let font = UIFont(name: name.rawValue, size: 17)
      #expect(font != nil, "\(name.rawValue) did not resolve — check UIAppFonts in Info.plist")

      // Non-nil is not quite enough. `UIFont(name:)` returns nil for an unknown
      // name, but asserting the round trip also pins that no substitution
      // happened, which is what would betray a family/PostScript mix-up.
      #expect(
        font?.fontName == name.rawValue,
        "asked for \(name.rawValue), got \(font?.fontName ?? "nil")"
      )
    }
  }

  @Test("Medium and Regular are two distinct outlines, not one file under two names")
  func weightsAreRealFaces() throws {
    let medium = try #require(UIFont(name: WeekclipFontName.interMedium.rawValue, size: 17))
    let regular = try #require(UIFont(name: WeekclipFontName.interRegular.rawValue, size: 17))

    // `familyName` is NOT the discriminator, which is worth stating because it
    // is the obvious thing to reach for and it silently agrees: CoreText
    // reports the typographic family (nameID 16), so all four Inter faces come
    // back as "Inter". An earlier version of this test asserted the families
    // differed and failed for exactly that reason.
    #expect(medium.familyName == regular.familyName)

    // The face attribute is the discriminator.
    let mediumFace = medium.fontDescriptor.object(forKey: .face) as? String
    let regularFace = regular.fontDescriptor.object(forKey: .face) as? String
    #expect(mediumFace == "Medium", "face was \(mediumFace ?? "nil")")
    #expect(regularFace == "Regular", "face was \(regularFace ?? "nil")")

    // And the metrics, which is the claim that actually matters: two different
    // sets of outlines are installed. This is what catches the same .ttf
    // vendored twice under different names — a copy/paste slip that every
    // name-based check above would happily pass.
    let probe = "WeekClip" as NSString
    let mediumWidth = probe.size(withAttributes: [.font: medium]).width
    let regularWidth = probe.size(withAttributes: [.font: regular]).width
    #expect(
      mediumWidth > regularWidth,
      "Medium (\(mediumWidth)) should set wider than Regular (\(regularWidth))"
    )
  }

  @Test("a bare family name resolves to Regular — which is why the enum holds PostScript names")
  func familyNameAloneReachesRegular() throws {
    // Pins the measurement `WeekclipFontName`'s documentation rests on. If a
    // future OS made "Inter" resolve to something else, the reasoning in that
    // file would need rewriting, and this is where that shows up.
    let byFamily = try #require(UIFont(name: "Inter", size: 17))
    #expect(
      byFamily.fontName == WeekclipFontName.interRegular.rawValue,
      "family lookup gave \(byFamily.fontName)"
    )
  }

  @Test("UIAppFonts and the bundled font files agree in both directions")
  func fontRegistrationMatchesTheBundle() {
    let declared = Set(
      (Bundle.main.object(forInfoDictionaryKey: "UIAppFonts") as? [String] ?? [])
    )
    #expect(!declared.isEmpty, "UIAppFonts is empty — no bundled face is registered")

    let bundled = Set(
      (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
        .map { $0.lastPathComponent }
    )

    // A face in the bundle but not in the plist is dead weight that renders as
    // San Francisco; one in the plist but not the bundle is a name that will
    // never resolve. Both directions, because each is a different mistake.
    #expect(
      declared.subtracting(bundled).isEmpty,
      "UIAppFonts names files that are not in the bundle: \(declared.subtracting(bundled))"
    )
    #expect(
      bundled.subtracting(declared).isEmpty,
      "bundled but unregistered: \(bundled.subtracting(declared))"
    )
  }

  @Test("the SIL OFL licences ship inside the app")
  func licencesAreBundled() {
    // OFL 1.1 clause 2: the licence travels with the font. In the repo is not
    // the same as in the binary, and the binary is what is distributed.
    for licence in ["Inter-OFL", "SpaceGrotesk-OFL"] {
      let url = Bundle.main.url(forResource: licence, withExtension: "txt")
      #expect(url != nil, "\(licence).txt is not in the app bundle")

      let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
      #expect(
        text.contains("SIL OPEN FONT LICENSE"),
        "\(licence).txt does not look like the OFL"
      )
    }
  }

  // MARK: - Artwork

  @Test("the app icon compiled into the bundle")
  func appIconIsPresent() {
    // Xcode injects CFBundleIcons at build time from the compiled asset
    // catalog. An icon set that failed to compile — or one whose name does not
    // match ASSETCATALOG_COMPILER_APPICON_NAME — leaves this absent, and the
    // app installs with a white square.
    let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
    let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
    let files = primary?["CFBundleIconFiles"] as? [String] ?? []

    #expect(!files.isEmpty, "no CFBundleIconFiles — AppIcon did not compile into the bundle")
  }

  @Test("the logo asset loads and is a tintable template")
  func logoAssetIsATemplate() {
    let image = UIImage(named: "WeekclipLogo", in: .main, compatibleWith: nil)
    #expect(image != nil, "WeekclipLogo is missing from the asset catalog")

    // Without the template intent the mark draws in its own colour and
    // `foregroundStyle` is quietly ignored — which is the opposite of how the
    // design system defines the mark (it is a mask, painted by a token).
    #expect(
      image?.renderingMode == .alwaysTemplate,
      "WeekclipLogo is not a template image; check template-rendering-intent in Contents.json"
    )
  }

  @Test("the accent colour is the design system's accent")
  func accentColourMatchesTheToken() {
    let colour = UIColor(named: "AccentColor", in: .main, compatibleWith: nil)
    #expect(colour != nil, "AccentColor has no value — it shipped as an empty colorset")

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    colour?.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

    // color.accent.default = #5B53FF. Tolerance is one 8-bit step; the catalog
    // stores and returns these as floats.
    #expect(abs(red - 0x5B / 255) < 0.004, "red \(red)")
    #expect(abs(green - 0x53 / 255) < 0.004, "green \(green)")
    #expect(abs(blue - 1.0) < 0.004, "blue \(blue)")
    #expect(abs(alpha - 1.0) < 0.004, "alpha \(alpha)")
  }
}
