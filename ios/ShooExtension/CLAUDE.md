# ShooExtension — owner: lead

Safari Web Extension (EX-01 … EX-08). Swift handler + web files in `Resources/`.

- `Resources/detector.js` is GENERATED from `detector/` (Team AI). Never edit it here — run `detector/scripts/sync-to-extension.sh`.
- Content scripts can't use ES `import`. Every script in `manifest.json > content_scripts.js` shares one global scope, loaded in order.
- Page data sent anywhere must follow contracts/ (PageSnapshot, ScanResult). Never send typed input values.
- Native messages (`sendNativeMessage`) are defined in contracts/app-group-keys.md.
- Script order: `lists-client.js` → `detector.js` → `pipeline.js` → UI scripts (`pill.js`, `popup.js`, `marks.js`, `report.js`, `block.js`) → `snapshot.js` → `content.js` (last).
- C1 (#75): `snapshot.js` reads forms of the page plus up to 5 same-origin iframes (`contentDocument`), from the top frame only. No `all_frames`: the pipeline and UI run once per page. Cross-origin iframes are not read (Phase 2).
- Block screen (EX-06) is the extension page `blocked.html` (listed in `web_accessible_resources`), not an overlay — page scripts can't remove it. Data travels in the URL fragment (`ShooBlock.encode/decode`). UI listens with `ShooPipeline.subscribe(state => …)`.
- EX-07: `report.js` sends one result per page (blocked, or warning once all layers are done); `background.js` takes the screenshot (`capture.js`) and does the POST so it survives the block-screen navigation. Before it, `screenshotTargets` blurs text fields of the page and of same-origin iframes (nested, max depth 3) and hides iframes it can't look into (#75).
- Layer 1 (docs/design/blocklist.md): `lists.js` in background downloads `/blocklist` + `/public-blocklist` into `storage.local` (hourly / 6 h / full daily, alarms); `lists-client.js` gives content scripts `ShooLists.match(hostname)`. The visited URL never leaves the phone.
- EX-01: `heartbeat.js` (background) sends `{ type: "heartbeat", allSites }`; `allSites` = `browser.permissions.contains(<all_urls>)`. Sent from content scripts (throttled 1/min), on permission change (forced) and on the hourly alarm.
- C11: `last-seen.js` (background) rides along with the heartbeat: `PATCH /devices/me { extensionLastSeenAt }` max 1×/hour, last send kept in `storage.local`. Not onboarded → nothing sent; failure → retried next heartbeat.
- EX-08: `marks.js` shows one reason bubble on tap. Highlights have no element, so taps (`pointerdown`/`pointerup` on `document`, never cancelled) are hit-tested against the stored ranges; a struck field's label is a button. Text: only `TEXT_SIGNALS` (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`) are highlighted, and `reasonFor` picks the heaviest of them quoting the phrase (a new text signal must be added there, #74); field: `asks_*` by name/id, else `asks_<kind>`, else `mark_why_<kind>`.
- Every network call goes through `background.js` (content scripts run under the page's origin).
- `Resources/psl.js` is GENERATED — refresh with `scripts/update-psl.sh`, never edit by hand.
- Tests (Node, no device needed): `node --test ios/ShooExtension/Tests/*.test.mjs`. `Tests/` and `scripts/` are excluded from the bundle in `project.yml`.
