import Foundation
import WeekclipDomain

/// `GET /app/version`, exactly as weekclip-api's `buildAppReleasePolicy` emits
/// it. Both platforms are returned; this client reads its own.
///
/// Every field is optional, and here that matters more than usual: this is the
/// one endpoint that can stop the app from running, and it is read before
/// anything else. A strict decode would turn a server-side field addition into
/// a failure on launch, on the exact call that exists to keep the app healthy.
struct AppReleaseDTO: Decodable, Sendable {
  let android: AppPlatformPolicyDTO?
  let ios: AppPlatformPolicyDTO?
}

struct AppPlatformPolicyDTO: Decodable, Sendable {
  let minimumBuild: Int?
  let storeUrl: String?
}

extension AppPlatformPolicyDTO? {
  /// A missing `minimumBuild` becomes 0 — block nobody. The server already
  /// fails open for an absent config; this keeps the client from failing closed
  /// on a response shape it did not expect.
  var domain: AppReleasePolicy {
    AppReleasePolicy(
      minimumBuild: self?.minimumBuild ?? 0,
      storeURL: self?.storeUrl.flatMap { $0.isEmpty ? nil : $0 }
    )
  }
}
