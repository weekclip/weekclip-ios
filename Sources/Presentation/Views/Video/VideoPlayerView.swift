import SwiftUI
import AVFoundation
import WeekclipDomain

/// Main video player screen
public struct VideoPlayerView: View {
  let studioId: String
  let mediaId: String
  let mediaTitle: String

  @State private var viewModel: VideoPlayerViewModel?
  @State private var isLandscape = false
  @Environment(\.horizontalSizeClass) var horizontalSizeClass
  @Environment(\.verticalSizeClass) var verticalSizeClass

  public init(
    studioId: String,
    mediaId: String,
    mediaTitle: String
  ) {
    self.studioId = studioId
    self.mediaId = mediaId
    self.mediaTitle = mediaTitle
  }

  public var body: some View {
    ZStack {
      Color.black
        .ignoresSafeArea()

      if let viewModel = viewModel {
        ZStack {
          // Poster image while loading
          if viewModel.isBuffering, let posterUrl = viewModel.posterImageUrl {
            AsyncImage(url: posterUrl) { image in
              image
                .resizable()
                .scaledToFit()
            } placeholder: {
              Color.gray.opacity(0.3)
            }
          }

          // AVPlayerViewController
          VideoPlayerUIViewRepresentable(player: viewModel.player, viewModel: viewModel)
            .onAppear {
              // Handle fullscreen on orientation change
              updateOrientationState()
            }

          // Custom controls overlay
          VideoControlsOverlay(viewModel: viewModel, mediaTitle: mediaTitle)
            .ignoresSafeArea()

          // Error display
          if let error = viewModel.error {
            VStack(spacing: 16) {
              Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

              Text("Video Playback Error")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

              Text(error.localizedDescription)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

              Button(action: { viewModel.clearError() }) {
                Text("Dismiss")
                  .font(.system(size: 16, weight: .semibold))
                  .foregroundStyle(.white)
                  .frame(maxWidth: .infinity)
                  .padding(12)
                  .background(Color.blue)
                  .cornerRadius(8)
              }
              .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.7))
          }
        }
      } else {
        VStack(spacing: 16) {
          ProgressView()
            .tint(.white)

          Text("Loading video...")
            .foregroundStyle(.white.opacity(0.7))
        }
      }
    }
    .navigationBarHidden(true)
    .onAppear {
      if viewModel == nil {
        viewModel = VideoPlayerViewModel(studioId: studioId, mediaId: mediaId)
        Task {
          await viewModel?.loadMediaFromAPI()
        }
      }
    }
    .onDisappear {
      viewModel?.pause()
    }
  }

  private func updateOrientationState() {
    let isLandscape = UIDevice.current.orientation.isLandscape
    withAnimation {
      self.isLandscape = isLandscape
    }
  }
}

#Preview {
  VideoPlayerView(studioId: "1", mediaId: "1", mediaTitle: "Sample Video")
}
