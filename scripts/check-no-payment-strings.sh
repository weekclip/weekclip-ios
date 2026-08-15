#!/usr/bin/env bash
#
# PRD-0008 D3 / N6 — the app binary must contain ZERO payment-related strings.
#
# Why a gate and not a note: D3 is the whole reason the app can exist without
# in-app purchase. Apple Guideline 3.1.1 judges what the binary says, so the
# rule has to be checked mechanically, not remembered. A capacity shortfall is
# reported as a plain fact ("Not enough capacity") — no price, no top-up path,
# no "buy it on the web".
#
# This matters more here than on Android. Android's store review does not turn
# on 3.1.1, and the copy this gate exists to stop was living in THIS repo:
# `AppError.insufficientCapacity` used to carry the recovery suggestion
# "Please upgrade your plan or delete some content". Nobody put it there
# maliciously; it read as helpful. That is exactly why the check is a script and
# not a habit.
#
# What this checks:
#   1. Swift string literals under Sources/ and App/, with comments stripped
#   2. Info.plist and any .strings / .stringsdict catalogues
#
# Tests/ is out of scope, and that is a scoping decision rather than an
# oversight: the rule is about what the *app binary* says, and a unit-test
# bundle is not shipped. It is also load-bearing — `WeekclipRouteTests` asserts
# that "/pricing" resolves to nil, i.e. that the app deliberately does NOT own
# the web's pricing page. Scanning tests would flag the proof that the rule
# holds.
#
# The comment-stripping matters: this repo's source deliberately *discusses*
# billing in comments (explaining why it is absent). Those must not trip the
# gate, and the compiler drops them anyway.
#
# What this does NOT check: third-party library internals — there are none
# (Package.swift declares no dependencies, ADR-0002 D4). If one is ever added,
# that is a review-time decision, not a grep.
#
# Usage:  scripts/check-no-payment-strings.sh [repo-root]
# Exit:   0 clean, 1 forbidden strings found

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# Words that would signal a purchase path to a store reviewer. Deliberately
# narrow: "capacity" and "storage" are fine — the app must be able to say the
# user is out of room. What it must never do is name a way to pay.
#
# `upgrade.{0,20}plan` and `\bplans?\b` were added on 2026-08-15 after this
# gate was tested against the sentence that was actually living in
# weekclip-ios (`AppError.insufficientCapacity`'s recovery suggestion):
#
#     "Please upgrade your plan or delete some content"
#
# The old pattern had `upgrade[ _-]?plan`, which does not match "upgrade YOUR
# plan", and nothing else in the list matched either — so both gates passed a
# real Guideline 3.1.1 string. A gate is only worth what you have watched it
# reject.
FORBIDDEN='checkout|polar|purchase|subscription|subscribe|top[ _-]?up|billing|payment|credit[ _-]?card|paywall|upgrade.{0,20}plan|\bplans?\b|refund|invoice|price|pricing|\$[0-9]'

fail=0

echo "== 1/2  Swift string literals in Sources/ + App/ (comments stripped) =="
swift_hits=""
while IFS= read -r f; do
  # Strip /* */ blocks, then // line comments and /// doc comments, then keep
  # only double-quoted literals. perl -0777 slurps the file so multi-line block
  # comments go too.
  literals=$(perl -0777 -pe 's{/\*.*?\*/}{}gs' "$f" \
    | sed 's://.*::' \
    | grep -oE '"[^"]*"' || true)
  if [ -n "$literals" ]; then
    if match=$(printf '%s\n' "$literals" | grep -niE "$FORBIDDEN" || true); then
      if [ -n "$match" ]; then
        swift_hits="${swift_hits}${f}: ${match}"$'\n'
      fi
    fi
  fi
done < <(find Sources App -name '*.swift' 2>/dev/null)

if [ -n "$swift_hits" ]; then
  printf '%s' "$swift_hits" | sed 's/^/   FORBIDDEN: /'
  fail=1
else
  echo "   clean"
fi

echo "== 2/2  plists and string catalogues (XML comments stripped) =="
plist_files=$(find App Sources -name '*.plist' -o -name '*.strings' -o -name '*.stringsdict' 2>/dev/null || true)
if [ -z "$plist_files" ]; then
  echo "   (none found)"
else
  plist_hits=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # XML comments are dropped by the plist compiler exactly as kotlinc drops
    # Kotlin ones, so scanning them would flag documentation for a rule the
    # documentation exists to explain.
    stripped=$(perl -0777 -pe 's{<!--.*?-->}{}gs' "$f")
    if match=$(printf '%s\n' "$stripped" | grep -niE "$FORBIDDEN" || true); then
      if [ -n "$match" ]; then
        plist_hits="${plist_hits}${f}: ${match}"$'\n'
      fi
    fi
  done < <(printf '%s\n' "$plist_files")

  if [ -n "$plist_hits" ]; then
    printf '%s' "$plist_hits" | sed 's/^/   FORBIDDEN: /'
    fail=1
  else
    echo "   clean"
  fi
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "FAIL — payment-related strings found. PRD-0008 D3 requires zero." >&2
  echo "If a match is a false positive, narrow the pattern in this script and" >&2
  echo "say why in the commit message. Do not add a blanket skip." >&2
  exit 1
fi

echo "PASS — no payment-related strings (PRD-0008 D3)."
