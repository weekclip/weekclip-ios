import Foundation
import WeekclipData
import WeekclipDomain

/// The composition root. Manual DI (ADR-0002: "수동 DI (컴포지션 루트)").
///
/// Everything the app needs is constructed in one place, once, and handed down.
/// The whole graph is the few lines below — a DI framework would add a
/// dependency, a registration DSL, and a class of failure that only shows up at
/// runtime, in exchange for saving those lines.
///
/// The rule this enforces: **nothing below constructs its own dependencies.**
/// A view model that reaches for `APIClient()` on its own is untestable, and
/// there is no container to stop it except this convention.
@MainActor
public final class AppContainer {
  public let getStudios: GetStudios

  /// Nil in the test/preview container: it builds over a fake repository and
  /// never makes a request, so there is nothing to version-gate.
  public let getAppUpdateRequirement: GetAppUpdateRequirement?

  /// Nil in the test/preview container: those build over a fake repository and
  /// never make a request, so there is no session to manage.
  private let sessionManager: SessionManager?
  private let authConfig: AuthConfig
  private let flowStore: SignInFlowStore

  public init(endpoints: APIEndpoints = .current, authConfig: AuthConfig = .current) {
    let manager = SessionManager(
      store: KeychainSessionStore(),
      refresher: SupabaseSessionRefresher(config: authConfig),
      authConfig: authConfig
    )
    let client = APIClient(
      baseURL: endpoints.api,
      credentials: SessionManagerCredentialProvider(sessionManager: manager)
    )
    let studioRepository = RemoteStudioRepository(client: client)

    self.sessionManager = manager
    self.authConfig = authConfig
    self.flowStore = SignInFlowStore()
    self.getStudios = GetStudios(repository: studioRepository)
    self.getAppUpdateRequirement = GetAppUpdateRequirement(
      repository: RemoteAppReleaseRepository(client: client)
    )
  }

  /// Test/preview seam: build a container over an arbitrary repository so a
  /// screen can be driven without a network.
  public init(studioRepository: any StudioRepository) {
    self.sessionManager = nil
    self.authConfig = AuthConfig(supabaseURL: nil, anonKey: "")
    self.flowStore = SignInFlowStore()
    self.getStudios = GetStudios(repository: studioRepository)
    self.getAppUpdateRequirement = nil
  }

  public func makeDashboardViewModel() -> DashboardViewModel {
    DashboardViewModel(getStudios: getStudios)
  }

  /// The auth gate.
  ///
  /// The preview container has no `SessionManager`, so it gets one built over
  /// an in-memory store with nothing in it — the gate then reports `signedOut`
  /// and a preview shows the login screen, which is the honest answer for a
  /// container with no session.
  public func makeAuthGateModel() -> AuthGateModel {
    AuthGateModel(sessionManager: sessionManager ?? Self.emptySessionManager(), flowStore: flowStore)
  }

  public func makeLoginViewModel() -> LoginViewModel {
    let manager = sessionManager ?? Self.emptySessionManager()
    return LoginViewModel(
      beginGoogleSignIn: BeginGoogleSignIn(config: authConfig, flowStore: flowStore),
      completeGoogleSignIn: CompleteGoogleSignIn(
        flowStore: flowStore,
        repository: SupabaseAuthRepository(config: authConfig),
        sessionManager: manager
      ),
      flowStore: flowStore,
      authenticator: WebAuthenticator(),
      debugSignInAction: Self.debugSignInAction(sessionManager: manager, config: authConfig)
    )
  }

  /// Nil outside a debug build — the whole affordance is compiled out rather
  /// than skipped at runtime, so the release binary contains neither the
  /// password grant nor the button's label.
  ///
  /// Also nil when the build carries no credentials: a button that is
  /// guaranteed to fail is worse than no button, and it makes the state of the
  /// checkout visible on the screen instead of on the second tap. `maestro/`
  /// branches on exactly that.
  private static func debugSignInAction(
    sessionManager: SessionManager,
    config: AuthConfig
  ) -> (any DebugSignInAction)? {
    #if DEBUG
    return DebugPasswordSignIn.makeIfConfigured(sessionManager: sessionManager, config: config)
    #else
    return nil
    #endif
  }

  private static func emptySessionManager() -> SessionManager {
    SessionManager(
      store: InMemorySessionStore(),
      refresher: NoRefresher(),
      authConfig: AuthConfig(supabaseURL: nil, anonKey: "")
    )
  }
}

/// A store with nothing in it, for the preview/test container.
private struct InMemorySessionStore: SessionStore {
  func read() async -> ProfileSession? { nil }
  func write(_ session: ProfileSession) async {}
  func clear() async {}
}

private struct NoRefresher: SessionRefresher {
  func refresh(_ profile: ProfileSession) async -> RefreshOutcome { .unavailable }
}
