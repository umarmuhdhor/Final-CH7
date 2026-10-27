# detector/ — owner: Lead (taken over from Team AI, 23 Oct 2026)

On-device detection, layer 1 (database) + layer 2 (the link). Runs inside the Safari extension on the iPhone.
Interface is fixed by contracts/detector-interface.md — read it first.

- Output: one plain script defining `globalThis.ShooDetector = { version, analyzeLocal }`. No ES modules, no `import` at runtime.
- `analyzeLocal(snapshot)` returns `Signal[]` (contracts/scan-result.schema.json). Never throws; returns `[]` on error. Target < 50 ms.
- **No network calls.** Layer 1 (database) comes from `await globalThis.ShooLists?.match(hostname)` (provided by the extension, see contracts/detector-interface.md + docs/design/blocklist.md). Mock it in tests; handle it being absent.
- **Layer 2 has two parts that add up** (#140): (A) brand check on the host name against `data/brands.json` (`lookalike_domain`, `brand_plus_keyword`, `cheap_tld`), and (B) the whole-link dissector `dissectLink` (`suspicious_link`). It reads the **whole URL** (scheme, userinfo, host, TLD, port, path, file extension, trailing slash, query, fragment, length); each part scores on its own, capped at 25. On free hosting (blogspot, github.io, cloudfront…) the domain belongs to the platform, so the first label and the file name are judged instead. Data lives in `data/link-rules.json` (free hosts, bait words, carriers, rare TLDs).
- `suspicious_link` rules: one signal per page; weight = raw score **capped at 29** (the link alone may open the LLM gate but never the popup at 30); not emitted below 10; `brands.json` cheap TLDs are scored by `cheap_tld` only (never twice); private/loopback addresses are skipped. Weights are starting values, not calibrated on real scams (D-imelda-45): do not tune them to pass one sample, add the sample to `ai/eval/` first.
- `evidence`: layer 1–2 is free-form (`db_match` → `hit.source`); never typed values. `suspicious_link` evidence is a list of **reason codes** (`random_name,slash_after_file`), never pieces of the URL: it travels to `/analyze` inside `localSignals` and the raw URL must not leave the phone (#97). Labels use only our own phrases (`REASON_TEXT`).
- Signal ids must come from the "Known signal ids" table. New id = contract PR to the lead. (`suspicious_link` was accepted by the lead in #140; its row in `contracts/detector-interface.md` is the lead's to add.)
- Every signal needs `label` (Guardian) and `labelSimple` (Protected, plain words), each as `{ en, id }` — English AND Bahasa Indonesia.
- After changing `src/`, run `scripts/sync-to-extension.sh` and commit both `src/` and the generated `ios/ShooExtension/Resources/detector.js`.
- Write tests for every rule (e.g. "p0stindonesia.com" → `lookalike_domain`, "tokopedia.com" → no signals; every URL part of the dissector has a test, and known false positives are pinned as tests so a change shows up).
- Don't touch anything outside `detector/` except the generated `detector.js`.
