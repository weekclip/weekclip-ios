// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "Weekclip",
  defaultLocalization: "en",
  platforms: [
    .iOS(.v16)
  ],
  products: [
    .library(name: "WeekclipShared", targets: ["WeekclipShared"]),
    .library(name: "WeekclipDomain", targets: ["WeekclipDomain"]),
    .library(name: "WeekclipData", targets: ["WeekclipData"]),
    .library(name: "WeekclipPresentation", targets: ["WeekclipPresentation"]),
  ],
  dependencies: [
    // Networking
    .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.9.0")),

    // Logging
    .package(url: "https://github.com/apple/swift-log.git", .upToNextMajor(from: "1.5.0")),

    // Testing
    .package(url: "https://github.com/pointfreeco/swift-dependencies.git", .upToNextMajor(from: "1.0.0")),
  ],
  targets: [
    // Shared utilities and models
    .target(
      name: "WeekclipShared",
      dependencies: [
        .product(name: "Logging", package: "swift-log"),
      ],
      path: "Sources/Shared"
    ),

    // Domain logic and use cases
    .target(
      name: "WeekclipDomain",
      dependencies: [
        "WeekclipShared",
      ],
      path: "Sources/Domain"
    ),

    // Data layer (API, repositories)
    .target(
      name: "WeekclipData",
      dependencies: [
        "WeekclipShared",
        "WeekclipDomain",
        .product(name: "Alamofire", package: "Alamofire"),
      ],
      path: "Sources/Data"
    ),

    // Presentation layer (SwiftUI views, ViewModels)
    .target(
      name: "WeekclipPresentation",
      dependencies: [
        "WeekclipShared",
        "WeekclipDomain",
        "WeekclipData",
      ],
      path: "Sources/Presentation"
    ),

    // Tests
    .testTarget(
      name: "WeekclipDataTests",
      dependencies: [
        "WeekclipData",
        .product(name: "Dependencies", package: "swift-dependencies"),
      ],
      path: "Tests/Data"
    ),

    .testTarget(
      name: "WeekclipDomainTests",
      dependencies: [
        "WeekclipDomain",
      ],
      path: "Tests/Domain"
    ),
  ]
)
