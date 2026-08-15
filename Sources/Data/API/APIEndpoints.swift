import Foundation

/// Service base URLs.
///
/// weekclip is split across three Workers services and the app talks to two of
/// them, exactly as the web client does (`getApiBaseUrl` / `getUserApiBaseUrl`
/// in weekclip-web `src/shared/api/client.ts`).
///
/// Billing is deliberately absent: PRD-0008 D3 requires zero payment strings in
/// the binary and N6 makes CI check for it. Capacity *reads* the app needs come
/// from weekclip-api, not the billing service.
///
/// Values mirror the `routes` in each service's `wrangler.jsonc`. Debug and
/// release differ because the two tiers are **separate Cloudflare accounts with
/// separate databases** — a single constant would be a way to write debug
/// traffic into production.
public struct APIEndpoints: Sendable {
  public let api: URL
  public let userAPI: URL

  public init(api: URL, userAPI: URL) {
    self.api = api
    self.userAPI = userAPI
  }

  /// The dev tier. Note `.dev`, not `.com`.
  public static let development = APIEndpoints(
    api: URL(string: "https://service-api.weekclip.dev/api/v1")!,
    userAPI: URL(string: "https://user-api.weekclip.dev/api/v1")!
  )

  public static let production = APIEndpoints(
    api: URL(string: "https://service-api.weekclip.com/api/v1")!,
    userAPI: URL(string: "https://user-api.weekclip.com/api/v1")!
  )

  /// Picked by build configuration rather than by a runtime flag, so a release
  /// build cannot be talked into the dev tier by anything on the device.
  public static var current: APIEndpoints {
    #if DEBUG
    return .development
    #else
    return .production
    #endif
  }
}
