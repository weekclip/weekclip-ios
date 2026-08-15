import Foundation

/// Whether this build is still allowed to run (PRD-0008 D6①).
///
/// Two cases, not three: "we could not find out" is deliberately folded into
/// `notRequired` by `GetAppUpdateRequirement`. A gate that blocks the app when
/// it cannot reach the server would brick every install during an outage —
/// including an outage of the very endpoint that would say "you are fine".
public enum AppUpdateRequirement: Equatable, Sendable {
  case notRequired

  /// This build is below the server's minimum and must stop.
  ///
  /// `storeURL` is nil when there is nowhere to send the user yet — the app
  /// then states the fact without offering a button that goes nowhere.
  case required(storeURL: String?)
}

/// One platform's slice of the server's release policy.
public struct AppReleasePolicy: Equatable, Sendable {
  public let minimumBuild: Int
  public let storeURL: String?

  public init(minimumBuild: Int, storeURL: String?) {
    self.minimumBuild = minimumBuild
    self.storeURL = storeURL
  }
}
