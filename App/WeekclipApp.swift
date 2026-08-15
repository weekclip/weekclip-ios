import SwiftUI
import WeekclipPresentation

/// The app target is a thin shell on purpose (ADR-0002 D3): it owns `@main`,
/// `Info.plist`, assets, entitlements and signing, and nothing else. All the
/// code lives in the SwiftPM modules, where it can be compiled and tested
/// without an app bundle.
@main
struct WeekclipApp: App {
  /// Built once, here. This is the only place in the app that constructs a
  /// dependency graph; everything below receives what it needs.
  @State private var container = AppContainer()

  var body: some Scene {
    WindowGroup {
      RootView(container: container)
    }
  }
}
