# Shoo for Chrome

Chrome (Manifest V3) version of the Shoo Safari Web Extension: same scan pipeline, same score bands, same
Figma design ("UI Pop Up Safari", from the Safari PRs #160 popup and #161 block screen), EN + ID.

| Score | What you see |
|---|---|
| < 30 | Only the live score bubble (EX-03) |
| 30–49 | Mini card at the bottom: ring, "Be careful / Waspada", top reason + advice, × closes it |
| 50–79 | Sheet over a dimmed page: "Leave this page" goes back, "Continue anyway" (or a click on the page) shrinks it to the mini card |
| ≥ 80 | The tab moves to the extension's own `blocked.html` (ring, reasons, "Back to a safe page"). Websites can't script that page, so the block can't be removed |

On Chrome only layers 1–2 run, on the device: the detector reads the URL (brand look-alikes, cheap TLDs,
the link dissector). Nothing leaves the browser.

## Layout

```
chrome/
  extension/      ← load this folder unpacked
  scripts/sync.sh ← refreshes the files shared with Safari + builds detector.js
  test/           ← node --test (unit), test/e2e/screens.mjs (real browser)
```

Files in `extension/`:

- **Chrome only**: `manifest.json`, `background.js` (service worker), `router.js` (message types), `messaging.js`
  (promise handler → `sendResponse`), `session.js` (server seam), `browser-shim.js` (`browser` = `chrome`),
  `_locales/`, `images/`.
- **Chrome copies of Safari UI** (edited by hand; no "See detail" / "Review in Shoo" / "Open Shoo", since
  there's no Shoo app to open): `popup.js` (from PR #160), `pill.js`, `blocked.html`, `blocked.css`,
  `blocked-page.js` (from PR #161). When the Safari versions change, port the change here.
- **Generated / shared, never edit here**: `detector.js` (built from `detector/`) and every file in
  `scripts/shared-files.txt` (copied unchanged from `ios/ShooExtension/Resources/`). `test/sync.test.mjs`
  fails when one drifts.

## Build

Nothing to compile. After `detector/` or a shared Safari file changes:

```bash
chrome/scripts/sync.sh
```

Commit the result.

## Load in Chrome

1. Open `chrome://extensions`, turn on **Developer mode**.
2. **Load unpacked** → pick `chrome/extension/`.
3. Visit any http(s) page. The bubble shows the score.

UI language follows Chrome's language (Settings → Languages): Indonesian → ID text, anything else → EN.

## Test

```bash
node --test chrome/test/*.test.mjs
```

Covers the manifest (files exist, script order, web-accessible resources, EN/ID keys), the shared-file
sync, the message router, the Chrome `onMessage` adapter, the session seam, popup tiers, the block screen
view, and that the demo URLs below land in their band.

Real browser check (screenshots of every band, EN and ID, at 1280×800; fails on any page or service-worker
console error):

```bash
cd chrome && npm install --no-save playwright-core && npx playwright-core install chromium && cd ..
node chrome/test/e2e/screens.mjs /tmp/shoo-screens
```

### Demo URLs

`test/fixtures/demo-urls.json` has fake scam-looking hosts for each band (40% mini card, 56% sheet, 82% block
screen). They don't exist on the internet: the e2e script points Chromium at a local proxy that answers
every request with a plain login page. To try them by hand, run any local proxy that does the same and start
Chrome with `--proxy-server=…` (and `--disable-features=HttpsUpgrades` since the hosts are http only).

## Server seam (off by default)

Safari gets a session (device token, API/AI base URLs, Guardian/Protected mode) from the Shoo iPhone app
over native messaging. Chrome has no app and no pairing yet, so `session.js` returns no session and:
no `/analyze` (layers 3–4), no `GET /verdicts`, no `/blocklist` + `/public-blocklist` downloads (layer 1).

For development against a local backend, store a session with the `getSession` shape
(`contracts/app-group-keys.md`) from the service worker console (`chrome://extensions` → Shoo → service worker):

```js
chrome.storage.local.set({ "shoo.devSession": {
    token: "<device token>", apiBaseURL: "http://localhost:8787", aiBaseURL: "http://localhost:8788",
    mode: "protected", guardianName: "Rina" } });
```

Then layer 1 lists, layers 3–4 and verdict polling on the block screen work like Safari. Remove it with
`chrome.storage.local.remove("shoo.devSession")`. Never ship a token in the extension.

## Not supported yet (vs Safari)

- **Pairing / session**: no way for a Chrome user to join a family. How Chrome should pair is an open product
  decision; until then layers 1 (lists) and 3–4 (`/analyze`) and verdicts only run with a dev session.
- **EX-07 reports** (`POST /scans` + blurred screenshot): `report.js` / `capture.js` aren't included, so
  nothing reaches the guardian's Activity.
- **Deep links into the app**: no "See detail" (popup, bubble card) and no "Review in Shoo" / "Open Shoo" on
  the block screen.
- **EX-01 heartbeat / C11 last seen**: answered as `skipped: "no_app"`.
- **Blocking before the page shows**: like Safari, the scan runs at `document_idle`, so a ≥ 80 page is visible
  for a moment before the block screen. Chrome could block earlier (`webNavigation` / `declarativeNetRequest`)
  for layer 1 matches; not done.
- `file://` pages and Chrome's own pages aren't scanned.
