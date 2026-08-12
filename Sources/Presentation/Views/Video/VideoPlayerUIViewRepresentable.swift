import SwiftUI
import AVKit

/// UIViewControllerRepresentable wrapper for AVPlayerViewController
struct VideoPlayerUIViewRepresentable: UIViewControllerRepresentable {
  let player: AVPlayer
  let viewModel: VideoPlayerViewModel

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    let controller = AVPlayerViewController()
    controller.player = player
    controller.showsPlaybackControls = false
    controller.videoGravity = .resizeAspect

    // Add tap gesture to toggle controls
    let tapGesture = UITapGestureRecognizer(
      target: context.coordinator,
      action: #selector(Coordinator.handleTap)
    )
    controller.view.addGestureRecognizer(tapGesture)

    return controller
  }

  func updateUIViewController(
    _ uiViewController: AVPlayerViewController,
    context: Context
  ) {
    // Update player if changed
    if uiViewController.player != player {
      uiViewController.player = player
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(viewModel: viewModel)
  }

  class Coordinator: NSObject {
    let viewModel: VideoPlayerViewModel

    init(viewModel: VideoPlayerViewModel) {
      self.viewModel = viewModel
    }

    @objc func handleTap() {
      viewModel.toggleControls()
    }
  }
}
