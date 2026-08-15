import Foundation

/// Route table.
///
/// **This is a contract, not a convenience.** The paths mirror weekclip-web's
/// URLs one-for-one, and `WeekclipRoutes` in weekclip-android mirrors the same
/// ones. PRD-0008 D4 routes `/studios/:id/media/:mid`, `/invite/:token` and
/// `/share/:token` into the app via Universal Links, and PRD-0007 D6 named the
/// media route as "the boundary where native push/pop attaches". If any of the
/// three drift apart, deep links stop resolving — silently, on other people's
/// phones.
///
/// Typed rather than stringly-typed (ADR-0002: "`NavigationStack` + 타입 있는
/// path"), so a destination with the wrong arity does not compile.
/// `WeekclipRouteTests` asserts every case against the literal path it must
/// produce, and round-trips each one back through `init?(path:)`.
public enum WeekclipRoute: Hashable, Sendable {
  case dashboard
  case studio(id: String)
  case media(studioID: String, mediaID: String)
  case members(studioID: String)
  case capacity(studioID: String)
  case invite(token: String)
  case share(token: String)

  /// The path this route occupies, with no leading slash — the same strings the
  /// Android route table builds.
  public var path: String {
    switch self {
    case .dashboard:
      return "dashboard"
    case .studio(let id):
      return "studios/\(id)"
    case .media(let studioID, let mediaID):
      return "studios/\(studioID)/media/\(mediaID)"
    case .members(let studioID):
      return "studios/\(studioID)/members"
    case .capacity(let studioID):
      return "studios/\(studioID)/capacity"
    case .invite(let token):
      return "invite/\(token)"
    case .share(let token):
      return "share/\(token)"
    }
  }

  /// Parses an incoming path back into a route.
  ///
  /// This is the half a Universal Link needs: `weekclip.com/studios/a/media/b`
  /// arrives as a `URL`, and the app has to decide which screen it names.
  /// Returning nil means "not a route this app owns" — the caller sends those
  /// to the web rather than guessing (PRD-0008 D4 keeps public pages on the web).
  public init?(path: String) {
    let segments =
      path
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)

    // Matched on (count, head) rather than as an array pattern: Swift has no
    // array-literal pattern that can bind, so `case ["studios", let id]` does
    // not compile.
    switch (segments.count, segments.first) {
    case (1, "dashboard"):
      self = .dashboard

    case (2, "studios"):
      self = .studio(id: segments[1])

    case (2, "invite"):
      self = .invite(token: segments[1])

    case (2, "share"):
      self = .share(token: segments[1])

    case (3, "studios") where segments[2] == "members":
      self = .members(studioID: segments[1])

    case (3, "studios") where segments[2] == "capacity":
      self = .capacity(studioID: segments[1])

    case (4, "studios") where segments[2] == "media":
      self = .media(studioID: segments[1], mediaID: segments[3])

    default:
      return nil
    }
  }

  /// Convenience for a Universal Link. Only the path matters — host
  /// verification is Apple's job, via the `apple-app-site-association` that
  /// weekclip.com has to serve (task 148.5 / PRD-0008 N2).
  public init?(url: URL) {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      return nil
    }
    self.init(path: components.path)
  }
}
