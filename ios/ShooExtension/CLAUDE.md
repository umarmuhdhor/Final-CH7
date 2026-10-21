# ShooExtension — owner: lead

Safari Web Extension (EX-01 … EX-08). Swift handler + web files in `Resources/`.

- `Resources/detector.js` is GENERATED from `detector/` (Team AI). Never edit it here — run `detector/scripts/sync-to-extension.sh`.
- Content scripts can't use ES `import`. Every script in `manifest.json > content_scripts.js` shares one global scope, loaded in order.
- Page data sent anywhere must follow contracts/ (PageSnapshot, ScanResult). Never send typed input values.
- Native messages (`sendNativeMessage`) are defined in contracts/app-group-keys.md.
