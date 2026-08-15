import Foundation
import WeekclipDomain
import WeekclipShared

/// Remote-only for now.
///
/// There is no local cache: PRD-0008 states no offline requirement, and a
/// persistence schema with no read path is a migration liability from the day
/// it lands. The seam that makes one addable later is `StudioRepository` —
/// callers already cannot tell where the data came from.
public struct RemoteStudioRepository: StudioRepository {
  private let client: APIClient

  public init(client: APIClient) {
    self.client = client
  }

  public func getStudios() async -> Result<[Studio], AppError> {
    await client
      .get("studios", as: ItemsPayload<StudioDTO>.self)
      .map { payload in payload.items.map(\.domain) }
  }
}
