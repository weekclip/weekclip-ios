import Foundation
import Observation
import WeekclipData
import WeekclipShared

/// A way into the app that is not Google, present only in builds that have one.
///
/// The concrete implementation lives behind `#if DEBUG` in `AppContainer`, so a
/// release build constructs this view model with nil and the button does not
/// exist. `if isDebugBuild` inside the view would be a different thing: the code
/// would ship.
public protocol DebugSignInAction: Sendable {
  /// What to put on the button.
  var label: String { get }

  /// - Returns: true when a session was adopted.
  func signIn() async -> Bool
}

/// The first gate's state holder.
///
/// ### It never decides whether the user is signed in
///
/// `AuthGateModel` does that, from `SessionManager`, and this screen only
/// exists once the answer is `signedOut`. Asking here as well would give two
/// owners of one fact and, worse, a moment where they disagree.
///
/// ### Cancellation is reported, not inferred
///
/// The whole round trip is one `await` on `WebAuthenticating`, which throws
/// `.cancelled` when the user dismisses the sheet. The Android twin cannot do
/// this — that platform sends no event when a Custom Tab is dismissed, so it
/// infers cancellation from an empty slot at `onResume` (`AuthRedirectBus`).
/// Same product behaviour, one linear function here and a lifecycle argument
/// there.
@MainActor
@Observable
public final class LoginViewModel {
  public private(set) var state: LoginUiState

  private let beginGoogleSignIn: BeginGoogleSignIn
  private let completeGoogleSignIn: CompleteGoogleSignIn
  private let flowStore: SignInFlowStore
  private let authenticator: any WebAuthenticating
  private let debugSignInAction: (any DebugSignInAction)?

  public init(
    beginGoogleSignIn: BeginGoogleSignIn,
    completeGoogleSignIn: CompleteGoogleSignIn,
    flowStore: SignInFlowStore,
    authenticator: any WebAuthenticating,
    debugSignInAction: (any DebugSignInAction)? = nil
  ) {
    self.beginGoogleSignIn = beginGoogleSignIn
    self.completeGoogleSignIn = completeGoogleSignIn
    self.flowStore = flowStore
    self.authenticator = authenticator
    self.debugSignInAction = debugSignInAction
    self.state = LoginUiState(
      hasIntendedDestination: flowStore.hasIntendedRoute,
      debugSignInLabel: debugSignInAction?.label
    )
  }

  public func signInWithGoogle() async {
    guard !state.isBusy else { return }

    state.phase = .connecting
    state.error = nil

    guard let url = beginGoogleSignIn() else {
      state.phase = .idle
      state.error = .notConfigured
      return
    }

    let callbackURL: URL
    do {
      callbackURL = try await authenticator.authenticate(
        url: url,
        callbackScheme: SupabaseOAuth.callbackScheme
      )
    } catch WebAuthenticationError.cancelled {
      // The verifier will never be paired now. Leaving it would mean the *next*
      // sign-in's redirect could be matched against an abandoned one.
      _ = flowStore.takeVerifier()
      state.phase = .idle
      return
    } catch {
      _ = flowStore.takeVerifier()
      state.phase = .idle
      state.error = .browserUnavailable
      AppLog.session.error(
        "the sign-in sheet failed: \(String(describing: error), privacy: .public)")
      return
    }

    switch SupabaseOAuth.parseCallback(callbackURL) {
    case .granted(let code):
      await exchange(code)

    case .denied(let error, _):
      _ = flowStore.takeVerifier()
      state.phase = .idle
      state.error = .denied(reason: error)

    case .notACallback:
      // The system only hands back URLs matching the scheme we asked for, so
      // this is unreachable — but treating an unreadable redirect as success is
      // the one outcome that must not be possible.
      _ = flowStore.takeVerifier()
      state.phase = .idle
      state.error = .denied(reason: "unrecognised_redirect")
    }
  }

  /// Clears the error and starts over.
  public func retry() async {
    state.error = nil
    await signInWithGoogle()
  }

  /// Debug builds only; nil action in a release build makes this unreachable.
  ///
  /// A password grant puts a real token in front of the session code without a
  /// Google round trip, which is what makes the store and this gate checkable
  /// on a device before the Supabase redirect allow list exists.
  public func signInWithDebugCredentials() async {
    guard let debugSignInAction, !state.isBusy else { return }

    state.phase = .exchanging
    state.error = nil

    // On success the gate flips to signedIn and this screen goes away; setting
    // .idle first would put the form back for a frame underneath it.
    if await debugSignInAction.signIn() == false {
      state.phase = .idle
      state.error = .notConfigured
    }
  }

  private func exchange(_ code: String) async {
    state.phase = .exchanging
    state.error = nil

    switch await completeGoogleSignIn(code: code) {
    case .success:
      // Deliberately no state change: adopting the session flips
      // `SessionManager`, the gate swaps this screen out, and anything set here
      // would only be visible as a flash on the way off.
      break
    case .failure(let error):
      state.phase = .idle
      state.error = .failed(cause: error)
    }
  }
}
