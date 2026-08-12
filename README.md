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
Sources/
├── Shared/              # Common utilities, error types, logging
├── Domain/              # Use cases, business logic
├── Data/               # API client, repositories, network layer
└── Presentation/       # SwiftUI views, ViewModels

Tests/
├── Domain/
└── Data/
```

## Setup

### Prerequisites
- Xcode 15.0+
- iOS 16.0+ deployment target
- Swift 5.9+
- macOS 12+

### Building
```bash
swift build
swift test
```

### Running
```bash
# Open in Xcode
open Weekclip.xcworkspace

# Or build from command line
swift build -c release
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
