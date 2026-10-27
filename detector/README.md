# detector — layer 1 & 2 (on device)

```
src/detector.js               Source (edit this)
data/brands.json              25 brands: official domains, names, cheap TLDs, bait keywords
data/link-rules.json          Link dissector data: free hosts, bait words, carriers, rare TLDs
scripts/build.mjs             Inlines both JSON files into one plain script
scripts/sync-to-extension.sh  Copies the build into ios/ShooExtension/Resources/detector.js
test/detector.test.mjs        node --test detector/test
```
The output stays a single plain script (Safari content scripts cannot import).

## What layer 2 checks

Layer 2 has two parts, run on every page that is not an official domain. Their weights add up.

| Part | Reads | Signals |
|---|---|---|
| A. Brand check | the host name only | `lookalike_domain` (25 / 10), `brand_plus_keyword` (14), `cheap_tld` (5 / 15) |
| B. Link dissector (#140) | the **whole URL** | `suspicious_link` (10 to 100) |

B scores each part of the URL on its own (max 25 per part):

| Part | Trigger | + |
|---|---|---|
| scheme | `http` without TLS | 5 |
| userinfo | `user@` before the host | 25 |
| host | IP address 20 · 4+ labels 8 · 3+ hyphens in a label 8 · digit-heavy label 8 · punycode 5 | |
| TLD | `.info .pw .cc .ws .su` (the TLDs in `brands.json` are `cheap_tld`, not counted twice) | 6 |
| port | not 80 / 443 | 10 |
| path | random file name (20+ chars, high entropy, has digits) 15 · ends in `.html .php …` 5 · slash after a file name 8 · bait word 6 | |
| query | redirect to another URL 12 · email 5 · over 150 chars 5 | |
| fragment | URL inside the fragment | 8 |
| length | over 120 chars | 4 |
| free hosting | host is on the list 3 · bait/carrier word in the first label 10 (16 for 2+) · year/amount in the label 5 · bait/carrier word in the file name 10 | added on top |

Rules of the signal: one per page, weight is the raw score (**no cap**, max 100), nothing is emitted below 10, private and loopback addresses are skipped. `evidence` holds reason codes only. Weights are guesses (D-imelda-45); known false positives are pinned in the tests.

Try it: `ai/testing/26-oct-2026/06-testing-14.57/l2-v2-visual.html`.
