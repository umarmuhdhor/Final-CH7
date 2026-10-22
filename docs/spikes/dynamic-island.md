# Spike: Dynamic Island from the Safari extension (EX-03)

**Question:** Can the running score appear in the Dynamic Island while the user browses in Safari?
**Fallback (PRD §10):** floating pill in-page.

## Paths to test
- [x] A. Extension (`SafariWebExtensionHandler`) calls `Activity.request` directly — **fails** (system rejects it, see below).
- [x] B. Extension updates an Activity the app started earlier — **fails** (extension can't see the app's Activity).
- [ ] C. Push-to-start / push updates via APNs from the server — not tested (needs backend endpoint + APNs key). See "Path C" below.
- [x] D. None works → in-page pill. **Chosen for MVP.**

## Result
- Works? **No** — not from the extension alone (A, B). Only C (server push) remains, untested.
- Path chosen: **D, in-page pill** for MVP (U6). C stays a Phase 2 option.
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
