import Foundation
import WeekclipDomain
import WeekclipShared

/// Reads `GET /app/version` and keeps only this platform's half.
///
/// The endpoint is unauthenticated by design (weekclip-api): an app too old to
/// be allowed in may also be too old to sign in, so the check has to work
/// before there is a session. `APIClient` still attaches a bearer if one
/// happens to exist — harmless, and not worth a second client to avoid.
///
/// ⚠️ **The answer is cached on this platform and not on Android.** The
/// response carries `Cache-Control: public, max-age=300`, and
/// `URLSessionConfiguration.default` (see `APIClient.defaultSession`) has a
/// `URLCache` that honours it. weekclip-android's `OkHttpClient` is built with
/// no `Cache` and therefore asks every launch.
///
/// Measured on 2026-08-15 by raising the dev minimum to 99 and watching both
/// apps: Android blocked on the next launch, **this one kept letting the build
/// through for five minutes** and then blocked. Nothing was broken; the answer
/// was cached. That is inside the budget the TTL already buys, so it is left as
/// is — but it is written here because during an incident it reads as "the iOS
/// gate is broken", and that is exactly how it read while being found.
public struct RemoteAppReleaseRepository: AppReleaseRepository {
  private let client: APIClient

  public init(client: APIClient) {
    self.client = client
  }

  public func policy() async -> Result<AppReleasePolicy, AppError> {
    await client
      .get("app/version", as: AppReleaseDTO.self)
      .map { payload in payload.ios.domain }
  }
}
