import Foundation
import WeekclipShared

/// Everything that has to happen before the browser opens.
///
/// A type rather than three calls in the view model because the **order** is
/// load-bearing and getting it wrong is not visible in a screenshot: the
/// verifier must be stored *before* the URL derived from it is handed to the
/// browser. Reversed, a fast redirect brings the app back holding a code it has
/// no verifier for, which reads to the user as "Google worked and weekclip lost
/// it".
///
/// Mirrors `BeginGoogleSignInUseCase` in weekclip-android. It sits in
/// `WeekclipData` rather than `WeekclipDomain` for the reason
/// `AuthRepository` states — what it traffics in is a Supabase grant.
public struct BeginGoogleSignIn: Sendable {
  private let config: AuthConfig
  private let flowStore: SignInFlowStore

  public init(config: AuthConfig, flowStore: SignInFlowStore) {
    self.config = config
    self.flowStore = flowStore
  }

  /// - Returns: the URL to open, or nil when this build has no Supabase project
  ///   compiled in. Nil is a real state, not a guard — it is what a release
  ///   build looked like until the production anon key landed in the ledger,
  ///   and the login screen says so rather than presenting an empty sheet.
  public func callAsFunction() -> URL? {
    let challenge = PkceChallenge.generate()
    guard let url = SupabaseOAuth.authorizeURL(config: config, challenge: challenge) else {
      return nil
    }

    flowStore.putVerifier(challenge.verifier)
    return url
  }
}

/// Everything that has to happen after the browser comes back.
///
/// Take the verifier, trade the code for a grant, hand the grant to the one
/// thing allowed to own sessions. The view model does none of it, because the
/// middle step must not be skippable: a code that reached the app without a
/// matching verifier belongs to a different sign-in — possibly a different
/// app's (see `PkceChallenge`) — and the only correct response is to refuse it.
///
/// The intended route is **not** read here. Navigating is the shell's job, and
/// it has to work identically for a user who was already signed in when the
/// link arrived — a path this type never runs on.
public struct CompleteGoogleSignIn: Sendable {
  private let flowStore: SignInFlowStore
  private let repository: any AuthRepository
  private let sessionManager: SessionManager

  public init(
    flowStore: SignInFlowStore,
    repository: any AuthRepository,
    sessionManager: SessionManager
  ) {
    self.flowStore = flowStore
    self.repository = repository
    self.sessionManager = sessionManager
  }

  public func callAsFunction(code: String) async -> Result<Void, AppError> {
    // Consumes it. A retry after a failed exchange starts a new round trip with
    // a new verifier, because the code it would pair with is spent either way.
    guard let verifier = flowStore.takeVerifier() else {
      AppLog.session.notice("a redirect arrived with no verifier stored; refusing it")
      return .failure(.unauthorized)
    }

    switch await repository.exchangeAuthCode(code: code, verifier: verifier) {
    case .success(let profile):
      await sessionManager.adopt(profile)
      AppLog.session.info("signed in as \(profile.userID, privacy: .public); session stored")
      return .success(())
    case .failure(let error):
      return .failure(error)
    }
  }
}
