#!/usr/bin/env bash
#
# Prints the UDID of an available iPhone simulator on the newest iOS runtime.
#
# Why not hardcode a name: "iPhone 17" exists on this Mac and may not exist on a
# GitHub runner image, and the reverse will be true in six months. Pinning a
# model name means CI breaks on an image bump for a reason that has nothing to
# do with the app.
#
# Exits 1 with a message if there is none. That is deliberate — a missing
# simulator must not degrade into "build only", because a suite that quietly
# stops running looks exactly like a suite that passes.
#
# Usage:  scripts/pick-simulator.sh
# Output: a UDID on stdout, nothing else (so it can be captured directly)

set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json
import sys

devices = json.load(sys.stdin)["devices"]

# Runtime keys look like com.apple.CoreSimulator.SimRuntime.iOS-26-5.
# Sorting the numeric components descending picks the newest without parsing
# a version string format that Apple has changed before.
def version(key):
    tail = key.rsplit(".", 1)[-1]
    parts = tail.split("-")[1:]
    return [int(p) if p.isdigit() else 0 for p in parts]

runtimes = sorted(
    (k for k in devices if ".iOS-" in k),
    key=version,
    reverse=True,
)

for runtime in runtimes:
    for device in devices[runtime]:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            print(device["udid"])
            sys.exit(0)

sys.exit("no available iPhone simulator — run: xcodebuild -downloadPlatform iOS")
'
