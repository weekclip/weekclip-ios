// swift-tools-version: 6.0
import PackageDescription

// The four library modules the app target links. The app bundle itself is an
// Xcode target (App/, generated from project.yml) — SwiftPM cannot produce an
// iOS app bundle, which is ADR-0002 D3.
//
// iOS only. The previous manifest also declared .macOS(.v14), purely so that
// `swift build` on a CI macOS host would compile; that host build never
// produced anything shippable and was the reason CI looked busy while the app
// was untestable. Everything now goes through xcodebuild against a simulator,
// so the macOS platform line has no reader.
let package = Package(
  name: "Weekclip",
  defaultLocalization: "en",
  platforms: [
    // v17 because @Observable is iOS 17+. Matches Android's minSdk 28 in
    // spirit: old enough to include real devices, new enough to skip a
    // compatibility layer nobody asked for.
    .iOS(.v17)
  ],
  products: [
    .library(name: "WeekclipShared", targets: ["WeekclipShared"]),
    .library(name: "WeekclipDomain", targets: ["WeekclipDomain"]),
    .library(name: "WeekclipData", targets: ["WeekclipData"]),
    .library(name: "WeekclipPresentation", targets: ["WeekclipPresentation"]),
  ],
  // No external dependencies, deliberately.
  //
  //  · Alamofire — rejected by ADR-0002 D4. PRD-0008 D8 needs background
  //    URLSession under direct control, and wrapping the one path that matters
  //    most would make it two layers deep for no gain.
  //  · swift-log  — os.Logger is on every supported OS, integrates with
  //    Console.app and sysdiagnose, and costs nothing to link.
  //  · swift-dependencies — the composition root in
  //    Presentation/Composition does manual DI in ~40 lines (ADR-0002's
  //    "수동 DI"). A DI framework for one graph this size is not a trade.
  dependencies: [],
  targets: [
    .target(name: "WeekclipShared", path: "Sources/Shared"),
    .target(name: "WeekclipDomain", dependencies: ["WeekclipShared"], path: "Sources/Domain"),
    .target(
      name: "WeekclipData",
      dependencies: ["WeekclipShared", "WeekclipDomain"],
      path: "Sources/Data"
    ),
    .target(
      name: "WeekclipPresentation",
      dependencies: ["WeekclipShared", "WeekclipDomain", "WeekclipData"],
      path: "Sources/Presentation"
    ),
  ],
  swiftLanguageModes: [.v6]
)
