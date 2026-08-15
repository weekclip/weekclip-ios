# weekclip-ios

Native iOS client for weekclip.

- **PRD**: `weekclip-harness/wiki/prd/PRD-0008-native-app-port.md`
- **Stack decisions**: `weekclip-harness/wiki/adr/ADR-0002-native-app-stack.md`
- **Port scope**: `docs/product/native-app-feature-inventory.md` (superrepo)

## Stack

Every choice below has a recorded reason in ADR-0002. Where a decision looks
unusual, the reason is in the third column — not in someone's memory.

| Area | Choice | Why |
|------|--------|-----|
| UI | SwiftUI | Default for new apps |
| State | `@Observable` | SwiftUI tracks the properties a view actually reads; `ObservableObject` invalidates every observer on any change |
| Concurrency | Swift 6 language mode | Strict concurrency, on both the package and the app target |
| Navigation | `NavigationStack` + typed path | A deep link becomes "append a `WeekclipRoute`" |
| DI | **Manual** (composition root) | The whole graph is ~40 lines in `AppContainer`. ADR-0002 |
| Networking | **`URLSession`, no wrapper** | PRD-0008 D8 needs background `URLSession` under direct control; a wrapper would leave the most important path bypassing it. ADR-0002 D4 |
| Playback | AVPlayer / AVKit | HLS is native, no dependency needed |
| Background upload | background `URLSession` (file-based) | Phase 5. iOS cannot stream a background body — every multipart part needs a temp file |
| Secure storage | Keychain | — |
| Project definition | **XcodeGen**, `.xcodeproj` gitignored | The definition stays reviewable text and CI regenerates it. ADR-0002 D3 |
| Identifier | `cc.sunglint.weekclip` | Same on both platforms. ADR-0002 D7 |

**No external dependencies.** `Package.swift` declares none. Alamofire was
removed (D4), swift-log was replaced by `os.Logger`, and swift-dependencies was
replaced by the composition root.

**No payment code, ever.** PRD-0008 D3 requires zero payment-related strings in
the app binary; `scripts/check-no-payment-strings.sh` gates it in CI (N6).
Capacity shortfall is reported as a plain fact — no price, no top-up path, no
"buy on the web". This is the platform the rule exists for: Apple Guideline
3.1.1 judges what the binary says.

## Requirements

- **Xcode 26+**. App Store Connect has required the iOS 26 SDK since 2026-04-28,
  and CI runners are on 26 — building locally against an older SDK would be a
  drift you find at upload time.
- An **iOS simulator runtime**: `xcodebuild -downloadPlatform iOS` (~8 GB).
  Xcode 26 does not install one by default, and without it there is nothing to
  run tests on.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- `swift-format` needs no install — it ships inside the Xcode toolchain.

## Build

`.xcodeproj` is generated and gitignored. Never edit it by hand; change
`project.yml` and regenerate.

```bash
xcodegen generate

# Build and test on a simulator. scripts/pick-simulator.sh chooses one that
# actually exists rather than hardcoding a model name.
UDID=$(./scripts/pick-simulator.sh)
xcodebuild build -project Weekclip.xcodeproj -scheme Weekclip \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build
xcodebuild test  -project Weekclip.xcodeproj -scheme Weekclip \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build

xcrun swift-format lint --strict --recursive \
  --configuration .swift-format Sources Tests App
```

> There is no `swift build`. It compiles the library modules for the **macOS
> host**, which never touches the app bundle — that host build is why this
> repo's CI looked busy for weeks while the app was untestable. Everything goes
> through `xcodebuild` against a simulator.

### Running on a device

```bash
open Weekclip.xcodeproj    # pick your iPhone, Run
```

Command-line equivalent:

```bash
DEVICE=$(xcrun devicectl list devices | awk '/connected/ {print $(NF-1); exit}')
xcodebuild -project Weekclip.xcodeproj -scheme Weekclip \
  -destination "platform=iOS,id=$DEVICE" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device "$DEVICE" \
  build/Build/Products/Debug-iphoneos/WeekClip.app
xcrun devicectl device process launch --device "$DEVICE" \
  --terminate-existing cc.sunglint.weekclip
```

`-allowProvisioningDeviceRegistration` is needed in addition to
`-allowProvisioningUpdates` the first time a given device is used; without it
the build fails with "Device isn't registered in your developer account".

| Symptom | Cause / fix |
|---|---|
| Everything Xcode-related aborts with `Symbol not found: _XPCTypeBool` | A stale `/Library/Developer/PrivateFrameworks/CoreDevice.framework` from an older Xcode. `sudo xcodebuild -runFirstLaunch` |
| `Developer Mode disabled` | On the phone: Settings > Privacy & Security > Developer Mode > on, then reboot |
| `CodeSign ... errSecInternalComponent` | codesign cannot reach the private key. Build once from the Xcode GUI and choose *Always Allow*, or `security set-key-partition-list -S apple-tool:,apple:,codesign: -s ~/Library/Keychains/login.keychain-db` |

## Running against dev

Everything above builds with no configuration. Reaching the dev tier with a real
session needs three build settings, all empty by default so CI and a clean
checkout are unaffected. Values come from the superrepo's encrypted ledger —
they are not committed here:

```bash
V=../scripts/secrets/vault.sh
xcodebuild build -project Weekclip.xcodeproj -scheme Weekclip \
  -destination "platform=iOS Simulator,id=$(./scripts/pick-simulator.sh)" \
  -derivedDataPath build \
  WEEKCLIP_SUPABASE_ANON_KEY="$($V get dev SUPABASE_ANON_KEY)" \
  WEEKCLIP_DEBUG_SIGN_IN_EMAIL="adam@weekclip.com" \
  WEEKCLIP_DEBUG_SIGN_IN_PASSWORD="$($V get dev CAPTURE_BOT_PASSWORD)"
```

`Info.plist` expands them; `AuthConfig` and `DebugAutoSignIn` read them from
there. With them set, a debug build signs in **once** on first launch and
restores the stored session on every launch after:

```bash
xcrun simctl spawn <udid> log show --info --style compact --start "<time>" \
  --predicate 'subsystem == "cc.sunglint.weekclip" AND category == "session"'
```

tells you which happened — `signed in` vs `restored a stored session … no
network needed` — and that difference is the point of the feature. Without them
the app behaves like a release build: no session, `AppError.unauthorized`, error
screen.

> ⚠️ **The dev API is behind a WAF that allows exactly one address** — the
> WireGuard egress `158.247.237.200` (superrepo
> `docs/ops/security-topology-161.md` §3). Off the VPN, `*.weekclip.dev` answers
> **403 with a Cloudflare HTML page**, which the app maps to
> `AppError.unauthorized` and renders as "Your session has ended" — a session
> error for a network problem. If sign-in succeeds but every API call fails,
> check the VPN before you debug the session code. Supabase itself is *not*
> behind that WAF, which is why sign-in can succeed while everything after it
> fails.

## UI verification (Maestro)

Unit tests never construct the app, so nothing else here can tell you it
launches. `maestro/` drives the installed app and reports back machine-readably.

```bash
./scripts/run-maestro.sh                    # simulator (boots one if needed)
./scripts/run-maestro.sh --device           # USB-attached iPhone
./scripts/run-maestro.sh --require-device   # never skip — for any automated caller
```

Needs the [Maestro](https://maestro.dev) CLI:
`curl -fsSL "https://get.maestro.mobile.dev" | bash`. Results land in
`build/maestro/`: JUnit XML, plus a screenshot and view hierarchy for each
failing step.

Simulator-first, unlike the Android twin — there the emulator is unusable on the
dev Mac (see `weekclip-android/maestro/README.md`), here it works and matches
what CI builds. `--device` exists because PRD-0008's deep-link and
background-upload DoDs will need real hardware.

**For agents:** `.mcp.json` registers Maestro's MCP server (it ships inside the
CLI), exposing `inspect_screen`, `take_screenshot` and `run` — enough to look at
the screen, act on it, and check the result without writing a flow file first.

CI runs `maestro check-syntax` on every flow. It cannot run the flows
themselves — that needs a booted simulator with the app installed.

## Layout

Four modules, dependencies pointing inward: `Presentation` → `Domain` ← `Data`.
The views never name a `URLSession` or decoding type; `Domain` imports only
`WeekclipShared`.

```
App/                          # the app target — @main, Info.plist, assets,
                              # signing. Nothing else (ADR-0002 D3)
project.yml                   # XcodeGen spec -> Weekclip.xcodeproj
Package.swift                 # the four library modules

Sources/
├── Shared/                   # AppError (the closed failure set), AppLog
├── Domain/                   # models, repository protocols, use cases
├── Data/
│   ├── API/                  # APIClient (URLSession), endpoints, envelope,
│   │                         # session axis + credential provider
│   ├── Session/              # the session itself: Keychain store, refresh
│   │                         # with single-flight, SessionManager
│   ├── DTO/                  # wire shapes + mapping to domain
│   └── Repository/           # implementations of the domain protocols
└── Presentation/
    ├── Navigation/           # WeekclipRoute — the deep-link contract
    ├── Composition/          # AppContainer, the only place the graph is built
    ├── Dashboard/            # the reference screen
    └── RootView.swift        # NavigationStack + onOpenURL

Tests/WeekclipTests/          # an Xcode test target, not a SwiftPM one, so
                              # tests run on the simulator rather than the host
```

### The route table is a contract

`Presentation/Navigation/WeekclipRoute.swift` mirrors weekclip-web's URLs
one-for-one, and `WeekclipRoutes.kt` in weekclip-android mirrors the same ones.
That is load-bearing: PRD-0008 D4 routes `/studios/:id/media/:mid`,
`/invite/:token` and `/share/:token` into the app via Universal Links. If the
three drift apart, deep links stop resolving — silently, on other people's
phones.

`WeekclipRouteTests` writes the expected paths out as literals rather than
deriving them, because a test derived from the type under test agrees with any
change, including a wrong one. It also asserts that `/pricing` resolves to
**nil**: paths the app does not own must go to the browser, not be guessed at.

### Errors are a closed set

`AppError` is what the UI is allowed to see; `APIClient` is the only place
transport failures become one. The `switch` in `DashboardView` is therefore
exhaustive, and adding a case breaks the build at every screen that has to
decide what to say about it.

`AppError` carries no user-facing copy. The previous version did, and one of
those strings — "Please upgrade your plan or delete some content" — is precisely
what Guideline 3.1.1 rejects.

### The dashboard is the reference screen

`Presentation/Dashboard/` is the shape every Phase 5 screen should copy, and the
vertical slice that proves the spine is connected: it runs a real `GET /studios`
against the contract in weekclip-api. `StudioRepositoryContractTests` pins that
contract with a `URLProtocol` stub — real response bytes through the real
request pipeline, because a stub of the repository would skip the envelope,
which is the part most likely to be wrong.

## Status

Spine, not features. The dashboard is real and reaches the live API; every other
destination is still a placeholder. Feature work is Phase 5 of PRD-0008.

Not built yet, on purpose:

| Missing | Why it is not here |
|---|---|
| Local cache | PRD-0008 states no offline requirement. A schema with no read path is a migration liability from day one; `StudioRepository` is the seam that makes one addable |
| Sign-in (Google OAuth) | Task 148.5c-b, and it is **blocked on console work** — an iOS OAuth client and a redirect URL registered with Supabase. Google is the product's only login (weekclip-web `LoginPage.tsx`). Until then a **debug-only** password sign-in stands in; see "Running against dev" |
| Guest / share session storage | PRD-0008 D5 needs one, but nothing writes it yet: a share session is minted by entering a link's password on a screen that does not exist (task 148.7). The **axis** is real and tested — `SessionAxis` routes `/api/v1/share/*` away from the profile bearer, so the store plugs in behind `SessionCredentialProvider` without `APIClient` or a repository changing |
| Universal Links entitlement | Task 148.5, and it needs `apple-app-site-association` served from `weekclip.com` first. `WeekclipRoute(url:)` is the half that lives here, and it is tested |
| TestFlight upload | Task 148.4c. Needs signing secrets in the value ledger (`secrets/*.enc.yaml`), not in a console |
