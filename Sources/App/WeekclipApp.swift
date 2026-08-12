import SwiftUI
import WeekclipPresentation

/// Main app entry point
@main
public struct WeekclipApp: App {
  @State private var authViewModel = AuthViewModel()

  public var body: some Scene {
    WindowGroup {
      AppNavigation(authViewModel: authViewModel)
        .task {
          // Restore session on app launch
          await authViewModel.restoreSession()
        }
    }
  }
}
