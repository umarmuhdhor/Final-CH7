# Shoo for Android

Native Android version of Shoo (Kotlin + Jetpack Compose), a 1:1 port of the iOS app (`ios/ShooApp`): same screens,
layout numbers, colours, images, copy (EN + ID, from `Localizable.xcstrings`), flows and motion. Browsing is checked
by the **Shoo add-on in Firefox for Android**, built from the Safari extension (Chrome on Android has no extensions).
Porting rules: [PORTING.md](PORTING.md).

```
Shoo app (Android)                         Firefox for Android
  every iOS screen (Onboarding, Home,        Shoo add-on = the Safari extension
  Activity, Detail, Pairing, Profile)         (ios/ShooExtension/Resources) + firefox-addon/overlay
        │                                            │
        │  one-time 6-digit code, 127.0.0.1:47613    │
        └──────────── session (getSession) ─────────►│
        ▼                                            ▼
    shoo-api  ◄────── /scans /verdicts /blocklist ───┘   (+ shoo-ai /analyze in release)
```

| Folder | What |
|---|---|
| `app/src/main/java/com/shoo/app/` | `app/`, `data/`, `support/`, `components/`, `features/*` mirror `ios/ShooApp/{App,Data,Support,Components,Features}` file by file |
| `app/src/main/res/drawable-*` | the iOS images, converted by `scripts/sync-ios-assets.mjs` (never edit by hand) |
| `app/src/main/l10n/android*.xcstrings` | Android-only copy (Firefox instead of Safari, Android wording); all other copy comes from the iOS catalog at build time |
| `bridge/AddonBridge.kt` | hands the session to the add-on, replacing Safari's native messaging |
| `firefox-addon/` | `build.mjs` copies the Safari extension, writes a Firefox manifest, swaps `sendNativeMessage` for `overlay/native-bridge.js`, adds the settings page |

## What is not identical, and why

- **Font**: Inter instead of SF Pro (Apple licence). **Icons**: Material Symbols instead of SF Symbols (Apple licence).
- **Safari steps → Firefox steps**: same screens and layout; the copy describes Firefox. The ON-04 / Safari-default
  illustrations still show Safari until Firefox artwork exists.
- **Push**: the backend speaks APNs only; the Guardian's phone polls `GET /scans` (~15 min) and notifies locally until FCM.
- **Glass and blur**: Android can't blur what lies behind a view, so iOS Liquid Glass and materials are frosted fills.
- **System UI**: alerts, share sheet, permission prompts and time pickers are Android's own.
- **Status bar**: iPhone's safe area is ~62 pt, Android's ~24 dp, so screens sit higher on the screen.
- **"Pages checked" count** stays "—": the add-on can't write the app's storage.
- **Motion**: every SwiftUI animation was checked against its Compose port; see [MOTION-PARITY.md](MOTION-PARITY.md) for what matches and what is approximated (sheets, navigation push, symbol effects).

## Build and run

Needs the Android SDK (platform 35) and a JDK 17–24 (Gradle 8.14 does not run on 25).

```bash
cd android && ./gradlew :app:assembleDebug
```

```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
```

Debug builds run on the Mock backend (`contracts/fixtures`) and accept iOS launch arguments as string extras, e.g.
`adb shell am start -n com.shoo.app.debug/com.shoo.app.MainActivity --es -mock.scenario figma --es -UITestSkipSplash YES`.
`--es -debug.backend cloud` (or `local`, `wrangler dev` at `10.0.2.2:8787`) uses a real API. A debug APK is not
optimised; on an emulator `adb shell cmd package compile -m speed -f com.shoo.app.debug` makes the first launch fast.

## The Firefox add-on

```bash
node android/firefox-addon/build.mjs
```

Writes `android/firefox-addon/build/shoo-firefox/` (gitignored). Until it is on addons.mozilla.org, install it with
[web-ext](https://github.com/mozilla/web-ext): turn on Firefox Settings → Remote debugging via USB, then

```bash
npx web-ext run -t firefox-android --android-device <adb serial> --firefox-apk org.mozilla.firefox --source-dir android/firefox-addon/build/shoo-firefox
```

Link it from the app (onboarding step "Aktifkan Ekstensi", or Profile → Perlindungan): the app shows a 6-digit code;
in Firefox open menu ⋮ → Extensions → Shoo → Settings and enter it. The app listens on 127.0.0.1 only while the code
is shown (10 minutes at most), refuses website origins, sends no CORS headers and stops after 5 wrong codes.

## Test

```bash
cd android && ./gradlew :app:testDebugUnitTest
```

```bash
node --test android/firefox-addon/test/*.test.mjs android/scripts/test/*.test.mjs
```

## Not done yet

- FCM push, App Links (`assetlinks.json` on the Worker), the add-on on addons.mozilla.org, release signing.
- Firefox artwork for the extension illustrations.
- A browser inside the app (links from WhatsApp/SMS open in Shoo's own WebView), so Firefox becomes optional.
