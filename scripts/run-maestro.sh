#!/usr/bin/env bash
#
# PRD-0008 Phase 4 — drive the installed app and report back.
#
# Why this exists: unit tests never construct the app. `WeekclipRouteTests`
# asserts the route table's shape; it cannot assert that AppContainer built a
# graph, that SwiftUI drew, or that the start destination is on screen. This
# script closes that gap in a form an agent can read: JUnit XML for the verdict,
# plus a screenshot and the failing step's view hierarchy.
#
# Simulator by default, unlike the Android twin. That is not a style difference
# — the Android emulator is unusable on the current dev Mac (SIGSEGV under TCG;
# see weekclip-android/maestro/README.md), while the iOS simulator works fine
# and matches what CI builds against. Pass --device to use attached hardware
# instead; PRD-0008's deep-link and background-upload DoDs will need it.
#
# Usage:
#   scripts/run-maestro.sh [--require-device] [--no-build] [--device] [flow-or-dir ...]
#
#   --require-device  Treat "nothing to run on" as a failure. Any automated
#                     caller MUST pass this. Without it the script skips, and a
#                     check that can only pass is a check that tests nothing —
#                     weekclip-android shipped one of those (`ktlintCheck ||
#                     true`) and it hid a broken build for weeks.
#   --no-build        Run against whatever build is already installed.
#   --device          Target a USB-attached iPhone rather than a simulator.
#   flow-or-dir       Defaults to the whole `maestro/` directory.
#
# Exit: 0 pass (or skipped without --require-device), 1 failure.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_ID="cc.sunglint.weekclip"
SCHEME="Weekclip"
PROJECT="Weekclip.xcodeproj"

require_device=0
build=1
use_hardware=0

# Options first, then flow paths. Flows stay in "$@" rather than an array so
# this works on bash 3.2, where expanding an empty array under `set -u` is an
# error — macOS ships 3.2 and /usr/bin/env finds it.
while [ $# -gt 0 ]; do
  case "$1" in
    --require-device) require_device=1; shift ;;
    --no-build)       build=0; shift ;;
    --device)         use_hardware=1; shift ;;
    -h|--help)        sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)               echo "unknown option: $1" >&2; exit 1 ;;
    *)                break ;;
  esac
done

[ $# -eq 0 ] && set -- maestro

# Maestro is bundled telemetry-on; this repo opts out everywhere it runs.
export MAESTRO_CLI_NO_ANALYTICS=1
export MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true

# --- tools -------------------------------------------------------------------
# A missing tool is a setup error, not a skip: skipping here would silently
# report success on a machine that never ran anything.
MAESTRO="$(command -v maestro || true)"
[ -z "$MAESTRO" ] && [ -x "$HOME/.maestro/bin/maestro" ] && MAESTRO="$HOME/.maestro/bin/maestro"
if [ -z "$MAESTRO" ]; then
  echo "FAIL — maestro CLI not found." >&2
  echo "  curl -fsSL \"https://get.maestro.mobile.dev\" | bash" >&2
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "FAIL — xcodegen not found (brew install xcodegen)." >&2
  echo "  .xcodeproj is generated and gitignored — ADR-0002 D3." >&2
  exit 1
fi

# --- target ------------------------------------------------------------------
if [ "$use_hardware" -eq 1 ]; then
  udid="$(xcrun devicectl list devices 2>/dev/null \
    | awk '/connected/ {print $(NF-1); exit}')"
  if [ -z "$udid" ]; then
    echo
    echo "No iPhone attached over USB."
    echo "  Attach one with Developer Mode on (Settings > Privacy & Security)."
    if [ "$require_device" -eq 1 ]; then
      echo "FAIL — --require-device was passed." >&2
      exit 1
    fi
    echo "SKIP — no device (pass --require-device to make this a failure)."
    exit 0
  fi
  destination="platform=iOS,id=$udid"
  products="Debug-iphoneos"
else
  # Prefer a simulator that is already booted: booting one takes ~20s and the
  # human may have it open with state worth keeping.
  udid="$(xcrun simctl list devices booted --json \
    | python3 -c 'import json,sys
devices = json.load(sys.stdin)["devices"]
for runtime, entries in devices.items():
    if ".iOS-" not in runtime:
        continue
    for device in entries:
        print(device["udid"])
        raise SystemExit
' || true)"

  if [ -z "$udid" ]; then
    udid="$("$ROOT/scripts/pick-simulator.sh" 2>/dev/null || true)"
    if [ -z "$udid" ]; then
      echo
      echo "No iOS simulator runtime is installed."
      echo "  xcodebuild -downloadPlatform iOS   (about 8 GB)"
      if [ "$require_device" -eq 1 ]; then
        echo "FAIL — --require-device was passed." >&2
        exit 1
      fi
      echo "SKIP — no simulator (pass --require-device to make this a failure)."
      exit 0
    fi
    echo "booting simulator $udid"
    xcrun simctl boot "$udid"
  fi

  destination="platform=iOS Simulator,id=$udid"
  products="Debug-iphonesimulator"
fi

name="$(xcrun simctl list devices | grep -m1 "$udid" | sed 's/^ *//' || true)"
echo "target: ${name:-$udid}"

# --- build + install ---------------------------------------------------------
if [ "$build" -eq 1 ]; then
  echo
  echo "== generating project =="
  xcodegen generate

  echo
  echo "== building =="
  xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$destination" \
    -derivedDataPath build \
    -quiet

  app="build/Build/Products/$products/WeekClip.app"
  if [ ! -d "$app" ]; then
    echo "FAIL — built product not found at $app" >&2
    exit 1
  fi

  echo
  echo "== installing =="
  if [ "$use_hardware" -eq 1 ]; then
    xcrun devicectl device install app --device "$udid" "$app"
  else
    xcrun simctl install "$udid" "$app"
  fi
fi

# --- run ---------------------------------------------------------------------
out="build/maestro"
rm -rf "$out"
mkdir -p "$out"

echo
echo "== running flows: $* =="
status=0
"$MAESTRO" --device "$udid" test \
  --format junit \
  --output "$out/report.xml" \
  --test-output-dir "$out/artifacts" \
  "$@" || status=$?

echo
if [ "$status" -ne 0 ]; then
  echo "FAIL — see $out/report.xml for the assertion that broke, and" >&2
  echo "$out/artifacts/ for the screenshot and that step's view hierarchy." >&2
  echo "App log:  xcrun simctl spawn $udid log show --last 2m --predicate 'subsystem == \"$APP_ID\"'" >&2
  exit 1
fi

echo "PASS — $out/report.xml"
