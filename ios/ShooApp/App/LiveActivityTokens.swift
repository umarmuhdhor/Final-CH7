import ActivityKit
import Foundation
import UIKit

/// EX-03 (#49): hands the backend the Dynamic Island's two APNs tokens, so `POST /live` from the extension can
/// start, update and end the island by push (contracts/api.md "Live score (Dynamic Island)", app side).
///
/// - Start token: `pushToStartTokenUpdates` (iOS 17.2+). Sent at every launch and again when it changes.
///   Without it the backend answered `no_start_token` to every `/live` and the island never appeared
///   (QA 2026-11-10 #5).
/// - A new activity (also one a `start` push created while Shoo was closed): every other Shoo island ends
///   at once, then its update token is sent. When it ends: `liveActivityUpdateToken: null`.
///
/// Tokens are hex, never logged. Nothing is stored on disk: iOS hands the tokens out again after a relaunch.
@MainActor
final class LiveActivityTokens {
    private let send: @MainActor (DeviceUpdate) async throws -> Void
    private let canSend: @MainActor () -> Bool
    private var tasks: [Task<Void, Never>] = []
    private var watched: Set<String> = []
    /// The last start token iOS gave and whether this device's server record has it.
    private var startToken: String?
    private var startTokenSent = false

    init(canSend: @escaping @MainActor () -> Bool, send: @escaping @MainActor (DeviceUpdate) async throws -> Void) {
        self.canSend = canSend
        self.send = send
    }

    /// Once, at launch. Safe to call again: only the first call starts watching.
    func start() {
        guard tasks.isEmpty else { return }
        if #available(iOS 17.2, *) {
            tasks.append(Task { [weak self] in
                for await data in Activity<ScoreActivityAttributes>.pushToStartTokenUpdates {
                    await self?.startTokenChanged(NotificationRouter.hex(token: data))
                }
            })
        }
        tasks.append(Task { [weak self] in
            for await activity in Activity<ScoreActivityAttributes>.activityUpdates {
                await self?.adopt(activity)
            }
        })
        for activity in Activity<ScoreActivityAttributes>.activities { adopt(activity) }
    }

    /// A new device on the server (registration, guardian → protected): its record has no tokens yet.
    func deviceChanged() {
        startTokenSent = false
        Task { await sendStartTokenIfNeeded() }
    }

    /// Every activation: a send that failed (offline, before onboarding) goes out now.
    func sync() async {
        await sendStartTokenIfNeeded()
    }

    private func startTokenChanged(_ hex: String) async {
        guard hex != startToken else { return }
        startToken = hex
        startTokenSent = false
        await sendStartTokenIfNeeded()
    }

    private func sendStartTokenIfNeeded() async {
        guard let token = startToken, !startTokenSent, canSend() else { return }
        startTokenSent = true
        // iOS hands out a new start token after each start push, often while Shoo is in the background.
        let background = UIApplication.shared.beginBackgroundTask(withName: "LiveActivityStartToken")
        defer { UIApplication.shared.endBackgroundTask(background) }
        do {
            try await send(DeviceUpdate(liveActivityStartToken: .set(token)))
        } catch {
            if startToken == token { startTokenSent = false }
            guard !error.isCancellation else { return }
            Log.app.error("Live Activity start token sync failed", error)
        }
    }

    private func adopt(_ activity: Activity<ScoreActivityAttributes>) {
        // One island follows the page: the newest wins, the others go at once. "Newest" is the latest
        // stale date (every start/update push sets one), never the arrival order: a background launch by a
        // start push lists the old island and the new one together, in no fixed order, and ending "every
        // other one" for each of them ended the new island too (device test 2026-11-12).
        var all = Activity<ScoreActivityAttributes>.activities
        if !all.contains(where: { $0.id == activity.id }) { all.append(activity) }
        guard let newest = all.max(by: { Self.staleDate($0) < Self.staleDate($1) }) else { return }
        for other in all where other.id != newest.id {
            Task { await other.end(nil, dismissalPolicy: .immediate) }
        }
        guard activity.id == newest.id, !watched.contains(activity.id) else { return }
        watched.insert(activity.id)
        let id = activity.id
        tasks.append(Task { [weak self] in
            for await data in activity.pushTokenUpdates {
                await self?.sendUpdate(.set(LiveActivityUpdateToken(activityId: id, token: NotificationRouter.hex(token: data))))
            }
        })
        tasks.append(Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .ended || state == .dismissed {
                await self?.ended(id)
                return
            }
        })
    }

    private static func staleDate(_ activity: Activity<ScoreActivityAttributes>) -> Date {
        activity.content.staleDate ?? .distantPast
    }

    private func ended(_ id: String) async {
        watched.remove(id)
        // Another island already took over: its token is the one the backend should keep.
        guard watched.isEmpty else { return }
        await sendUpdate(.clear)
    }

    private func sendUpdate(_ token: Clearable<LiveActivityUpdateToken>) async {
        guard canSend() else { return }
        // Shoo is often woken in the background only to hand over this token (a start push while Safari is
        // on screen) and suspended right after: without the extra time the PATCH never left the phone.
        let background = UIApplication.shared.beginBackgroundTask(withName: "LiveActivityToken")
        defer { UIApplication.shared.endBackgroundTask(background) }
        do {
            try await send(DeviceUpdate(liveActivityUpdateToken: token))
        } catch {
            guard !error.isCancellation else { return }
            Log.app.error("Live Activity update token sync failed", error)
        }
    }
}
