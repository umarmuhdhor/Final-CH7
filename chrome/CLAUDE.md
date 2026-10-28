# chrome/ — owner: lead

Chrome (MV3) version of the Safari extension. How to build, load and test: [README.md](README.md).

- Load `extension/` unpacked. No build step except `scripts/sync.sh`.
- `extension/detector.js` and every file in `scripts/shared-files.txt` are copies: change them in `detector/` or
  `ios/ShooExtension/Resources/`, then run `scripts/sync.sh`. Never edit them here (`test/sync.test.mjs` fails).
- `popup.js`, `pill.js`, `blocked.*` are hand-made Chrome copies of the Safari UI (no Shoo-app deep links).
  Port Safari UI changes to them by hand; keep the pure logic (`decide`, `layoutFor`, `describe`, `viewFor`) the same.
- Shared scripts call `browser.*`: content scripts and `blocked.html` load `browser-shim.js` first. In the service
  worker use `chrome.*` and register listeners at top level; answer messages through `messaging.js` (Chrome
  ignores a Promise returned from `onMessage`).
- No server call without a session (`session.js`). There is no pairing on Chrome; the dev session is for local
  testing only. Never add a token, base URL or new endpoint to the extension; JSON must match `contracts/`.
- Same rules as `ios/ShooExtension/CLAUDE.md` for anything shared: no typed input values leave the page, the
  full URL never leaves the browser (`shareableUrl`), replies to content scripts never carry the token.
- Tests: `node --test chrome/test/*.test.mjs`. Real browser: `node chrome/test/e2e/screens.mjs` (README).
