# DRAF issue. Belum dikirim ke GitHub. Kirim hanya kalau Imelda setuju.

Template: **Question / proposal** (`.github/ISSUE_TEMPLATE/question.yml`) · label `question` · assign `@umarmuhdhor`

**Title:** `AI-M4: layer 4 gets an empty answer from reasoning models (OpenRouter); and brand_logo_offsite did not fire on a fake Microsoft login`

---

### PRD ID / area

AI-M4 (layer 4, `ai/src/layer4/provider.js`) and layer 3 (`brand_logo_offsite`)

### Context

Imelda ran one real phishing page end to end (report: `ai/testing/26-oct-2026/01-testing-09.58/testing-1.md`). Page: a fake Microsoft login on `helpnets[.]info`, captured with `ai/eval/tools/capture.mjs` (static GET, never opened in a browser). `main` @ `a035bb9`.

Two things came out of it. Both are in `ai/` (yours since 23 Oct), so this is a question, not a PR.

**1. Layer 4 returns nothing on a reasoning model.** Run against OpenRouter, model `deepseek/deepseek-v4-flash` (provider Relace), same request as `provider.js` sends (`max_tokens: 200`, `response_format: json_object`, `temperature: 0`):

| Variant | Time | finish_reason | completion / reasoning tokens | content |
|---|---|---|---|---|
| `max_tokens: 200` (current code) | 6.6 s | `length` | 200 / 218 | `null` |
| `max_tokens: 200` + `reasoning: {enabled: false}` | 3.7 s | `stop` | 31 / 0 | valid JSON |
| `max_tokens: 1000` | 8.6 s | `length` | 1000 / 1028 | `null` |

The model spends the whole `max_tokens` on reasoning, so `content` is empty. In `reality.js` this ends as `bad_schema` or `timeout`, and no signal is added. Nothing in the response says "wrong model": the outcome counters just show `bad_schema`/`timeout`. Raising `max_tokens` does not help (reasoning grows with it). Turning reasoning off gives the expected answer in 31 tokens.

Not known: whether production (`bandelbanget.xyz`, `deepseek-v4-flash`) behaves the same. Eval D-imelda-39 had 29% timeouts after the fix, which may or may not be this.

**2. `brand_logo_offsite` did not fire.** Snapshot had `imageAlts: ["Microsoft"]`, title "Sign in to your account", field ids `loginfmt` / `i0116` / `i0118` (Microsoft's own login ids), on `helpnets.info`. Layer 3 gave only `asks_password` (15). LLM said `reasonable: true` (confidence 0.6) because the brand never reaches it (D-imelda-27). Final score is about 15, below the 30 warning threshold.

### Proposal

1. In `provider.js`, send `reasoning: { enabled: false }` when the provider is OpenRouter (or always; other OpenAI-compatible providers ignore unknown fields, but this needs a check on `bandelbanget.xyz`). Additive, one line, and add the outcome `empty_content` so this shows up in the stats instead of `bad_schema`.
2. Find out why `brand_logo_offsite` stayed silent for `imageAlts: ["Microsoft"]` on a non-Microsoft domain (is Microsoft in `brands.json`? does the rule read `imageAlts`? does it need `asksData`?). Test snapshot: `ai/eval/data/scam/` after redaction, or the one in the report.
3. Optional, needs your OK on D-imelda-27: send the detected brand names (e.g. `["Microsoft"]`) to layer 4 as one extra field, not raw text. Bumps `reality-check` to v3 and needs a re-run of the eval.
4. Optional rule: brand-specific field ids (`loginfmt`, `i0116`, `i0118`) on a non-Microsoft domain.

### Questions

1. Does production layer 4 return an empty `content` too? (Worker `outcomes` counters: how many `bad_schema` / `timeout` vs `reasonable` / `flagged`.)
2. Is `reasoning: { enabled: false }` OK for `bandelbanget.xyz`, or does that provider reject or ignore it?
3. Is `brand_logo_offsite` supposed to catch a logo alt on the wrong domain, and is Microsoft in `brands.json`?
4. May layer 4 receive a list of detected brand names (point 3), given D-imelda-27?
5. Do you want the helpnets sample added to the eval set once it is redacted (A4/E-1)? License of the capture itself: it is a copy of a scam page, source "user-supplied".

### Until answered

Imelda changes nothing in `ai/` or `detector/` (rule 1). She keeps `ai/.env` (gitignored) with OpenRouter for local runs only, and treats local layer 4 results as unreliable until question 1 is answered. Blocks: the M6 recalibration on real data (E-2), and any claim that layer 4 adds detection on OpenRouter.
