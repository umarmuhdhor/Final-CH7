import UIKit
import UserNotifications

/// APNs token (ON-05) and notification taps (GD-06). Owns the environment, so a tap that launched the
/// app is routed before the first screen appears.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let environment = AppEnvironment.live(registerForPush: { UIApplication.shared.registerForRemoteNotifications() })

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Log.app.info("APNs token received")
        Task { await environment.pushTokenReceived(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Without the Push capability (or offline) there is no token: Shoo works, only without pushes.
        Log.app.error("APNs registration failed", error)
    }

    // The completion-handler forms, not the `async` ones: the `async` form's generated completion ran off the
    // main thread and UIKit asserted (crash on a tap from the background, D-alief-C17). `nonisolated` because
    // the center may call from any queue; the work and the completion run on the main actor.

    /// A push while Shoo is open still shows as a banner; the Guardian taps it like any other (C15).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            completionHandler(environment.showsPushBanner ? [.banner, .list, .sound] : [])
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let scanId = NotificationRouter.scanId(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            if isTap { environment.openPush(scanId: scanId) }
            completionHandler()
        }
    }
}
