import SwiftUI

/// Studio list screen
public struct StudioListView: View {
  @Bindable var viewModel: StudioListViewModel
  @Bindable var authViewModel: AuthViewModel
  @State private var showingSettings = false
  @State private var selectedStudio: Studio?

  public var body: some View {
    NavigationStack {
      ZStack {
        // Background
        Color(red: 0.95, green: 0.95, blue: 0.97)
          .ignoresSafeArea()

        VStack(spacing: 0) {
          // Search bar
          HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
              .foregroundStyle(.secondary)

            TextField("Search studios", text: $viewModel.searchText)
              .textFieldStyle(.plain)

            if !viewModel.searchText.isEmpty {
              Button(action: { viewModel.searchText = "" }) {
                Image(systemName: "xmark.circle.fill")
                  .foregroundStyle(.secondary)
              }
            }
          }
          .padding(12)
          .background(Color.white)
          .cornerRadius(8)
          .padding(16)

          // Content
          if viewModel.isLoading {
            VStack(spacing: 12) {
              ProgressView()
              Text("Loading studios...")
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if viewModel.filteredStudios.isEmpty {
            EmptyStateView(
              icon: "play.circle",
              title: "No studios",
              message: "You don't have access to any studios yet"
            )
          } else {
            // Studio list
            List(viewModel.filteredStudios) { studio in
              NavigationLink(value: studio) {
                StudioListItemView(studio: studio)
              }
              .listRowBackground(Color.white)
              .listRowSeparator(.hidden)
              .padding(.vertical, 4)
            }
            .listStyle(.plain)
            .refreshable {
              await viewModel.refresh()
            }
          }

          if let error = viewModel.error {
            ErrorBannerView(error: error) {
              viewModel.clearError()
            }
            .padding(16)
          }
        }
      }
      .navigationTitle("Studios")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { showingSettings = true }) {
            Image(systemName: "gear")
              .foregroundStyle(.primary)
          }
        }
      }
      .sheet(isPresented: $showingSettings) {
        SettingsView(authViewModel: authViewModel)
      }
      .navigationDestination(for: Studio.self) { studio in
        MediaListView(
          studioId: studio.id,
          studioName: studio.name
        )
      }
      .task {
        await viewModel.loadStudios()
      }
    }
  }
}

// MARK: - Studio List Item

struct StudioListItemView: View {
  let studio: Studio

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        // Logo placeholder
        if let logoUrl = studio.logoUrl {
          AsyncImage(url: URL(string: logoUrl)) { image in
            image
              .resizable()
              .scaledToFill()
              .frame(width: 48, height: 48)
              .cornerRadius(8)
          } placeholder: {
            PlaceholderImageView()
              .frame(width: 48, height: 48)
          }
        } else {
          PlaceholderImageView()
            .frame(width: 48, height: 48)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(studio.name)
            .font(.system(size: 16, weight: .semibold))
            .lineLimit(1)

          HStack(spacing: 8) {
            RoleBadgeView(role: studio.role)

            Text("\(studio.mediaCount) media")
              .font(.system(size: 13, weight: .regular))
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }

      if let description = studio.description {
        Text(description)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
    }
    .padding(12)
    .background(Color.white)
    .cornerRadius(8)
  }
}

// MARK: - Role Badge

struct RoleBadgeView: View {
  let role: StudioRole

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: roleIconName)
        .font(.system(size: 12, weight: .semibold))

      Text(role.rawValue.capitalized)
        .font(.system(size: 12, weight: .semibold))
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(roleBadgeColor)
    .cornerRadius(4)
  }

  private var roleIconName: String {
    switch role {
    case .admin:
      return "crown.fill"
    case .member:
      return "person.fill"
    case .viewer:
      return "eye.fill"
    }
  }

  private var roleBadgeColor: Color {
    switch role {
    case .admin:
      return Color(red: 1.0, green: 0.6, blue: 0.0)
    case .member:
      return Color(red: 0.0, green: 0.5, blue: 1.0)
    case .viewer:
      return Color(red: 0.5, green: 0.5, blue: 0.5)
    }
  }
}

#Preview {
  @Previewable @State var studioListVM = StudioListViewModel()
  @Previewable @State var authVM = AuthViewModel()

  let previewStudio = Studio(
    id: "1",
    name: "Apple Event 2024",
    description: "Footage from the main keynote",
    logoUrl: nil,
    role: .admin,
    mediaCount: 42
  )
  studioListVM.studios = [previewStudio]
  studioListVM.filteredStudios = [previewStudio]

  return StudioListView(viewModel: studioListVM, authViewModel: authVM)
}
