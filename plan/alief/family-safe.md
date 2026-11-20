# Family-wide "Mark as safe" (20 Nov 2026)

Alief's decision: "Mark as safe" is a whitelist, scoped to one family (never global). When one family member marks a link safe, every phone in that family treats it as safe, so nobody marks it twice. Usability test 20 Nov 2026: the tester expected a whitelist and did not know where to correct a site.

Contract wording (no JSON shape change) was first asked in [umarmuhdhor/Final-CH7#632](https://github.com/umarmuhdhor/Final-CH7/issues/632). Alief then decided (20 Nov 2026): no waiting on an issue, Team App makes the Lead-owned wording change in the same PR, with Umar as reviewer. Who can mark: Guardian only (Alief: "Guardian saja").

## 1. How it works today (main @ 5a62eb94)

| Part | Today |
|---|---|
| App UI | Detail → footer "Aman / Bahaya" (`DetailFooter`, GD-07). Only a **Guardian** sees it (`DetailModel.canValidate`). "Aman" opens `SafeReasonSheet` (reason chips + optional note) and sends `POST /verdicts { scanId, value: "safe", notes }`. |
| Endpoint | `POST /verdicts` (`backend/api/src/routes/verdicts.ts`), `requireMode("guardian")`. The Guardian may decide on its own scans and on scans of its linked Protected members (`decideVerdict`). |
| Table | `verdicts`, primary key `(owner_id, url)`: one row per **scan owner** + link (origin + path, #241). `by_device_id` / `by_name` = who decided. |
| Extension | Asks `GET /verdicts?url=&domain=` with its own device token once a page reaches score 30 (`pipeline.js`), caches the answer 60 s (`verdicts.js`), polls fresh while the block screen is open, and asks fresh for a page in block memory. A `safe` → page opens, bubble says "Ditandai aman oleh <name>". |
| Lookup | `findVerdict`: (1) a verdict of **this owner** on exactly this link, (2) else a `not_safe` of this owner on another link of the domain (not on shared hosts), (3) else null. A `safe` never reaches past its link. Activity (`selectScans`) and `recordScan`'s "has a verdict" repeat the rule. |
| Scope | **Per device (scan owner)**. Guardian marks a link safe on the child's scan → safe only on the child's phone. The Guardian's own phone and other members still get the warning. |
| Weekly learning | A `safe` is locked until Shoo's weekly review has read it (#476, `verdictLock.ts`, "can change after Shoo's weekly learning"). Only `not_safe` verdicts by a Guardian on a linked Protected's scan go to the global review queue (`global_eligible`); a `safe` never reaches the global list. The admin learning reads verdict rows per family. |

## 2. Design

**One family list, resolved when read.** No new table and no copied rows. A family = one Guardian + its linked Protected members (`family_links`, today's star shape). New SQL function `public.verdict_family(device)` returns every device id in that device's family now (just the device when it has no family). The lookup's step 1 becomes "the newest verdict on exactly this link made in **this family**", whichever member's scan it was made on.

| Question | Decision |
|---|---|
| Key | **Link** (origin + path), as today (#241). A `safe` on `sites.google.com/view/a` must never open other pages of the platform. Domain-wide safe is not done: one page says nothing about the others. |
| Who can add | **The Guardian**, as today (PRD DT-05/GD-07). Its "Aman" on any member's scan, or its own, is safe for the whole family. A Protected member does not get the button: a scammer can talk the protected person into tapping "safe". Confirmed by Alief: "Guardian saja". |
| Undo | The Guardian changes it with "Ubah" → "Bahaya" (after the weekly-review lock). Newest verdict on the link in the family wins, so undo is family-wide too. The lock is checked across the family: a locked `safe` made on member A's scan also blocks a `not_safe` on member B's scan of the same link until the review. |
| `not_safe` on the same link | Also family-wide (step 1 does not care about the value): blocking more is the safe side, and it keeps "newest wins" one rule. Step 2 (a `not_safe` covering the rest of the domain) stays **per owner**: family-wide it would show member B the path of a page member A visited. |
| Member leaves / unpairs / deletes | Family is computed at read time from current `family_links`, so the moment a link is gone the member stops seeing the family's verdicts and the family stops seeing that member's. Verdicts the Guardian made on that member's scans are deleted as today (`dropVerdicts`, SECURITY §3 P13): they carry that member's link. `DELETE /devices/me` deletes all its rows. A new member sees the family's current list at once. |
| Speed | No push needed. The server answers family-wide the moment the verdict is saved. Another phone sees it on its next lookup: an open block screen within 2–15 s (poll), a new page visit after at most 60 s (extension cache), a page in block memory at once (fresh lookup). The app's Activity/Detail shows it on the next refresh. |
| Activity | Each member's own scan of that link shows the family verdict: "Ditandai aman oleh Ayah" (`VerdictNote`, unchanged), "Anda menandai ini aman" for the Guardian. Shown only on rows of that exact link. |
| Other families / global model | `verdict_family` never crosses `family_links`, so another family never sees it. No row is copied, so the admin learning and the global review queue still count one decision per family (`global_eligible`, `families_safe`). A `safe` still never goes to the global blocklist. |
| Privacy | No new data: no new column, table or field. A member learns only that the Guardian decided on the very link that member is opening. Notes are never returned and still cleared after 14 days; scans still go after 14 days; retention unchanged. |

## 3. Contract

JSON shapes stay the same (`Verdict` already has `byName`, `byDeviceId`, `url`). The text in `contracts/api.md` "Verdicts (per link)" ("applies to the scan's link for that owner", lookup step 1) and the `Verdict` description change meaning. Changed in this PR (Alief's decision, Umar reviews): `contracts/api.md` Verdicts (POST row, lookup steps 1–2, family-wide lock), `contracts/scan-result.schema.json` `Verdict.byName` description, `ios/ShooExtension/CLAUDE.md` block-memory sentence. Wording only. No `ios/ShooShared/` change and no extension code change: the extension already asks per link with its own token.

## 4. Build

- Backend: migration `verdict_family()`; `findVerdict`, `selectScans` (Activity), `recordScan` "has a verdict", and the lock check in `decideVerdict` use the family; tests in `test/verdicts-family.test.ts`.
- App: copy only. `SafeReasonSheet` says the link becomes safe on every phone in the family; the "Verified safe" card says so too.
- Follow-up (not here): the entry from the warning/block page to the app was not obvious in the test (extension, Umar).
- `admin.v_scans` (dashboard) still shows the verdict per owner; the admin view is not a family screen, so it stays.

## 5. Two-phone check (20 Nov 2026)

Two new simulators ("FamSafe Guardian" = Ayah, "FamSafe Protected" = Nenek), this branch's app (Debug, `AppConfig.apiBaseURL` pointed at a private worker on :8797 for the run only), the worker on an isolated Supabase stack (not the shared dev DB). Onboarded both in the app, paired Nenek to Ayah with a code, then one blocked scan of `https://bca-verifikasi.site/login` per phone (seeded in the DB: the extension is not part of this change).

1. Nenek's phone, before: "Situs Berbahaya!", Diblokir (`qa/img/family-safe/e2e-1-nenek-before.png`).
2. Ayah's phone: his **own** scan → Aman → "Saya kenal situs ini" → Tandai Aman. One verdict row, owner = Ayah (`e2e-2-ayah-marks-safe.png`).
3. Nenek's phone, reopened, nothing tapped: "Ayah Menandai ini Aman", Blokir Dibuka, "dikonfirmasi Ayah" (`e2e-3-nenek-after.png`). Before this change it stayed blocked: the verdict was Ayah's own only.

UI copy before/after: `sheet-before.png` / `sheet-after.png` (new line "Link ini jadi aman di semua HP keluargamu."), `card-before.png` / `card-after.png` ("… siapa pun di keluargamu di link ini.").
