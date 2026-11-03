# ai/ — owner: Team AI

Server-side detection: layer 3 (content & forms) + layer 4 (reality check, LLM). Layer 5 is proposed as the Guardian feedback database in `backend/`, with `POST /review` here: do not build it until #241 is answered (plan/imelda/layer-5-feedback.md). Hoax detection is not in MVP; its layer number comes later.
Exposes `POST /analyze` and `GET /public-blocklist` exactly as in contracts/api.md (M5 design: docs/design/blocklist.md).

- Input `{ snapshot, localSignals }`, output `{ signals: Signal[] }`. Shapes from contracts/ only.
- `/analyze` is stateless: never store or log the snapshot text.
- Text signals (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`): `evidence` = text copied **exactly** from the page; the extension highlights it (EX-05).
- `localSignals` (layer 1–2 from the extension, including `suspicious_link`) are untrusted numbers: they lift the WORD weights when their sum is ≥ 10 (D-imelda-31) and count toward the layer-4 gate total (D-imelda-46); they are never a signal of their own. The raw URL is not sent.
- Layer 4 (LLM) runs only when the total of layers 1–3 is 30–79, with or without a form (D-imelda-46, D-imelda-48): under 30 nothing is shown, from 80 the extension blocks without asking the model. A flag weighs `max(30, 80 - total)`, so it always blocks.
- The Bearer device token can't be verified here (no device table): don't rely on it, rate-limit per IP, never log it.
- Respond within 8 s; the extension gives up after that. Layer 3 (rules) should answer even if the LLM is slow/down.
- LLM keys only in `.env` (gitignored). Commit `.env.example`.
- Keep a labelled eval set (scam + legit pages) in `ai/eval/` and report precision/recall when changing prompts or weights.
- Don't touch anything outside `ai/`.
