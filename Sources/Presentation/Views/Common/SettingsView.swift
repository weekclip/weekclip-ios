import SwiftUI

/// Settings screen with user profile and logout
public struct SettingsView: View {
  @Environment(\.dismiss) var dismiss
  @Bindable var authViewModel: AuthViewModel

  public var body: some View {
    NavigationStack {
      ZStack {
        Color(red: 0.95, green: 0.95, blue: 0.97)
          .ignoresSafeArea()

        VStack(spacing: 0) {
          // User profile section
          if let user = authViewModel.user {
            VStack(spacing: 12) {
              HStack(spacing: 12) {
                // Avatar placeholder
                Circle()
                  .fill(Color.blue.opacity(0.3))
                  .frame(width: 48, height: 48)
                  .overlay(
                    Image(systemName: "person.fill")
                      .font(.system(size: 24))
                      .foregroundStyle(.blue)
                  )

                VStack(alignment: .leading, spacing: 4) {
                  if let displayName = user.displayName {
                    Text(displayName)
                      .font(.system(size: 16, weight: .semibold))
                  }

                  Text(user.email)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }

                Spacer()
              }
              .padding(16)
              .background(Color.white)
              .cornerRadius(8)
            }
            .padding(16)
          }

          // Settings sections
          VStack(spacing: 16) {
            SettingsSectionView(
              title: "About",
              items: [
                SettingsItemView(
                  icon: "info.circle",
                  title: "App Version",
                  subtitle: "1.0.0",
                  action: {}
                ),
              ]
            )

            SettingsSectionView(
              title: "Support",
              items: [
                SettingsItemView(
                  icon: "questionmark.circle",
                  title: "Help & Support",
                  action: {
                    // Open support URL
                  }
                ),
                SettingsItemView(
                  icon: "exclamationmark.circle",
                  title: "Report a Problem",
                  action: {
                    // Open bug report
                  }
                ),
              ]
            )

            SettingsSectionView(
              title: "Account",
              items: [
                SettingsItemView(
                  icon: "arrow.right.square",
                  title: "Sign Out",
                  color: .red,
                  action: {
                    Task {
                      await authViewModel.signOut()
                      dismiss()
                    }
                  }
                ),
              ]
            )
          }
          .padding(16)

          Spacer()

          // Footer
          VStack(spacing: 8) {
            HStack(spacing: 12) {
              Link(destination: URL(string: "https://weekclip.com/terms")!) {
                Text("Terms of Service")
                  .font(.system(size: 12, weight: .regular))
                  .foregroundStyle(.blue)
              }

              Divider()
                .frame(height: 12)

              Link(destination: URL(string: "https://weekclip.com/privacy")!) {
                Text("Privacy Policy")
                  .font(.system(size: 12, weight: .regular))
                  .foregroundStyle(.blue)
              }
            }
            .multilineTextAlignment(.center)
          }
          .padding(16)
          .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
              Text("Back")
            }
            .foregroundStyle(.blue)
          }
        }
      }
    }
  }
}

// MARK: - Settings Section

struct SettingsSectionView: View {
  let title: String
  let items: [SettingsItemView]

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)

      VStack(spacing: 0) {
        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
          item

          if index < items.count - 1 {
            Divider()
              .padding(.horizontal, 12)
          }
        }
      }
      .background(Color.white)
      .cornerRadius(8)
    }
  }
}

// MARK: - Settings Item

struct SettingsItemView: View {
  let icon: String
  let title: String
  let subtitle: String?
  let color: Color
  let action: () -> Void

  init(
    icon: String,
    title: String,
    subtitle: String? = nil,
    color: Color = .primary,
    action: @escaping () -> Void
  ) {
    self.icon = icon
    self.title = title
    self.subtitle = subtitle
    self.color = color
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: icon)
          .font(.system(size: 16, weight: .semibold))
          .frame(width: 24)
          .foregroundStyle(color)

        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)

          if let subtitle = subtitle {
            Text(subtitle)
              .font(.system(size: 13, weight: .regular))
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(12)
    }
  }
}

#Preview {
  @Previewable @State var authVM = AuthViewModel()
  SettingsView(authViewModel: authVM)
}
