import Foundation
import WeekclipDomain
import WeekclipShared

/// Reads `GET /app/version` and keeps only this platform's half.
///
/// The endpoint is unauthenticated by design (weekclip-api): an app too old to
/// be allowed in may also be too old to sign in, so the check has to work
/// before there is a session. `APIClient` still attaches a bearer if one
/// happens to exist — harmless, and not worth a second client to avoid.
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
