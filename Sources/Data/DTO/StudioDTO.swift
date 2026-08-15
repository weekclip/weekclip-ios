import Foundation
import WeekclipDomain

/// `GET /studios` item, exactly as weekclip-api's `presentStudioMembership`
/// emits it. Property names match the wire; do not rename them to read better.
///
/// Every field but `id` is optional. That is not defensive padding — the API
/// has already added a field to this shape once (`slug`), and a strict decoder
/// turns a server-side addition into a client-side failure for everyone who has
/// not updated.
struct StudioDTO: Decodable, Sendable {
  let id: String
  let slug: String?
  let name: String?
  let ownerId: String?
  let createdAt: String?
  let updatedAt: String?
  let role: String?
}

extension StudioDTO {
  /// Wire -> domain. Kept next to the DTO so the two move together.
  ///
  /// A studio with no name renders as an empty title rather than being dropped:
  /// hiding a row the server sent would make the count on screen disagree with
  /// the count on the web, which is much harder to diagnose than a blank label.
  var domain: Studio {
    Studio(
      id: id,
      slug: slug ?? "",
      name: name ?? "",
      ownerId: ownerId ?? "",
      role: StudioRole(wire: role),
      createdAt: createdAt,
      updatedAt: updatedAt
    )
  }
}
