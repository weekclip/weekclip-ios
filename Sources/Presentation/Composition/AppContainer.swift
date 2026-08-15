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

  /// Nil in the test/preview container: those build over a fake repository and
  /// never make a request, so there is no session to manage.
  private let sessionManager: SessionManager?
  private let authConfig: AuthConfig

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
    self.getStudios = GetStudios(repository: studioRepository)
  }

  /// Test/preview seam: build a container over an arbitrary repository so a
  /// screen can be driven without a network.
  public init(studioRepository: any StudioRepository) {
    self.sessionManager = nil
    self.authConfig = AuthConfig(supabaseURL: nil, anonKey: "")
    self.getStudios = GetStudios(repository: studioRepository)
  }

  public func makeDashboardViewModel() -> DashboardViewModel {
    DashboardViewModel(getStudios: getStudios)
  }

  /// Process-start work, awaited by the root view.
  ///
  /// Empty in a release build. The debug-only sign-in is the sole caller today
  /// (148.5, until Google OAuth lands as 148.5c-b), and it is compiled out
  /// rather than skipped at runtime.
  public func start() async {
    #if DEBUG
    guard let sessionManager else { return }
    await DebugAutoSignIn(sessionManager: sessionManager, config: authConfig).run()
    #endif
  }
}
