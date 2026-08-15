import WeekclipShared

/// Studios for the dashboard, ordered the way the dashboard wants them.
///
/// This is the one thing a use case earns over calling the repository directly:
/// ordering is a product rule, and it would otherwise be duplicated into every
/// caller and re-decided differently each time. The repository stays a plain
/// pass-through of what the server sent.
///
/// Most recently touched first — what the web dashboard shows, and what
/// `GetStudiosUseCase` in weekclip-android does. The two clients sorting
/// differently would be a bug nobody files and everybody notices.
public struct GetStudios: Sendable {
  private let repository: any StudioRepository

  public init(repository: any StudioRepository) {
    self.repository = repository
  }

  public func callAsFunction() async -> Result<[Studio], AppError> {
    await repository.getStudios().map { studios in
      studios.sorted { lhs, rhs in
        // Nil sorts last: a studio with no timestamp is older than one with any.
        let left = lhs.updatedAt ?? ""
        let right = rhs.updatedAt ?? ""
        if left == right { return lhs.name < rhs.name }
        return left > right
      }
    }
  }
}
