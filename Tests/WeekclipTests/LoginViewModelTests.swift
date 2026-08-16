import Foundation
import Testing
import WeekclipData
import WeekclipShared

@testable import WeekclipPresentation

/// The login screen's state machine, with the browser sheet replaced by a stub.
///
/// The sheet is the only part of this feature that cannot run off a device, and
/// it is behind `WebAuthenticating` for exactly that reason — everything the
/// user can observe is decided by the code below it.
@MainActor
@Suite("LoginViewModel")
struct LoginViewModelTests {

  private let config = AuthConfig(
    supabaseURL: URL(string: "https://project.supabase.co"),
    anonKey: "anon"
  )

  private func makeFlowStore() -> SignInFlowStore {
    SignInFlowStore(defaults: UserDefaults(suiteName: "LoginViewModelTests.\(UUID())")!)
  }

  private func makeViewModel(
    flowStore: SignInFlowStore,
    sessionManager: SessionManager,
    authenticator: any WebAuthenticating,
    repository: any AuthRepository = StubAuthRepository(),
    config: AuthConfig? = nil,
    debugSignInAction: (any DebugSignInAction)? = nil
  ) -> LoginViewModel {
    let authConfig = config ?? self.config
    return LoginViewModel(
      beginGoogleSignIn: BeginGoogleSignIn(config: authConfig, flowStore: flowStore),
      completeGoogleSignIn: CompleteGoogleSignIn(
        flowStore: flowStore,
        repository: repository,
        sessionManager: sessionManager
      ),
      flowStore: flowStore,
      authenticator: authenticator,
      debugSignInAction: debugSignInAction
    )
  }

  private func makeSessionManager() -> SessionManager {
    SessionManager(
      store: RecordingStore(),
      refresher: NoopRefresher(),
      authConfig: config,
      now: { 0 }
    )
  }

  @Test("a completed round trip becomes a session")
  func happyPath() async {
    let flowStore = makeFlowStore()
    let manager = makeSessionManager()
    let repository = StubAuthRepository()
    let viewModel = makeViewModel(
      flowStore: flowStore,
      sessionManager: manager,
      authenticator: StubAuthenticator(result: .success(Self.callbackURL(code: "auth-code-1"))),
      repository: repository
    )

    await viewModel.signInWithGoogle()

    #expect(await manager.state == .signedIn(userID: "user-1"))
    #expect(repository.lastCode == "auth-code-1")
  }

  @Test("the verifier is stored before the sheet opens, and presented at the exchange")
  func verifierRoundTrip() async {
    let flowStore = makeFlowStore()
    let repository = StubAuthRepository()
    // The stub reads the store at the moment the sheet would be presented,
    // which is the ordering that matters. Reversed, a fast redirect brings the
    // app back holding a code it has no verifier for.
    let authenticator = StubAuthenticator(
      result: .success(Self.callbackURL(code: "auth-code-1")),
      flowStore: flowStore
    )

    let viewModel = makeViewModel(
      flowStore: flowStore,
      sessionManager: makeSessionManager(),
      authenticator: authenticator,
      repository: repository
    )

    await viewModel.signInWithGoogle()

    #expect(authenticator.verifierAtPresentation != nil)
    // Without this the flow is PKCE-shaped but not PKCE: an intercepted code
    // would be redeemable by whoever intercepted it.
    #expect(repository.lastVerifier == authenticator.verifierAtPresentation)
  }

  @Test("a cancelled sign-in returns to the button with no error")
  func cancelled() async {
    let flowStore = makeFlowStore()
    let viewModel = makeViewModel(
      flowStore: flowStore,
      sessionManager: makeSessionManager(),
      authenticator: StubAuthenticator(result: .failure(WebAuthenticationError.cancelled))
    )

    await viewModel.signInWithGoogle()

    // Dismissing the sheet is not a failure to report — it is the user changing
    // their mind. An error banner here would be the app arguing with them.
    #expect(viewModel.state.phase == .idle)
    #expect(viewModel.state.error == nil)
    // The abandoned verifier is cleared, so the next sign-in cannot be matched
    // against it.
    #expect(flowStore.takeVerifier() == nil)
  }

  @Test("a refusal is shown as a refusal, not as a failure")
  func denied() async {
    let viewModel = makeViewModel(
      flowStore: makeFlowStore(),
      sessionManager: makeSessionManager(),
      authenticator: StubAuthenticator(
        result: .success(
          URL(string: "cc.sunglint.weekclip://auth-callback?error=access_denied")!))
    )

    await viewModel.signInWithGoogle()

    // The wireframe draws these separately because the user's next move
    // differs: retry helps one and not the other.
    #expect(viewModel.state.error == .denied(reason: "access_denied"))
    #expect(viewModel.state.phase == .idle)
  }

  @Test("a failed exchange offers a retry rather than a dead spinner")
  func failedExchange() async {
    let manager = makeSessionManager()
    let viewModel = makeViewModel(
      flowStore: makeFlowStore(),
      sessionManager: manager,
      authenticator: StubAuthenticator(result: .success(Self.callbackURL(code: "auth-code-1"))),
      repository: StubAuthRepository(result: .failure(.offline))
    )

    await viewModel.signInWithGoogle()

    #expect(viewModel.state.error == .failed(cause: .offline))
    #expect(viewModel.state.phase == .idle)
    // A failed exchange must not leave a half-session behind.
    #expect(await manager.state != .signedIn(userID: "user-1"))
  }

  @Test("a code with no stored verifier is refused without a network call")
  func codeWithoutVerifier() async {
    let flowStore = makeFlowStore()
    let repository = StubAuthRepository()
    let authenticator = StubAuthenticator(result: .success(Self.callbackURL(code: "auth-code-1")))
    // Drops the verifier while the sheet is up — the shape of a redirect that
    // belongs to some other app's sign-in, or to one already completed.
    authenticator.whilePresented = { _ = flowStore.takeVerifier() }

    let viewModel = makeViewModel(
      flowStore: flowStore,
      sessionManager: makeSessionManager(),
      authenticator: authenticator,
      repository: repository
    )

    await viewModel.signInWithGoogle()

    #expect(repository.lastCode == nil)
    #expect(viewModel.state.error == .failed(cause: .unauthorized))
  }

  @Test("a build with no project key says so instead of opening a sheet")
  func unconfigured() async {
    let authenticator = StubAuthenticator(result: .success(Self.callbackURL(code: "x")))
    let viewModel = makeViewModel(
      flowStore: makeFlowStore(),
      sessionManager: makeSessionManager(),
      authenticator: authenticator,
      config: AuthConfig(supabaseURL: nil, anonKey: "")
    )

    await viewModel.signInWithGoogle()

    #expect(viewModel.state.error == .notConfigured)
    #expect(viewModel.state.phase == .idle)
    #expect(authenticator.calls == 0)
  }

  @Test("the screen says a link is waiting when one is")
  func intendedDestinationNotice() {
    let flowStore = makeFlowStore()
    flowStore.putIntendedRoute(WeekclipRoute.invite(token: "tok"))

    let viewModel = makeViewModel(
      flowStore: flowStore,
      sessionManager: makeSessionManager(),
      authenticator: StubAuthenticator(result: .failure(WebAuthenticationError.cancelled))
    )

    #expect(viewModel.state.hasIntendedDestination)
  }

  @Test("a release build has no debug button")
  func noDebugButtonWithoutAnAction() {
    let viewModel = makeViewModel(
      flowStore: makeFlowStore(),
      sessionManager: makeSessionManager(),
      authenticator: StubAuthenticator(result: .failure(WebAuthenticationError.cancelled))
    )

    // nil action is what `AppContainer` passes outside `#if DEBUG`.
    #expect(viewModel.state.debugSignInLabel == nil)
  }

  private static func callbackURL(code: String) -> URL {
    URL(string: "cc.sunglint.weekclip://auth-callback?code=\(code)")!
  }
}

/// Stands in for `ASWebAuthenticationSession`.
///
/// It also holds the flow store, so it can look at what is on disk **at the
/// moment the sheet would be presented** — which is the only interesting
/// instant in this whole flow, and the one the ordering bug lives in.
@MainActor
private final class StubAuthenticator: WebAuthenticating {
  private let result: Result<URL, Error>
  private let flowStore: SignInFlowStore?

  private(set) var calls = 0
  private(set) var verifierAtPresentation: String?

  /// Runs while the sheet is "up", so a test can disturb the store exactly then.
  var whilePresented: (() -> Void)?

  init(result: Result<URL, Error>, flowStore: SignInFlowStore? = nil) {
    self.result = result
    self.flowStore = flowStore
  }

  func authenticate(url: URL, callbackScheme: String) async throws -> URL {
    calls += 1
    // Peek: take, then put back. The store has no read-without-consume for the
    // verifier on purpose — single use is the property, and a test is not a
    // reason to widen it.
    if let flowStore {
      verifierAtPresentation = flowStore.takeVerifier()
      if let verifierAtPresentation { flowStore.putVerifier(verifierAtPresentation) }
    }
    whilePresented?()
    return try result.get()
  }
}

private final class StubAuthRepository: AuthRepository, @unchecked Sendable {
  private let result: Result<ProfileSession, AppError>

  private(set) var lastCode: String?
  private(set) var lastVerifier: String?

  init(result: Result<ProfileSession, AppError>? = nil) {
    self.result =
      result
      ?? .success(
        ProfileSession(
          accessToken: "access-1",
          refreshToken: "refresh-1",
          expiresAtEpochSeconds: 10_000,
          userID: "user-1"
        ))
  }

  func exchangeAuthCode(
    code: String,
    verifier: String
  ) async -> Result<ProfileSession, AppError> {
    lastCode = code
    lastVerifier = verifier
    return result
  }
}

private actor RecordingStore: SessionStore {
  private var stored: ProfileSession?

  func read() async -> ProfileSession? { stored }
  func write(_ session: ProfileSession) async { stored = session }
  func clear() async { stored = nil }
}

private struct NoopRefresher: SessionRefresher {
  func refresh(_ profile: ProfileSession) async -> RefreshOutcome { .unavailable }
}
