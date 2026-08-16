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
#                     ⚠️ Building + installing works; the maestro *run* does not
#                     yet. Maestro compiles its own XCUITest driver for hardware
#                     and refuses without an Apple team id ("Apple account team
#                     ID must be specified to build drivers for connected
#                     iPhone"), and its CLI exposes no flag for one —
#                     --team-id is absent from `maestro test --help`, and
#                     MAESTRO_APPLE_TEAM_ID / TEAM_ID / APPLE_TEAM_ID were all
#                     tried and ignored (2026-08-16). Until that is found, use
#                     --device to get a build onto the phone and drive it by
#                     hand; the simulator path runs the flows.
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
# A physical iPhone has TWO identifiers and they are not interchangeable:
#
#   identifier  4F337E3E-…  CoreDevice UUID   — what `devicectl` and
#                                               `xcodebuild -destination` take
#   udid        00008150-…  hardware UDID     — what `maestro --device` takes
#
# Read from `--json-output` rather than scraped from the table, because the
# table's columns are not fixed-width and the model name contains spaces.
# 🔴 The previous version did `awk '/connected/ {print $(NF-1)}'`, which on
# "iPhone Air (iPhone18,4)" yields the literal string **"Air"** — and maestro
# then matched a *simulator* named "iPhone Air" and ran the whole suite there,
# reporting a pass for a device that was never touched. Measured 2026-08-16;
# this path had evidently never been run.
install_id=""
maestro_id=""

if [ "$use_hardware" -eq 1 ]; then
  ids="$(
    tmp="$(mktemp)"
    xcrun devicectl list devices --json-output "$tmp" >/dev/null 2>&1 || true
    python3 - "$tmp" <<'PY' || true
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    raise SystemExit
for device in devices:
    if device["connectionProperties"]["tunnelState"] == "connected":
        print(device["identifier"], device["hardwareProperties"]["udid"])
        break
PY
    rm -f "$tmp"
  )"
  if [ -z "$ids" ]; then
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
  install_id="${ids%% *}"
  maestro_id="${ids##* }"
  udid="$install_id"
  destination="platform=iOS,id=$install_id"
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

  # A simulator has only the one id, and both tools take it.
  install_id="$udid"
  maestro_id="$udid"
  destination="platform=iOS Simulator,id=$udid"
  products="Debug-iphonesimulator"
fi

if [ "$use_hardware" -eq 1 ]; then
  # Name it from devicectl, not simctl — grepping simctl for a hardware id
  # finds nothing, and the fallback would print a bare UUID for the one case
  # where knowing which phone this is matters most.
  name="$(xcrun devicectl list devices 2>/dev/null | awk -v id="$install_id" '$0 ~ id {print $1; exit}')"
  echo "target: ${name:-iPhone} (hardware $maestro_id)"
else
  name="$(xcrun simctl list devices | grep -m1 "$udid" | sed 's/^ *//' || true)"
  echo "target: ${name:-$udid}"
fi

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

# 🔴 `launchApp: clearState: true` does NOT sign the user out on iOS.
# It resets the app *container* — UserDefaults, Documents — and the session
# lives in the **Keychain**, which is per-device and survives. Measured
# 2026-08-16: the smoke flow's gate assertion passed once (on a simulator that
# had just had the app installed for the first time, so the Keychain was empty)
# and failed on the very next run against the same simulator.
#
# That is the worse of the two failure shapes. A check that cannot fail gets
# trusted; a check that passes once and then fails gets deleted. Resetting here
# is what makes "the first screen is the gate" mean something on every run.
#
# Simulator only, and it wipes that simulator's whole keychain — acceptable for
# a throwaway test device, not something to do to a phone. The hardware path
# therefore cannot assert the signed-out state; see the --device note above.
if [ "$use_hardware" -eq 0 ]; then
  echo
  echo "== resetting the simulator keychain (clearState does not) =="
  xcrun simctl keychain "$udid" reset
fi

echo
echo "== running flows: $* =="
status=0
# maestro_id, not install_id — see the note where they are read. On a
# simulator they are the same string; on hardware they are not, and passing the
# CoreDevice UUID here makes maestro fall back to *some other* device.
"$MAESTRO" --device "$maestro_id" test \
  --format junit \
  --output "$out/report.xml" \
  --test-output-dir "$out/artifacts" \
  "$@" || status=$?

echo
if [ "$status" -ne 0 ]; then
  echo "FAIL — see $out/report.xml for the assertion that broke, and" >&2
  echo "$out/artifacts/ for the screenshot and that step's view hierarchy." >&2
  # simctl reaches a simulator and nothing else; on hardware the log lives on
  # the phone. Printing the simulator command for a hardware run would send the
  # reader to an empty log and let them conclude the app never ran.
  if [ "$use_hardware" -eq 1 ]; then
    echo "App log:  xcrun devicectl device console --device $install_id" >&2
  else
    echo "App log:  xcrun simctl spawn $udid log show --last 2m --predicate 'subsystem == \"$APP_ID\"'" >&2
  fi
  exit 1
fi

echo "PASS — $out/report.xml"
