import Foundation

/// A studio as the app reasons about it.
///
/// No `Codable`, no wire annotations — the DTO in `WeekclipData` owns that, so
/// the server's field names are free to change without reaching this type.
/// This mirrors `Studio` in weekclip-android exactly; the two clients agreeing
/// on the same domain shape is what keeps the ports from drifting.
///
/// Timestamps stay as the raw ISO-8601 strings the API sends. Parsing them into
/// `Date` here would force a formatting decision (locale, timezone, relative vs
/// absolute) into the domain, and that decision belongs to the screen.
public struct Studio: Identifiable, Hashable, Sendable {
  public let id: String
  public let slug: String
  public let name: String
  public let ownerId: String
  public let role: StudioRole
  public let createdAt: String?
  public let updatedAt: String?

  public init(
    id: String,
    slug: String,
    name: String,
    ownerId: String,
    role: StudioRole,
    createdAt: String? = nil,
    updatedAt: String? = nil
  ) {
    self.id = id
    self.slug = slug
    self.name = name
    self.ownerId = ownerId
    self.role = role
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}

/// Membership role.
///
/// The API sends these capitalised ("Owner"/"Editor"/"Viewer") — see
/// `presentStudioMembership` in weekclip-api. `.unknown` exists so a role added
/// server-side degrades to read-only instead of failing the whole list.
public enum StudioRole: Hashable, Sendable {
  case owner
  case editor
  case viewer
  case unknown

  /// Everything except viewing is gated on this.
  public var canEdit: Bool { self == .owner || self == .editor }

  public init(wire: String?) {
    switch wire?.lowercased() {
    case "owner": self = .owner
    case "editor": self = .editor
    case "viewer": self = .viewer
    default: self = .unknown
    }
  }
}
