import SwiftUI

/// Legacy content view - replaced by AppNavigation
public struct ContentView: View {
  public init() {}

  public var body: some View {
    AppNavigation(authViewModel: AuthViewModel())
  }
}

#Preview {
  ContentView()
}
