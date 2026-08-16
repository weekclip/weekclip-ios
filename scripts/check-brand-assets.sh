#!/usr/bin/env bash
#
# Brand assets — the checks that read the checked-in files, not the built app.
#
# `Tests/WeekclipTests/BrandAssetsTests.swift` asserts what only a running app
# can see: that every PostScript name resolves, that the icon compiled into the
# bundle, that the logo is a tintable template, that AccentColor is #5B53FF.
# This script covers the rest — the shape of the source tree, and the one
# property of the icon file that the app cannot observe about itself.
#
# Why a script as well as a test: this runs before the toolchain, in seconds,
# and it fails on things that would otherwise fail twenty minutes later inside
# `xcodebuild` — or not at all. An alpha channel in the app icon is the clearest
# case: it builds, it installs, it runs, and App Store Connect rejects the
# upload.
#
# What this checks:
#   1. UIAppFonts and App/Resources/Fonts/ agree in both directions
#   2. Every PostScript name in WeekclipFont.swift has a file to resolve to
#   3. The SIL OFL licences are in the tree
#   4. The 1024 app icon is 1024x1024, RGB, and carries NO alpha channel
#   5. AccentColor.colorset actually holds a colour
#
# Usage:  scripts/check-brand-assets.sh [repo-root]
# Exit:   0 clean, 1 a check failed

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

FONT_DIR="App/Resources/Fonts"
LICENSE_DIR="App/Resources/Licenses"
INFO_PLIST="App/Info.plist"
ICON="App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
ACCENT="App/Assets.xcassets/AccentColor.colorset/Contents.json"

fail=0

echo "== 1/5  UIAppFonts <-> App/Resources/Fonts =="
# PlistBuddy rather than grep: the plist is XML today, and a grep would keep
# "passing" if it were ever converted to binary.
declared=$(/usr/libexec/PlistBuddy -c "Print :UIAppFonts" "$INFO_PLIST" 2>/dev/null \
  | sed -n 's/^ *\([A-Za-z].*\.ttf\)$/\1/p' | sort || true)
bundled=$(ls "$FONT_DIR"/*.ttf 2>/dev/null | xargs -n1 basename | sort || true)

if [ -z "$declared" ]; then
  echo "   FAIL: UIAppFonts is missing or empty in $INFO_PLIST" >&2
  echo "         A font in the bundle but not in UIAppFonts is never registered;" >&2
  echo "         Font.custom returns the system face and nothing reports an error." >&2
  fail=1
elif [ "$declared" != "$bundled" ]; then
  echo "   FAIL: UIAppFonts and $FONT_DIR disagree" >&2
  diff <(printf '%s\n' "$declared") <(printf '%s\n' "$bundled") \
    | sed 's/^/      /' >&2 || true
  fail=1
else
  echo "   clean ($(printf '%s\n' "$declared" | wc -l | tr -d ' ') faces)"
fi

echo "== 2/5  PostScript names in WeekclipFont.swift resolve to files =="
# The enum's raw values are PostScript names, and these files are named after
# their PostScript name. That is a convention, not a guarantee — which is why
# BrandAssetsTests asserts the real thing (UIFont(name:) round-trips) against
# the built app. This check is the cheap early half.
names=$(grep -oE '= "(Inter|SpaceGrotesk)-[A-Za-z]+"' \
  Sources/Presentation/Theme/WeekclipFont.swift | tr -d '="' | sed 's/^ *//' | sort -u)
if [ -z "$names" ]; then
  echo "   FAIL: no PostScript names found — did WeekclipFontName move?" >&2
  fail=1
else
  missing=0
  for n in $names; do
    if [ ! -f "$FONT_DIR/$n.ttf" ]; then
      echo "   FAIL: WeekclipFontName names $n but $FONT_DIR/$n.ttf is missing" >&2
      missing=1
    fi
  done
  [ "$missing" -eq 0 ] && echo "   clean ($(printf '%s\n' "$names" | wc -l | tr -d ' ') names)" || fail=1
fi

echo "== 3/5  SIL OFL licences =="
# OFL 1.1 clause 2: the licence travels with the font.
missing_license=0
for entry in "Inter-:Inter-OFL.txt" "SpaceGrotesk-:SpaceGrotesk-OFL.txt"; do
  prefix="${entry%%:*}"
  license="${entry##*:}"
  ls "$FONT_DIR"/"$prefix"*.ttf >/dev/null 2>&1 || continue
  if [ ! -s "$LICENSE_DIR/$license" ]; then
    echo "   FAIL: $FONT_DIR/$prefix* is bundled but $LICENSE_DIR/$license is missing" >&2
    missing_license=1
  fi
done
if [ "$missing_license" -ne 0 ]; then fail=1; else echo "   clean"; fi

echo "== 4/5  app icon: 1024x1024, RGB, no alpha =="
if [ ! -f "$ICON" ]; then
  echo "   FAIL: $ICON is missing" >&2
  fail=1
else
  # Anchored to "  <key>: <value>", because sips echoes the file path first and
  # an unanchored /space/ also matches any checkout living under a directory
  # called "workspace" — which produced an empty first value and a comparison
  # against a two-line string. Measured, not imagined.
  props=$(sips -g pixelWidth -g pixelHeight -g hasAlpha -g space "$ICON" 2>/dev/null)
  prop() { printf '%s\n' "$props" | awk -v k="$1" '$1 == k":" {print $2}'; }
  w=$(prop pixelWidth)
  h=$(prop pixelHeight)
  a=$(prop hasAlpha)
  s=$(prop space)

  icon_ok=1
  [ "$w" = "1024" ] && [ "$h" = "1024" ] || { echo "   FAIL: icon is ${w}x${h}, expected 1024x1024" >&2; icon_ok=0; }
  # App Store Connect rejects a marketing icon with an alpha channel. It builds,
  # installs and runs fine — the rejection arrives at upload, which is the worst
  # moment to discover it.
  [ "$a" = "no" ] || { echo "   FAIL: icon has an alpha channel; App Store Connect rejects that" >&2; icon_ok=0; }
  [ "$s" = "RGB" ] || { echo "   FAIL: icon colour space is $s, expected RGB" >&2; icon_ok=0; }
  [ "$icon_ok" -eq 1 ] && echo "   clean (${w}x${h}, $s, alpha: $a)" || fail=1
fi

echo "== 5/5  AccentColor holds a colour =="
# An empty colorset is what shipped until 2026-08-16: valid JSON, valid catalog,
# and `Color.accentColor` silently falls back to the system blue.
if grep -q '"color-space"' "$ACCENT" && grep -q '"components"' "$ACCENT"; then
  echo "   clean"
else
  echo "   FAIL: $ACCENT declares an idiom but no colour components" >&2
  fail=1
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — brand assets are not wired up correctly." >&2
  exit 1
fi

echo "PASS — fonts registered, licensed, icon uploadable, accent set."
