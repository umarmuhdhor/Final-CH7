# android/ — rules

Native Android app (Kotlin + Jetpack Compose) and the Firefox for Android add-on build. How to build, run and
test: [README.md](README.md).

Owner: Team App (Alief), until the lead confirms it in the root CLAUDE.md table.

- Same contracts as iOS: every JSON matches `contracts/`. The Mock backend reads `contracts/fixtures/` (copied into
  the APK at build time, never edited here).
- Light on purpose: no networking, JSON, DI or navigation library. `HttpURLConnection` + `org.json`, Keystore for
  the token, `JobScheduler` for the Guardian check. Add a dependency only when the platform can't do it.
- Strings: `res/values/` is Bahasa Indonesia (default, like iOS), `res/values-en/` English. Add both.
- `firefox-addon/` builds the add-on from the Safari extension (`ios/ShooExtension/Resources/`, lead-owned). Never
  edit those files from here: change `overlay/` or `build.mjs`. `test/addon.test.mjs` fails when the Safari
  `background.js` no longer has the native calls `native-bridge.js` answers.
- The add-on bridge (`bridge/AddonBridge.kt`) listens on 127.0.0.1 only while a code is on screen. Never widen
  that: no other routes, no CORS headers, no website origins, never log the token.
- Debug builds never send pages to the AI Worker (`AI_URL` empty), like iOS #82.
- Tests: `./gradlew :app:testDebugUnitTest` and `node --test android/firefox-addon/test/*.test.mjs`.
