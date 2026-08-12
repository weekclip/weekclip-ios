import SwiftUI

/// Main app navigation structure
public struct AppNavigation: View {
  @Bindable var authViewModel: AuthViewModel
  @State private var studioListVM = StudioListViewModel()

  public var body: some View {
    if authViewModel.isAuthenticated {
      StudioListView(viewModel: studioListVM, authViewModel: authViewModel)
    } else {
      LoginView(viewModel: authViewModel)
    }
  }
}

#Preview {
  @Previewable @State var authVM = AuthViewModel()
  AppNavigation(authViewModel: authVM)
}
