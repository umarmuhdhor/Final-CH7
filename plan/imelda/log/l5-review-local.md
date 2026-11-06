# L5 review: local runs on dummy data

Plan: `plan/imelda/fase-09-layer5-review.md`. Everything below ran on the **local** Supabase database with the dummy data of
`ai/eval/dataset/` (`*.shoo-dummy.test`, plus `sites.google.com` as the shared-host case). **This is dummy data, not evidence.**
The decision "use the LLM or not" waits for real Guardian data.

## Task 4: review loop (`ai/eval/dataset/review-loop.mjs`)

| Run | Model | Domains | Result |
|---|---|---|---|
| `--mock-llm` (fake model in `dev-server.mjs`, `REVIEW_MOCK=1`) | mock-review | 13 due (9 dummy + 4 stock seed rows) | `stored 13`; second run `stored 0` |
| Real LLM through the local dev server | deepseek-v4-flash | 9 due (the dummy ones) | `stored 9`, 0 failed, one `/review` request of 4421 ms |

Real LLM answers on the 9 dummy domains (suggestion is computed in `ai/src/review/review.js`, threshold 0.7):

| Domain group | Families N | Avg score | LLM result | Suggestion |
|---|---|---|---|---|
| scam-01..06 | 2 to 5 | 72 to 88 | scam, confidence 0.78 to 0.98 | approve |
| scam-07, scam-08 (weak signals) | 2 | 40, 42 | unsure, 0.60 | none |
| legit-05 (2 N + 2 Y) | 2 | 55 | unsure, 0.55 | none |

Notes:
- Tokens: `/review` does not return token usage (it is not in the contract), so only the model name and latency are logged. At 25 domains per request and `max_tokens` 2000, one request is one provider call.
- The prompt is in Indonesian (`ai/prompts/review.js`, `review.v1`). The model's reasons come back in Indonesian.
- `shared_host` rows are never sent: `sites.google.com` is absent from `admin.review_due()` once `admin.shared_hosts` is filled from `ai/data/shared-hosts.json`.

## Task 5: rule vs LLM (`ai/eval/dataset/eval-review.mjs`)

Run on the dummy export after the real-LLM run above (`node eval/dataset/eval-review.mjs eval/dataset/out.jsonl`).

First run, truth = `final_label` (the label the families' votes produced):

| Approach | TP | FP | FN | TN | Precision | Recall |
|---|---|---|---|---|---|---|
| (a) rule: >= 2 families N and avg score >= 50 | 7 | 0 | 2 | 0 | 1.00 | 0.78 |
| (b) LLM suggestion = approve | 6 | 0 | 3 | 0 | 1.00 | 0.67 |

That truth was wrong for the dummy set: all 9 reviewed domains came out as `scam_weak`, including `legit-05` (2 N + 2 Y, built
to be legit), so there were no negatives and precision was 1.00 by construction. The LLM's `unsure` on `legit-05` was counted
as a miss, and the rule's approval of it as a hit.

Fixed run (6 Nov 2026, `--dummy-truth`: `scam-*` = scam, `legit-*` = not scam, other names left out), same 9 domains, same
review answers:

| Approach | TP | FP | FN | TN | Precision | Recall |
|---|---|---|---|---|---|---|
| (a) rule: >= 2 families N and avg score >= 50 | 6 | 1 | 2 | 0 | 0.86 | 0.75 |
| (b) LLM suggestion = approve | 6 | 0 | 2 | 1 | 1.00 | 0.75 |

Reading it: both approve `scam-01..06` and both miss `scam-07`/`scam-08` (average score 40 and 42). The only difference is
`legit-05`: the rule approves it (a false approve), the LLM holds it back (`unsure`, 0.55). That is one domain, so it shows the
eval can now tell the two apart, not that the LLM is better. **Dummy data, not evidence.** Only one negative, and only
`legit-05` was reviewed (`legit-01..04` are not among the 9 domains `review_due` returned; why was not checked). Whether to use the LLM at all
is decided on real Guardian data once layer 5 has collected some, scored with the default truth (the admin's final decision).
