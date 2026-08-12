import SwiftUI

/// Media list screen with 2-column grid
public struct MediaListView: View {
  let studioId: String
  let studioName: String
  @State private var viewModel: MediaListViewModel?

  private let gridColumns = [
    GridItem(.flexible(), spacing: 12),
    GridItem(.flexible(), spacing: 12),
  ]

  public var body: some View {
    ZStack {
      // Background
      Color(red: 0.95, green: 0.95, blue: 0.97)
        .ignoresSafeArea()

      VStack(spacing: 0) {
        if let viewModel = viewModel {
          if viewModel.isLoading {
            VStack(spacing: 12) {
              ProgressView()
              Text("Loading media...")
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if viewModel.mediaList.isEmpty {
            EmptyStateView(
              icon: "film",
              title: "No media",
              message: "This studio doesn't have any media yet"
            )
          } else {
            // Media grid
            ScrollView {
              LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(viewModel.mediaList) { media in
                  NavigationLink(destination: VideoPlayerView(
                    studioId: studioId,
                    mediaId: media.id,
                    mediaTitle: media.title
                  )) {
                    MediaGridItemView(media: media)
                  }
                  .buttonStyle(PlainButtonStyle())
                  .onAppear {
                    // Load more when scrolling to 80% of list
                    if shouldLoadMore(for: media) {
                      Task {
                        await viewModel.loadMore()
                      }
                    }
                  }
                }

                if viewModel.isLoadingMore {
                  ProgressView()
                    .frame(maxWidth: .infinity)
                    .gridCellUnsizedAxes(.horizontal)
                }
              }
              .padding(12)
            }
            .refreshable {
              await viewModel.refresh()
            }
          }

          if let error = viewModel.error {
            ErrorBannerView(error: error) {
              viewModel.clearError()
            }
            .padding(16)
          }
        }
      }
    }
    .navigationTitle(studioName)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if viewModel == nil {
        viewModel = MediaListViewModel(studioId: studioId)
        Task {
          await viewModel?.loadMedia()
        }
      }
    }
  }

  private func shouldLoadMore(for media: StudioMedia) -> Bool {
    guard let viewModel = viewModel else { return false }
    guard let lastIndex = viewModel.mediaList.firstIndex(where: { $0.id == media.id }) else {
      return false
    }
    let threshold = Int(Double(viewModel.mediaList.count) * 0.8)
    return lastIndex >= threshold
  }
}

// MARK: - Media Grid Item

struct MediaGridItemView: View {
  let media: StudioMedia

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ZStack(alignment: .bottomLeading) {
        // Thumbnail
        if let thumbnailUrl = media.thumbnailUrl {
          AsyncImage(url: URL(string: thumbnailUrl)) { image in
            image
              .resizable()
              .scaledToFill()
          } placeholder: {
            PlaceholderImageView()
          }
          .frame(height: 160)
          .clipped()
        } else {
          PlaceholderImageView()
            .frame(height: 160)
        }

        // Overlay with duration and status
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Spacer()

            // Status badge
            if media.status != .ready {
              HStack(spacing: 4) {
                if media.status == .processing {
                  ProgressView()
                    .scaleEffect(0.7)
                } else {
                  Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                }

                Text(media.status.rawValue.capitalized)
                  .font(.system(size: 11, weight: .semibold))
              }
              .foregroundStyle(.white)
              .padding(4)
              .background(statusBadgeColor)
              .cornerRadius(4)
            }
          }
          .padding(8)

          Spacer()

          // Duration at bottom left
          if let duration = media.duration {
            HStack(spacing: 4) {
              Image(systemName: "play.fill")
                .font(.system(size: 10))

              Text(formatDuration(duration))
                .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(6)
            .background(Color.black.opacity(0.6))
            .cornerRadius(4)
            .padding(8)
          }
        }
      }
      .cornerRadius(8)
      .clipped()

      // Title
      Text(media.title)
        .font(.system(size: 14, weight: .semibold))
        .lineLimit(2)

      // Meta info
      VStack(alignment: .leading, spacing: 4) {
        if let fileSize = media.fileSize {
          Text(formatFileSize(fileSize))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
        }

        if let createdAt = media.createdAt {
          Text(formatDate(createdAt))
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(8)
    .background(Color.white)
    .cornerRadius(8)
  }

  private var statusBadgeColor: Color {
    switch media.status {
    case .processing:
      return Color(red: 0.0, green: 0.5, blue: 1.0)
    case .failed:
      return Color(red: 1.0, green: 0.3, blue: 0.3)
    case .ready:
      return Color(red: 0.0, green: 0.7, blue: 0.3)
    case .archived:
      return Color(red: 0.5, green: 0.5, blue: 0.5)
    }
  }

  private func formatDuration(_ seconds: Int) -> String {
    let minutes = seconds / 60
    let secs = seconds % 60
    return String(format: "%d:%02d", minutes, secs)
  }

  private func formatFileSize(_ bytes: Int) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
  }

  private func formatDate(_ dateString: String) -> String {
    // Simple date formatting - can be enhanced
    return dateString.prefix(10).replacingOccurrences(of: "-", with: "/")
  }
}

#Preview {
  @Previewable @State var viewModel = MediaListViewModel(studioId: "1")

  let previewMedia = StudioMedia(
    id: "1",
    title: "Opening Ceremony",
    studioId: "1",
    thumbnailUrl: nil,
    duration: 1234,
    status: .ready
  )
  viewModel.mediaList = [previewMedia]

  return MediaListView(studioId: "1", studioName: "Apple Event 2024")
}
