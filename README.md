# WeekClip iOS

Modern iOS native app for WeekClip with SwiftUI and MVVM architecture.

## Architecture

### Modern Stack (2024-2026)
- **UI Framework**: SwiftUI (declarative UI)
- **Architecture Pattern**: MVVM + Clean Architecture (3-layer)
- **State Management**: @Observable (iOS 17+) + Swift async/await
- **Networking**: Alamofire + URLSession
- **Async Concurrency**: Swift 6 structured concurrency
- **Background Tasks**: URLSession background upload + BGTaskScheduler
- **Package Management**: Swift Package Manager (SPM)

### Project Structure
```
App/                    # iOS app shell (@main, Info.plist, assets) — the only
                        # part that ships as an app target
project.yml             # XcodeGen spec -> generates Weekclip.xcodeproj
Package.swift           # SwiftPM package supplying the 4 library modules

Sources/
├── Shared/              # Common utilities, error types, logging
├── Domain/              # Use cases, business logic
├── Data/               # API client, repositories, network layer
└── Presentation/       # SwiftUI views, ViewModels

Tests/
├── Domain/
└── Data/
```

`Weekclip.xcodeproj` is **generated and gitignored**. Never edit it by hand —
change `project.yml` and regenerate.

## Setup

### Prerequisites
- **Xcode 26+** (required: macOS 26 ships frameworks that Xcode 16.x cannot load,
  and an iOS 26 device needs the matching SDK)
- iOS 17.0+ deployment target (`@Observable` requires 17)
- Swift 5.9+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Generating the project
```bash
export DEVELOPMENT_TEAM=XXXXXXXXXX   # optional; otherwise pick the team in Xcode
xcodegen generate
```

### Building
```bash
swift build          # library modules only
swift test
```

### Running on a device
```bash
xcodegen generate
open Weekclip.xcodeproj
```
Then in Xcode: select the **Weekclip** scheme, pick your connected iPhone,
set a team under *Signing & Capabilities*, and Run. On first launch the device
will refuse the app until you trust the developer profile under
*Settings > General > VPN & Device Management*.

Command-line equivalent:
```bash
xcodebuild -project Weekclip.xcodeproj -scheme Weekclip \
  -destination 'platform=iOS,name=<YOUR IPHONE>' build
```

## Development

### Code Style
- Swift with consistent formatting
- Modern Swift 6 concurrency patterns
- Value types (structs) preferred over reference types
- @Observable for state management (replacing Combine boilerplate)

### Testing
- Unit tests with XCTest
- Integration tests with mock API client
- Swift async/await for test code

## Key Features

### Current
- [x] Modern SwiftUI framework
- [x] Modular architecture with SPM
- [x] API client with Alamofire
- [x] MVVM state management

### Planned
- [ ] Video playback with native player
- [ ] Background upload with URLSession
- [ ] Scheduled WiFi upload with BGTaskScheduler
- [ ] Photo gallery integration
- [ ] User authentication with OAuth

## Background Task Architecture

### URLSession Background Upload
- Non-resumable uploads use standard URLSession
- Resumable uploads use background URLSessionConfiguration
- Automatic retry on network changes

### BGTaskScheduler Integration
- Process info background tasks for scheduled uploads
- WiFi-only constraint for off-peak uploads
- Battery optimization aware

## References
- [SwiftUI Documentation](https://developer.apple.com/swiftui/)
- [URLSession Background Transfer Guide](https://developer.apple.com/documentation/foundation/urlsession/downloading_files_in_the_background)
- [BGTaskScheduler](https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler)
- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency)
- [Swift Package Manager](https://www.swift.org/package-manager/)
