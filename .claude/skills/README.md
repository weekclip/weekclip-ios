# Vendored Claude Code skills

The skill directories here are **not written by this project**. They are
vendored verbatim from [dpearson2699/swift-ios-skills][upstream].

- Upstream commit: `8d90fd121a263355a4fb44fd082af1416a5c1c2a` (2026-07-31)
- Scope: the **SwiftUI** section of the upstream README only — 10 of the 86
  skills that repo ships. The other sections were deliberately not installed.
- Each skill keeps its upstream `SKILL.md` and `references/`. The upstream
  `evals/` fixtures are omitted; they test the skills, and are not used when a
  skill is applied.

Installed:

| Skill | Covers |
|---|---|
| `focus-engine` | Focus state and the focus engine |
| `swiftui-animation` | Animation and transitions |
| `swiftui-gestures` | Gesture recognisers and composition |
| `swiftui-layout-components` | Layout containers and custom `Layout` |
| `swiftui-liquid-glass` | Liquid Glass material |
| `swiftui-navigation` | `NavigationStack`, sheets, tabs, deep links |
| `swiftui-patterns` | State management and view composition |
| `swiftui-performance` | Rendering and diffing performance |
| `swiftui-uikit-interop` | `UIViewRepresentable` and friends |
| `swiftui-webkit` | `WebView` / WebKit integration |

## Licence

PolyForm Perimeter 1.0.0 — see [`LICENSE`](./LICENSE). This is **not** an
open-source licence. The required notice is:

> Copyright (c) 2025 dpearson2699 (https://github.com/dpearson2699)

The perimeter clause forbids using the software to compete with the licensor.
Using these skills to build WeekClip is fine; redistributing them as part of a
competing skills product is not.

## Updating

Re-vendor from upstream rather than editing in place — local edits will be lost
and make the provenance above a lie:

```bash
git clone --depth 1 https://github.com/dpearson2699/swift-ios-skills.git /tmp/sis
for s in .claude/skills/*/; do
  s=$(basename "$s")
  [ -d "/tmp/sis/skills/$s" ] && rsync -a --delete --exclude evals "/tmp/sis/skills/$s" .claude/skills/
done
```

[upstream]: https://github.com/dpearson2699/swift-ios-skills
