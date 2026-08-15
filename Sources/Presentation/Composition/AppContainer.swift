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

  public init(endpoints: APIEndpoints = .current) {
    let client = APIClient(
      baseURL: endpoints.api,
      // No session yet — task 148.5 replaces this with a Keychain-backed
      // provider that also answers the guest/share axis (PRD-0008 D5).
      tokenProvider: NoSessionTokenProvider()
    )
    let studioRepository = RemoteStudioRepository(client: client)
    self.getStudios = GetStudios(repository: studioRepository)
  }

  /// Test/preview seam: build a container over an arbitrary repository so a
  /// screen can be driven without a network.
  public init(studioRepository: any StudioRepository) {
    self.getStudios = GetStudios(repository: studioRepository)
  }

  public func makeDashboardViewModel() -> DashboardViewModel {
    DashboardViewModel(getStudios: getStudios)
  }
}
