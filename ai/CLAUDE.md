# ai/ — owner: Team AI

Server-side detection: layer 3 (content & forms) + layer 4 (reality check, LLM). Layer 5 (hoax) is Phase 2 — do not build it in MVP.
Exposes `POST /analyze` and `GET /public-blocklist` exactly as in contracts/api.md (M5 design: docs/design/blocklist.md).

- Input `{ snapshot, localSignals }`, output `{ signals: Signal[] }`. Shapes from contracts/ only.
- `/analyze` is stateless: never store or log the snapshot text.
- Text signals (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`): `evidence` = text copied **exactly** from the page; the extension highlights it (EX-05).
- The Bearer device token can't be verified here (no device table): don't rely on it, rate-limit per IP, never log it.
- Respond within 8 s; the extension gives up after that. Layer 3 (rules) should answer even if the LLM is slow/down.
- LLM keys only in `.env` (gitignored). Commit `.env.example`.
- Keep a labelled eval set (scam + legit pages) in `ai/eval/` and report precision/recall when changing prompts or weights.
- Don't touch anything outside `ai/`.
