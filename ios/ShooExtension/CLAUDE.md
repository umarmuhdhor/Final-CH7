# ShooExtension — owner: lead

Safari Web Extension (EX-01 … EX-08). Swift handler + web files in `Resources/`.

- `Resources/detector.js` is GENERATED from `detector/` (Team AI). Never edit it here — run `detector/scripts/sync-to-extension.sh`.
- Content scripts can't use ES `import`. Every script in `manifest.json > content_scripts.js` shares one global scope, loaded in order.
- Page data sent anywhere must follow contracts/ (PageSnapshot, ScanResult). Never send typed input values.
- Native messages (`sendNativeMessage`) are defined in contracts/app-group-keys.md.
- Script order: `detector.js` → `pipeline.js` → UI scripts → `content.js` (last). UI listens with `ShooPipeline.subscribe(state => …)`.
- Every network call goes through `background.js` (content scripts run under the page's origin).
- `Resources/psl.js` is GENERATED — refresh with `scripts/update-psl.sh`, never edit by hand.
- Tests (Node, no device needed): `node --test ios/ShooExtension/Tests/*.test.mjs`. `Tests/` and `scripts/` are excluded from the bundle in `project.yml`.
