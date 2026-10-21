# detector/ — owner: Team AI

On-device detection, layer 1 (database) + layer 2 (link name). Runs inside the Safari extension on the iPhone.
Interface is fixed by contracts/detector-interface.md — read it first.

- Output: one plain script defining `globalThis.ShooDetector = { version, analyzeLocal }`. No ES modules, no `import` at runtime.
- `analyzeLocal(snapshot)` returns `Signal[]` (contracts/scan-result.schema.json). Never throws; returns `[]` on error. Target < 50 ms.
- Signal ids must come from the "Known signal ids" table. New id = contract PR to the lead.
- Every signal needs `label` (Guardian) and `labelSimple` (Protected, plain words), each as `{ en, id }` — English AND Bahasa Indonesia.
- After changing `src/`, run `scripts/sync-to-extension.sh` and commit both `src/` and the generated `ios/ShooExtension/Resources/detector.js`.
- Write tests for every rule (e.g. "p0stindonesia.com" → `lookalike_domain`, "tokopedia.com" → no signals).
- Don't touch anything outside `detector/` except the generated `detector.js`.
