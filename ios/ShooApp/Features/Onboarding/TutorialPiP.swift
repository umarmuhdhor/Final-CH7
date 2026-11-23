import AVKit
import UIKit

/// ON-04 "Watch the tutorial": the video opens straight in Picture in Picture, so the steps stay on screen
/// while the user follows them in Shoo and in Settings. Needs `UIBackgroundModes: [audio]` (project.yml).
///
/// PiP needs an `AVPlayerLayer` in the window. This class adds a small host view, hidden from VoiceOver,
/// and starts PiP as soon as the player is ready. Where PiP can't run, `start` calls `fallback` and the
/// screen shows the full-screen `TutorialVideoPlayer` instead.
@MainActor
final class TutorialPiP: NSObject {
    static let shared = TutorialPiP()

    private var player: AVPlayer?
    private var hostView: PlayerHostView?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var fallback: (() -> Void)?
    private var restore: ((CMTime) -> Void)?
    private var video: TutorialVideo?
    /// Set by `willStart`: iOS took the start, so stop retrying.
    private var isStarting = false

    /// Starts the tutorial in PiP. `fallback` runs when PiP can't start; `restore` runs with the current
    /// time when the user taps "back to app" in the PiP window.
    func start(_ video: TutorialVideo, fallback: @escaping () -> Void, restore: @escaping (CMTime) -> Void) {
        guard let url = video.url,
              AVPictureInPictureController.isPictureInPictureSupported(),
              let window = Self.keyWindow() else {
            fallback()
            return
        }
        self.fallback = fallback
        self.restore = restore

        // Already playing: start again from the beginning, with this page's video.
        if let player, controller != nil {
            if self.video != video {
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                loopAtEnd(of: player)
                self.video = video
            }
            player.seek(to: .zero)
            player.play()
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            Log.app.error("Audio session for tutorial PiP failed", error)
        }

        let player = AVPlayer(url: url)
        player.isMuted = true  // the tutorial has no sound
        let host = PlayerHostView(frame: CGRect(x: 0, y: 0, width: 4, height: 4))
        host.playerLayer.player = player
        host.playerLayer.videoGravity = .resizeAspect
        host.isUserInteractionEnabled = false
        host.accessibilityElementsHidden = true
        window.addSubview(host)

        guard let controller = AVPictureInPictureController(playerLayer: host.playerLayer) else {
            host.removeFromSuperview()
            fallback()
            return
        }
        controller.delegate = self
        // Back-up: if the user leaves Shoo before PiP is up, iOS still moves the video into PiP.
        controller.canStartPictureInPictureAutomaticallyFromInline = true

        self.player = player
        self.hostView = host
        self.controller = controller
        self.video = video
        loopAtEnd(of: player)

        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { controller, _ in
            guard controller.isPictureInPicturePossible else { return }
            Task { @MainActor in
                self.possibleObservation = nil
                self.attemptStart(triesLeft: Self.startTries)
            }
        }
        player.play()
    }

    /// Loop: older users may need the steps more than once.
    private func loopAtEnd(of player: AVPlayer) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    /// `isPictureInPicturePossible` can turn true a moment before the controller accepts a start
    /// ("startPictureInPicture failed; status = 0"), so try a few times, then fall back to full screen.
    private static let startTries = 10
    private static let retryDelay: Duration = .milliseconds(150)

    private func attemptStart(triesLeft: Int) {
        guard let controller, !controller.isPictureInPictureActive, !isStarting else { return }
        controller.startPictureInPicture()
        Task { @MainActor in
            try? await Task.sleep(for: Self.retryDelay)
            guard let current = self.controller, current === controller,
                  !current.isPictureInPictureActive, !self.isStarting else { return }
            if triesLeft > 1 {
                self.attemptStart(triesLeft: triesLeft - 1)
            } else {
                Log.app.error("Tutorial PiP did not start; showing full screen")
                let fallback = self.fallback
                self.tearDown()
                fallback?()
            }
        }
    }

    /// Closes the PiP window and frees the player.
    func stop() {
        if let controller, controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            tearDown()
        }
    }

    private func tearDown() {
        player?.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        possibleObservation = nil
        hostView?.removeFromSuperview()
        hostView = nil
        controller = nil
        player = nil
        fallback = nil
        restore = nil
        video = nil
        isStarting = false
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.app.error("Audio session deactivation failed", error)
        }
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

extension TutorialPiP: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.isStarting = true }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            Log.app.error("Tutorial PiP failed to start", error)
            let fallback = self.fallback
            self.tearDown()
            fallback?()
        }
    }

    /// "Back to app" in the PiP window: carry on full screen from the same moment.
    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            let time = self.player?.currentTime() ?? .zero
            self.restore?(time)
            completionHandler(true)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in self.tearDown() }
    }
}

/// A view whose backing layer is the `AVPlayerLayer` PiP takes the video from.
private final class PlayerHostView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }  // swiftlint:disable:this force_cast
}
