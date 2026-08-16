# Brand assets — provenance

Where the bundled fonts and the logo artwork came from, and why they are shaped
the way they are. The Android port has the same file; keep them in step.

## Fonts

| Family | Weights bundled | Licence | Upstream |
|---|---|---|---|
| Inter 4.1 | Regular 400, Medium 500, SemiBold 600, Bold 700 | SIL OFL 1.1 | [rsms/inter v4.1](https://github.com/rsms/inter/releases/tag/v4.1), `extras/ttf/` |
| Space Grotesk | Regular 400, Medium 500, Bold 700 | SIL OFL 1.1 | [floriankarsten/space-grotesk](https://github.com/floriankarsten/space-grotesk), `fonts/ttf/static/` |

Files live in `App/Resources/Fonts/`, licences in `App/Resources/Licenses/` —
both are copied into the app bundle, because OFL 1.1 clause 2 requires the
licence to travel with the font and "it is in the repo" is not the same as "it
is in the thing we distribute".

Static instances rather than the variable files: selecting a weight from a
variable font on iOS means going through `UIFontDescriptor` variation axes, and
getting it subtly wrong renders at the default weight without erroring.

**Registration is not automatic.** iOS registers what `UIAppFonts` in
`Info.plist` names, not what happens to be in the bundle. A face that is present
but unlisted resolves to `nil` at `Font.custom`, and SwiftUI silently draws San
Francisco instead. That is why `BrandAssetsTests` asserts every PostScript name
resolves rather than trusting the list.

### Why PostScript names, not a family name

Measured on the simulator (the assertions are in `BrandAssetsTests`):

- `UIFont(name: "Inter", size: 17)` → **Inter-Regular**. A bare family name
  reaches exactly one of the four faces, silently.
- All four report `familyName == "Inter"`: CoreText uses the typographic family
  (nameID 16), not the per-weight legacy family the files also carry. So the
  family name cannot distinguish them.
- A `UIFontDescriptor` with family + `.weight` *does* reach Inter-Medium. That
  path works — it is simply not the one `Font.custom(_:size:)` takes.

`WeekclipFontName` therefore holds PostScript names, each identifying exactly
one file, and the test asserts the round trip.

### Dynamic Type

Every role goes through `Font.custom(_:size:relativeTo:)`. Without
`relativeTo:`, a custom font is a *fixed* size and the app ignores the user's
text-size setting entirely — the single most common regression introduced by
adopting a brand face, and invisible unless someone moves the slider.

The navigation bar is the exception SwiftUI does not cover: `.navigationTitle`
renders inside a `UINavigationBar` and no modifier reaches its font.
`WeekclipAppearance` sets it through the appearance proxy, scaled with
`UIFontMetrics` for the same reason.

### Which face renders what

Mirrors `weekclip-design-system/packages/tokens/tokens.json`:

- `typography.fontFamily.base` → **Inter** → body, callout, footnote, caption,
  and `headline`
- `typography.fontFamily.heading` → **Space Grotesk** → largeTitle, title,
  title2, title3

`headline` is Inter on purpose. On iOS it is not a heading — it is the
emphasised body role a `List` row title uses, and web renders those in the base
family. Android draws the same line at `titleMedium`.

### CJK is deliberately not bundled

The web stacks name Noto Sans KR / JP / SC after Inter, sliced by
`unicode-range` down to ~30–60 KB of actual glyphs. There is no such slicing for
a file in an app bundle: a full Noto CJK face is 5–10 MB and there are three.

Neither Inter nor Space Grotesk contains a Hangul, kana or Han glyph, so the
system font fallback resolves those runs to the platform CJK face on its own —
the same outcome the web stacks describe, with a better source.

## Logo and icon

Canonical vector source:
`weekclip-design-system/packages/assets/logo/logo.svg` — one filled path in a
`0 0 687 687` viewBox, `#5B53FF` (`color.accent.default`).

| Asset | Notes |
|---|---|
| `Assets.xcassets/WeekclipLogo.imageset` | `logo.svg` verbatim, `preserves-vector-representation`, **template** rendering intent |
| `Assets.xcassets/AppIcon.appiconset` | 1024×1024, generated from the same path on a `#0C0E16` plate |
| `Assets.xcassets/AccentColor.colorset` | `#5B53FF`. It shipped **empty** until 2026-08-16, so `Color.accentColor` was the system blue |

The template intent is the port of how web paints the mark: `.wc-logo` is a
`mask-image` with `background-color` showing through, so the mark takes a token
rather than carrying a colour. Here `foregroundStyle` plays that part. Without
the intent the mark draws in its own colour and the modifier is ignored.

### The app icon

Composed at 1024×1024 with the mark's ink (539.422 × 610.100, centred at
343.211, 344.141) scaled to 600px tall and centred:

```
scale = 600 / 610.100 = 0.983445
tx    = 512 - 343.211 × scale = 174.471
ty    = 512 - 344.141 × scale = 173.556
```

**No alpha channel.** The file is re-encoded to RGB after rasterisation, because
App Store Connect rejects a marketing icon that has one — and it rejects it at
upload, after the app has built, installed and run perfectly.
`scripts/check-brand-assets.sh` checks this with `sips`; the check was proven by
feeding it the pre-conversion RGBA file.

`#0C0E16` is `color.bg.panel` (dark), the same plate the design system's
`favicon.svg` uses, so the app icon, the browser favicon and the Android
launcher icon agree.

## Checks

- `scripts/check-brand-assets.sh` — `UIAppFonts` ↔ bundled files in both
  directions, PostScript names have files, licences present, icon is
  1024/RGB/no-alpha, AccentColor holds a colour. Runs in CI before the
  toolchain.
- `Tests/WeekclipTests/BrandAssetsTests.swift` — what only a running app can
  see: names resolve, Medium and Regular are distinct outlines, the icon
  compiled into the bundle, the logo is a template, the accent is `#5B53FF`.
