import SwiftUI

/// Login screen with Google Sign-In
public struct LoginView: View {
  @Bindable var viewModel: AuthViewModel

  public var body: some View {
    ZStack {
      // Background gradient
      LinearGradient(
        gradient: Gradient(colors: [
          Color(red: 0.95, green: 0.95, blue: 0.97),
          Color(red: 0.98, green: 0.98, blue: 0.99),
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 40) {
        Spacer()

        // Logo section
        VStack(spacing: 16) {
          Image(systemName: "play.circle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.blue)

          Text("WeekClip")
            .font(.system(size: 32, weight: .bold))
            .foregroundStyle(.primary)

          Text("Collaborate on media in real-time")
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(.secondary)
        }

        Spacer()

        // Main content
        VStack(spacing: 24) {
          if let error = viewModel.error {
            VStack(alignment: .leading, spacing: 8) {
              HStack {
                Image(systemName: "exclamationmark.circle.fill")
                  .foregroundStyle(.red)

                VStack(alignment: .leading) {
                  Text("Error")
                    .font(.system(size: 14, weight: .semibold))

                  Text(error.errorDescription ?? "Unknown error")
                    .font(.system(size: 13, weight: .regular))
                    .lineLimit(3)
                }

                Spacer()
              }
              .padding(12)
              .background(Color(red: 1.0, green: 0.95, blue: 0.95))
              .cornerRadius(8)
            }
            .onTapGesture {
              viewModel.clearError()
            }
          }

          // Google Sign-In Button
          Button(action: {
            // TODO: Trigger Google Sign-In flow
            // This will integrate with GoogleSignIn SDK
            handleGoogleSignIn()
          }) {
            HStack(spacing: 12) {
              if viewModel.isLoading {
                ProgressView()
                  .tint(.blue)
              } else {
                Image(systemName: "g.circle.fill")
                  .font(.system(size: 20))
                  .foregroundStyle(.blue)

                Text("Sign in with Google")
                  .font(.system(size: 16, weight: .semibold))
              }

              Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .foregroundStyle(.blue)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
          }
          .disabled(viewModel.isLoading)
          .opacity(viewModel.isLoading ? 0.6 : 1.0)

          // Info text
          VStack(spacing: 8) {
            Text("By signing in, you agree to our")
              .font(.system(size: 12, weight: .regular))
              .foregroundStyle(.secondary)

            HStack(spacing: 4) {
              Link("Terms of Service", destination: URL(string: "https://weekclip.com/terms")!)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)

              Text("and")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary)

              Link("Privacy Policy", destination: URL(string: "https://weekclip.com/privacy")!)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
            }
          }
          .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color.white)
        .cornerRadius(16)

        Spacer()
      }
      .padding(16)
    }
  }

  private func handleGoogleSignIn() {
    // TODO: Implement actual Google Sign-In flow
    // This is a placeholder that demonstrates the flow:
    // 1. Trigger GoogleSignIn.shared?.presentingViewController = self
    // 2. Call GoogleSignIn.shared?.signIn() with scopes
    // 3. On success, get ID token from GIDSignInResult
    // 4. Call viewModel.signInWithGoogle(idToken: token)

    // For now, simulate with a placeholder idToken
    Task {
      await viewModel.signInWithGoogle(idToken: "placeholder-id-token")
    }
  }
}

#Preview {
  @Previewable @State var viewModel = AuthViewModel()
  LoginView(viewModel: viewModel)
}
