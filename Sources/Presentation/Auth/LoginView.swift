import SwiftUI
import WeekclipShared

/// The first gate.
///
/// Layout follows the wireframe (`screens/auth/mobile.html`): identity, then one
/// way in, then — app-only — what you will be taken back to. The notes are
/// explicit that there is exactly one button, and the reason is worth keeping in
/// front of whoever adds the second one: *"방법이 둘이면 재방문 때 '지난번에 뭘로
/// 들어왔지'가 생기고, 그 순간 이탈이 난다."*
///
/// Accessibility identifiers are set explicitly because that is what `maestro/`
/// selects on — SwiftUI does not derive one from a label.
public struct LoginView: View {
  @State private var viewModel: LoginViewModel

  public init(viewModel: LoginViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  public var body: some View {
    VStack(spacing: 16) {
      Spacer()

      Text("Sign in to WeekClip", comment: "Login screen title")
        .font(.title)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("screen-title")

      Text("Your studios, on this device.", comment: "Login screen subtitle")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      signInControl

      if viewModel.state.hasIntendedDestination {
        // App-only zone in the wireframe ("딥링크 복귀"). Not decoration: an
        // unexpected login screen reads as "it forgot what I tapped" unless
        // something says otherwise.
        Text("We'll take you back to what you opened.", comment: "Deep-link return notice")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .accessibilityIdentifier("login-intended-destination")
      }

      if let error = viewModel.state.error {
        errorState(error)
      }

      if let label = viewModel.state.debugSignInLabel {
        Button(label) {
          Task { await viewModel.signInWithDebugCredentials() }
        }
        .font(.footnote)
        .accessibilityIdentifier("login-debug")
      }

      Spacer()
    }
    .padding(.horizontal, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // ⚠️ No `.accessibilityIdentifier` on this container, and it must stay that
    // way. SwiftUI propagates accessibility modifiers **down**, and the
    // outermost one wins — an identifier here silently rewrites every
    // descendant's. Measured 2026-08-16 against the simulator: with one on this
    // VStack the hierarchy reported `screen-title`, `login-google` and
    // `login-debug` all as `login-screen`, and `maestro/` matched none of them
    // while the screenshot looked perfect. Identifiers belong on leaves.
  }

  @ViewBuilder
  private var signInControl: some View {
    if viewModel.state.isBusy {
      // The wireframe's `loading` state, and its note is the requirement: "앱은
      // 외부 브라우저로 나갔다 돌아온다. 돌아오는 동안 이 화면이 남아 있어야
      // 한다." Replacing the button rather than covering the screen is what
      // keeps it the same screen.
      VStack(spacing: 8) {
        ProgressView()
        Text("Finish signing in in your browser.", comment: "Login connecting state")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, minHeight: minTouchTarget)
      .accessibilityIdentifier("login-connecting")
    } else {
      Button {
        Task { await viewModel.signInWithGoogle() }
      } label: {
        Text("Continue with Google", comment: "Google sign-in button")
          .frame(maxWidth: .infinity, minHeight: minTouchTarget)
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("login-google")
    }
  }

  private func errorState(_ error: LoginError) -> some View {
    VStack(spacing: 8) {
      Text(message(for: error))
        .font(.callout)
        .multilineTextAlignment(.center)
        // On the label, not on the enclosing VStack — see the note at the end
        // of `body`. A container identifier would take `login-retry` with it.
        .accessibilityIdentifier("login-error")

      // No retry for `.notConfigured`: pressing it again cannot compile a
      // project key into the running binary. The wireframe draws the same split
      // — `error` gets a button, `denied` does not.
      if error != .notConfigured {
        Button("Try again") {
          Task { await viewModel.retry() }
        }
        .accessibilityIdentifier("login-retry")
      }
    }
    .frame(maxWidth: .infinity)
  }

  /// Error -> copy.
  ///
  /// A `switch` over the closed set, so a new `LoginError` fails to compile here
  /// rather than falling through to a message nobody notices is wrong — the same
  /// rule `DashboardView` states for `AppError`.
  private func message(for error: LoginError) -> String {
    switch error {
    case .denied:
      return String(localized: "Sign-in was not completed.")
    case .notConfigured:
      return String(localized: "This build cannot sign in.")
    case .browserUnavailable:
      return String(localized: "Could not open the sign-in page.")
    case .failed(let cause):
      switch cause {
      case .offline:
        return String(localized: "You appear to be offline.")
      case .timeout:
        return String(localized: "The server took too long to respond.")
      default:
        return String(localized: "Could not sign in. Please try again.")
      }
    }
  }

  /// 44pt is Apple's minimum hit target (HIG, Layout). Stating it means a
  /// padding change cannot quietly drop below the floor.
  private let minTouchTarget: CGFloat = 44
}
