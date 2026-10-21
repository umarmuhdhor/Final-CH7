import AVKit
import SwiftUI

/// ON-04 "Still can't? Watch the video": full-screen player with Picture in Picture, so the video can
/// keep playing over Settings. PiP outside the app also needs `UIBackgroundModes: [audio]` (TODO C3 item 4);
/// without it the video plays inside the app only.
struct TutorialVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss

    // TODO(sync:umar): ON-04 tutorial video from PM — replace after C15
    static let videoURL = Bundle.main.url(forResource: "onboarding-tutorial-placeholder", withExtension: "mp4")

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = Self.videoURL {
                PlayerController(url: url)
                    .ignoresSafeArea()
            } else {
                Text("The video isn't available right now.")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(32)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.6), in: Circle())
            }
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("video.close")
            .padding(16)
        }
    }
}

private struct PlayerController: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        do {
            // Needed for Picture in Picture; switched off again when the player closes.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            Log.app.error("Audio session for tutorial video failed", error)
        }
        let controller = AVPlayerViewController()
        controller.player = AVPlayer(url: url)
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        controller.player?.pause()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.app.error("Audio session deactivation failed", error)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        /// Back from PiP: the player is still on screen over ON-04, so just finish the restore.
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}
