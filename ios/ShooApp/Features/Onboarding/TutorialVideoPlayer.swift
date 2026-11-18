import AVKit
import SwiftUI

/// ON-04 "Still can't? Watch the video": full-screen player. The link opens the video in PiP first
/// (`TutorialPiP`); this player is the fallback where PiP can't run, and where "back to app" in the PiP
/// window lands (`startTime` = the moment PiP was at).
struct TutorialVideoPlayer: View {
    @Environment(\.dismiss) private var dismiss
    var startTime: CMTime = .zero

    /// Silent 64 s screen recording of the real enable flow, 1080 x 1080 so the text stays readable in PiP.
    /// Source: `.video/` HyperFrames project (not in git).
    static let videoURL = Bundle.main.url(forResource: "onboarding-tutorial", withExtension: "mp4")

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if let url = Self.videoURL {
                PlayerController(url: url, startTime: startTime)
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
    let startTime: CMTime

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        do {
            // Needed for Picture in Picture; switched off again when the player closes.
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        } catch {
            Log.app.error("Audio session for tutorial video failed", error)
        }
        let controller = AVPlayerViewController()
        let player = AVPlayer(url: url)
        player.seek(to: startTime)
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.delegate = context.coordinator
        player.play()
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
