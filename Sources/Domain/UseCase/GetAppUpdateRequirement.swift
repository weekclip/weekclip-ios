import Foundation

/// Decides whether this build may keep running.
///
/// Two rules, both of which are the kind that get written the wrong way round
/// exactly once — in production, for everybody, at the same time:
///
/// 1. **Strictly below.** A build equal to the minimum is allowed. `>=` here
///    would block the very release an operator just declared to be the floor —
///    the one they are trying to force everyone onto.
/// 2. **Any failure means "carry on".** No network, a timeout, a WAF answering
///    403, a body we cannot parse: none is evidence that this build is too old.
///    Blocking on them would turn every outage into a force-update screen for
///    the whole fleet, and the server that could take it back is the one that
///    is down.
///
/// The server makes the same choice from the other end — an unconfigured
/// `APP_MIN_BUILD_*` returns 0 and blocks nobody (weekclip-api `app-release.ts`).
/// Both ends fail open, so it takes two deliberate acts to stop an app.
public struct GetAppUpdateRequirement: Sendable {
  private let repository: any AppReleaseRepository

  public init(repository: any AppReleaseRepository) {
    self.repository = repository
  }

  public func callAsFunction(currentBuild: Int) async -> AppUpdateRequirement {
    switch await repository.policy() {
    case .success(let policy):
      return currentBuild < policy.minimumBuild
        ? .required(storeURL: policy.storeURL)
        : .notRequired
    case .failure:
      return .notRequired
    }
  }
}
