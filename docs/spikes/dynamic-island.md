# Spike: Dynamic Island from the Safari extension (EX-03)

**Question:** Can the running score appear in the Dynamic Island while the user browses in Safari?
**Fallback (PRD §10):** floating pill in-page.

## Paths to test
- [x] A. Extension (`SafariWebExtensionHandler`) calls `Activity.request` directly — **fails** (system rejects it, see below).
- [x] B. Extension updates an Activity the app started earlier — **fails** (extension can't see the app's Activity).
- [x] C. Push-to-start / push updates via APNs from the server — **chosen 10 Nov** (#49). Built: contract #357/#359, backend #356, extension + island #358. App token registration (Alief) and the device test still open.
- [x] D. None works → in-page pill. MVP choice until C; stays the offline, instant signal next to the island.
- [x] E. App relays the extension's score (App Group + Darwin notification) to an Activity the app started — **works, but dead end** (9–10 Nov, see below).

## Result
- Works? Not from the extension alone (A, B). Through the app (E) yes, but only after the user opened Shoo. Without opening Shoo: only C.
- Path chosen: **C, server push** (#49, decision 10 Nov), for every page while the online check is on. Forwarded, never stored. The pill (D) stays.
- Latency per update: n/a (A/B never reach the Dynamic Island).
- Tested: 22 Oct 2026, iPhone 17 (Dynamic Island), Xcode 26.6, paid team, Debug build. Spike code: local branch `spike/EX-03-dynamic-island` (not merged; path B needed a temporary line in `ShooApp`).

### Evidence (device syslog, `pymobiledevice3 syslog live`)

**A — extension calls `Activity.request`.** Compiles fine in the extension target, but `liveactivitiesd` treats the extension as its own app and refuses:

```
ShooExtension{ActivityKit}: Requesting an activity: ["Attributes type: ScoreActivityAttributes", ...]
liveactivitiesd{SessionCore} <ERROR>: App does not exist: com.<bundle>.extension
liveactivitiesd{SessionCore} <ERROR>: Target does not include NSSupportsLiveActivities key in its Info.plist widget(containingProcess: com.<bundle>.extension)
```

Adding `NSSupportsLiveActivities: true` to the extension's Info.plist changes nothing — same two errors. The first one ("App does not exist") is the blocker.

**B — app starts the Activity, extension updates it.** The app starts it without problems:

```
Shoo{ActivityKit}: Requesting an activity ...
liveactivitiesd{SessionCore}: Requester is foreground
liveactivitiesd{SessionCore}: Activity started: 76985EF3-...
```

But in the extension process `Activity<ScoreActivityAttributes>.activities` is empty while that Activity is still running:

```
ShooExtension{ActivityKit}: Fetched descriptors for content states: []
```

So the extension has nothing to update, falls back to `request`, and gets the same errors as A. Activities are scoped to the requesting bundle; the app and its Safari extension don't share them.

### Path C (not tested) — what it would take
1. App (foreground, e.g. on launch) registers `Activity.pushToStartTokenUpdates` (iOS 17.2+) and sends the token to the backend.
2. On each score change the extension calls a new endpoint (e.g. `POST /live`) → backend sends APNs `liveactivity` pushes (start, then updates via the Activity's own push token).
3. Costs: a new endpoint + APNs Live Activity pushes (Alief), a contract change, the domain + score leave the phone on every page (privacy review), and APNs throttles frequent updates unless `NSSupportsLiveActivitiesFrequentUpdates`. Score must stay correct when the server is down (MVP rule 3), which the pill gives for free.

### Side findings
- **U7 / onboarding:** turning the extension on in Settings doesn't make the app show On. `extensionLastSeenAt` is written only when a page loads in Safari after permission is granted. Onboarding should tell the user to open one website after enabling Shoo (Alief, ON-*).
- **L0 / C3:** a paid team signs all three targets with App Groups + Push via `Local.xcconfig`, no `project.yml` change.

## Path E (9–10 Nov) — app relay, not merged
Tried on `spike/EX-03-dynamic-island-score` (deleted after #358; nothing of it merged except the island UI).
- Flow: `live-island.js` → background → native message `liveScore` → App Group + Darwin notification → the app (`LiveScoreRelay`) → `Activity.update`. Worked on an iPhone 17: island updated on page open, emptied ~1.5 s after leaving Safari, came back on return.
- **Dead end 1:** `Activity.request` from the background is refused with `ActivityAuthorizationError.visibility` (simulator, iOS 26). The app has to be on screen to start the Activity, so the user must open Shoo first. That's what the user did not want.
- **Dead end 2:** a suspended or killed app never sees the Darwin notification. Keeping it alive needed a silent `AVAudioEngine` under `UIBackgroundModes: audio`, an App Store risk (guideline 2.5.4). After a reboot, a swipe-away or the 8 h limit, nothing shows until Shoo is opened again.
- **Side effect:** a running but "hidden" Activity still leaves an empty card on the lock screen, and a long-press opens an empty island.
- **Test note:** with two Shoo builds on one iPhone (`com.umarmuhdhor.shoo` and `com.aliefauzan.shoo`), Safari lists two "Shoo" extensions. Only the one of the build under test must be on.

## Path C as built (#49)
- Contract: contracts/api.md "Live score (Dynamic Island)". Extension `POST /live` → backend → APNs `liveactivity` start / update / end. `content-state` = `ScoreActivityAttributes.ContentState`.
- Remaining: the app sends `pushToStartTokenUpdates` and the update token, and ends older activities (Alief). Then the device test: delay on Wi-Fi/4G, fast tab switching, island after a reboot without opening Shoo. Use a TestFlight build, or point the backend at sandbox APNs for a Debug build.
