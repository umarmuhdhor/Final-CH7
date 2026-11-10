# QA report: edge cases on two phones

Run on 2026-11-10 (evening, WITA) for the 2026-11-11 hunt. App `main` @ c6d34a88. Follows [figma-parity-2026-11-10.md](https://github.com/umarmuhdhor/Final-CH7/blob/docs/QA-figma-parity-2026-11-10/plan/alief/qa/figma-parity-2026-11-10.md) (PR #366). Its 17 problems are not repeated here. Its #1 (push tap freezes the Guardian app) is fixed on `fix/GD-06-detail-push-hang`.

## Short version

- 16 edge cases tried on a Guardian phone and a Protected phone, with the real Safari extension, the real local server and database. **22 new problems: 3 P1, 5 P2, 14 P3** (row 20 is a known one, listed but not counted). No P0: no data leak found, and the core pairing and blocking flow works.
- **Biggest problems:**
  1. **No `/analyze`, no protection.** When the Protected phone's session is gone (or the phone is offline, or the AI server is down), the same BCA PIN/OTP/KTP page that scored 100% a minute earlier scores **14% "RISIKO RENDAH"** and loads with no warning. PIN, OTP and KTP form signals exist only on the server (layer 3).
  2. **Onboarding locks up behind one shared IP.** `POST /devices` allows 10 per hour per IP. Joining as Protected registers twice (Pribadi first, then Protected). In this test the 11th registration got `429 rate_limited`. The app says "Terlalu banyak percobaan. Tunggu beberapa menit", but the wait can be up to an hour. Mobile networks in Indonesia put many users behind one carrier-grade NAT IP.
  3. **"Aktif" lies to the Guardian.** Bu Sari turned the Shoo extension off in Safari settings. Her app says "Anda Belum Terlindungi", but the Guardian still sees "Bu Sari · Aktif · iPhone · Safari". The same "Aktif" shows for members who never opened Shoo, and for a dead device left behind after a reinstall.
- **Things that work:** an expired code shows a clear message. A Protected person can't join a second family. Two simultaneous account deletes leave no rows. The 14-day retention cut is exact to the minute. A push opened while the app is killed, or with the phone locked, works, including for a scan already deleted. Time zone changes move the times correctly. "Bahaya" after "Aman" blocks again on the next reload.

## How to read this report

**How bad:** P0 blocks the core flow or leaks data. P1 is a core feature that is wrong or misleads. P2 is visible quality or UX. P3 is cosmetic, or a question.

**Scam score** (`contracts/README.md`): 0 to 29 nothing, 30 to 49 a card, 50 to 79 a sheet, 80 and up the page is blocked.

| | |
|---|---|
| Phones | "QA Edge Guardian 1111" (Guardian **Rina Sekar Ayuningty**, a 20-character name on purpose) and "QA Edge Protected 1111" (**Bu Sari**). iPhone 17 Pro simulator, iOS 26.5, Bahasa Indonesia, app clock Asia/Jakarta (WIB). The simulator status bar shows the Mac's clock (WITA), one hour ahead. |
| Extra family members | Pak Budi, Kak Dewi (and Om Agus, refused because the family was full) joined with `curl` on the same code. They never ran the app. |
| Server | `wrangler dev` on `localhost:8787`. This session reused the server that the `qa-1110-fixes` session runs from its worktree (branch `fix/GD-06-detail-push-hang`). That branch has no `backend/` diff against `main`, so results match `main`. Local Supabase. AI server on `localhost:8789` (app flag `-debug.aiBaseURL`). |
| Test pages | Served on port 8898 from `*.localhost` hosts, a fresh `eNN.localhost` per case. Pages: a BCA PIN/OTP/KTP form (`login.html`), a Shopee prize form (`klaim.html`), and a page with no form (`benign.html`). |
| Push | A laptop can't reach Apple (`failed:network` in `push_log`), so each banner is the server's exact text delivered with `xcrun simctl push`. |
| Limits | Offline was not cut at the network level, because the server and the AI on the Mac are shared with other sessions. It is covered by E9: the extension takes the same code path when `/analyze` fails for any reason. Tier edges are checked in code and with the detector run in Node (E14), not on live pages. |

## Problems found

| # | Problem | Where to see it | How bad · owner | Lead |
|---|---|---|---|---|
| 1 | **Without `/analyze` a credential page looks safe.** Session gone: the BCA PIN/OTP/KTP page scores 14% "RISIKO RENDAH · Nama brand ditambah kata lain", with no card, sheet or block. The same page was 100% and blocked before. `asks_pin`, `asks_otp` and `asks_ktp` come only from the AI server (layer 3). When `/analyze` fails, the extension returns no signals and still shows a confident low score. The same happens offline or when the AI is down. The figma-parity report saw 40% in the signed-out case, but didn't list it as a problem. | E9; `e11-p-ext-session-gone.jpg`, `e11-p-pill-session-gone.jpg` | **P1** · Lead (extension) + AI | `ios/ShooExtension/Resources/background.js:96-110` (any failure returns `signals: []`); `ai/src/layer3/forms.js` |
| 2 | **Onboarding is blocked by the per-IP device limit.** `POST /devices` allows 10 per hour per IP. A Protected person registers twice (Pribadi, then Protected on join). After 10 registrations from one IP, the next join fails with `429 rate_limited`. The app shows "Terlalu banyak percobaan. Tunggu beberapa menit, lalu coba lagi.", the copy for `too_many_attempts`, but no join attempt was recorded and the wait can be up to an hour. Behind a carrier-grade NAT, strangers share this bucket. | E10; `e17-p-rejoin-family-full.jpg` | **P1** · Team App (backend + app copy) | `backend/api/src/http/rateLimit.ts:13`; app error mapping for `rate_limited` on join |
| 3 | **Guardian sees "Aktif" for a Protected person who isn't protected.** The extension was off, the app showed "Anda Belum Terlindungi", and the Guardian's Profile showed "Bu Sari · Aktif · iPhone · Safari". "Aktif" only means "linked". It also shows for members who never ran Shoo (Pak Budi, Kak Dewi) and for the dead device left by a reinstall. The Guardian is never told protection is off. Needs a field in the contract, so it goes to the lead. | E8, E10, E5; `e12-p-app-ext-off.jpg`, `e12-g-profile-ext-off.jpg`, `e17-g-ghost-member.jpg`, `e3-g-home-three.jpg` | **P1** · Team App + Lead (contract) | `ios/ShooApp/Features/Shield/GuardianHomeView.swift:367` (`isConnected ? "Active"`), `ios/ShooApp/Features/Profile/ProfileView.swift:196` |
| 4 | **Foreground push doesn't refresh Guardian Home.** The banner shows, but Home stays "Keluarga Terlindungi! · Belum ada situs berisiko" for 20 s and longer. Only pull-to-refresh shows "Keluarga Dalam Ancaman". | E3; `e4-g-home-after-push.jpg`, `e4-g-home-stale-20s.jpg`, `e4-g-home-after-pull.jpg` | P2 · Team App | `ios/ShooApp/App/AppDelegate.swift:33-44` (`willPresent` only shows the banner); `GuardianHomeView.swift:81-85` reloads only on refresh and scene change |
| 5 | **"Bahaya" can't be undone in the app.** After Bahaya, Detail shows no "Ubah", so Bahaya → Aman is impossible. The server accepts the change, and the button's hint says "Applies right away. You can change it later." Bahaya also queues the domain for the global blocklist (`blocklist_entries`, families = 1), so a mis-tap has an effect outside the family. | E2; `e4-g-detail-no-change.jpg` | P2 · Team App + product decision | `ios/ShooApp/Features/Detail/DetailFooter.swift:41` (`canChange … verdict.value == .safe`), `:102` |
| 6 | **Reinstall leaves a ghost that holds a family slot.** After reinstalling on the Protected phone, onboarding starts fresh as a new device. The old device stays linked and "Aktif · 7 mnt lalu". In a full family of 3, the person can't rejoin until the Guardian finds and removes the ghost, and nothing tells either side. | E10; `e17-p-after-reinstall.jpg`, `e17-g-ghost-member.jpg` | P2 · Team App | `family_links` keeps `9b0ec542…`; no recovery path in onboarding |
| 7 | **Onboarding text overlaps after coming back from Settings.** On "Aktifkan Ekstensi", returning without turning the extension on adds the "Shoo dimatikan…" card. It pushes step 03 under the consent checkbox, and the lines draw over each other. | E15; `g-ext-return-overlap.jpg` | P2 · Team App | `ios/ShooApp/Features/Onboarding/TurnOnExtensionView.swift` (info card ~`:53` + footer) |
| 8 | **Domain-only scams stay under the first warning.** Run in Node through the real detector: `login.klikbca.com.verifikasi-akun.xyz` = **29** (one point under the card), `bcа.co.id` with a Cyrillic "а" = **25**, `bca.verifikasi-data.info` = 14, `verifikasi-akun-nasabah-prioritas-bank-central-asia-2026-resmi.com` = 0. A look-alike domain alone never warns. With problem 1 this is all the protection left offline. | E13, E14 | P2 · Lead (detector) | `detector/src/detector.js:21` (weights), `:334` (punycode +5), `:459-470` |
| 9 | **A page on a sibling subdomain is blocked with the old page's reasons.** After Bahaya on `bca-verifikasi.e4a.localhost`, a page with no form on `news.e4a.localhost` shows "Halaman ini diblokir · Meminta PIN rahasia kamu · Meminta nomor KTP kamu…" and 100%. No new scan is stored, so the Guardian never hears about it. Blocking the whole domain may be wanted, but the reasons are false for this page. | E4; `e10-p-sibling-subdomain.jpg` | P3 · Lead | `ios/ShooExtension/Resources/pipeline.js:130` (`recallBlock`), `block-memory.js` (keyed by registrable domain) |
| 10 | **Long domain cut at the end on the block page.** The chip shows "verifikasi-akun-nasabah-prioritas-bank-central-asia…", hiding the part that tells real from fake. The Guardian app cuts in the middle ("verifikasi-aku…resmi.localhost"), which is better. | E13; `e15-p-long-domain.jpg`, `e15-g-home-long-domain.jpg` | P3 · Lead | `ios/ShooExtension/Resources/blocked.css:33-35` (`text-overflow: ellipsis` at the end) |
| 11 | **IDN look-alike shown as raw punycode.** The chip says "xn--bc-7kc.localhost". Safe, since it doesn't spoof "bca", but it means nothing to a parent and there is no "looks like BCA" note. | E13; `e15-p-idn-domain.jpg` | P3 · Lead | block page chip; `detector.js:99` already decodes labels |
| 12 | **App score colours ignore the server thresholds.** The extension takes `warnAt` / `blockAt` from `GET /config/public` (today 30 / 80, version 0). The app's ring uses fixed 30 / 50 / 80. If the admin moves `blockAt` to 70, a 75 is blocked on the phone but drawn as a sheet-level score in the app. Code reading only; the shared thresholds were not changed. | E14 | P3 · Team App + Lead | `ios/ShooApp/Components/ScoreRing.swift:31`, `ios/ShooShared/ScanResult.swift:59`, `ios/ShooExtension/Resources/thresholds.js:25-30` |
| 13 | **Verdict rows keep the full URL after day 14.** Retention deleted the e5b scan exactly on time, but its `verdicts` row stays with `url = http://bca-login.e5b.localhost:8898/login.html`, `by_name` and `scan_id = null`. Retention only clears `notes`. This may be wanted (block memory, blocklist), but the 14-day promise reads as covering the visited URL. Needs a check against SECURITY §3. | E7 | P3 · Team App (backend), question | `backend/api/src/cron/retention.ts:187` |
| 14 | **Join link opened during onboarding is lost.** `shoo://join?code=687354` while on "Jadikan Safari Default": the code boxes are empty when the Connect screen opens. A Pribadi device registers as `mode=guardian`, and that clears the pending code. | E10 | P3 · Team App | `ios/ShooApp/App/AppEnvironment.swift:205` |
| 15 | **Guardian code card keeps an expired code.** After the server expired code 315801, the Guardian card still showed it with "berlaku 22.23" and didn't re-check. The Protected side was correct. | E1; `e1-g-expired-code.jpg`, `e1-p-expired-code.jpg` | P3 · Team App | `ios/ShooApp/Features/Pairing/FamilyCodeModel.swift` (countdown is local only) |
| 16 | **"berlaku 29.55" reads like a clock time.** `minuteSecond` with the Indonesian locale writes a dot. "berlaku 29 mnt" or "29:55" would be clearer. | E1; `g-code-fresh.jpg` | P3 · Team App | `ios/ShooApp/Features/Pairing/FamilyCodeModel.swift:165` |
| 17 | **Name over 20 characters: no error.** "Selanjutnya" stays disabled, and the hint "*Nama harus terdiri dari maksimal 20 karakter" stays grey. | E15; `g-name-over-20.jpg` | P3 · Team App | `ios/ShooApp/Features/Onboarding/NameView.swift:19` |
| 18 | **Long Guardian name cut off at the left.** Join success screen: "na Sekar A… · Guardian". | E5; `e16-p-join-success-longname.jpg` | P3 · Team App | join success chip |
| 19 | **"Notifikasi mati" comes back on every launch.** It appears after "Nanti saja" too. `UITestSupport.swift:28` says once per launch is intended, so this is a question: should "Nanti saja" quiet it for a while? | E11; `g-notif-denied-alert.jpg`, `e13-g-notif-alert-relaunch.jpg` | P3 · Team App, question | GD-01 |
| 20 | *Not counted, known as figma-parity #10.* An open scam page isn't blocked by a later Bahaya (here on the Aman → Ubah → Bahaya path) until a reload. Listed only so the fix covers this path too. | E2; `e5-p-open-after-bahaya.jpg` | known · Lead | `pipeline.js` (no polling on normal pages) |
| 21 | **"Bagikan undangan" offered in a full family.** Profile still offers the invite at 3 of 3. A new person then gets `family_full` only after typing the code. | E5; `e17-g-ghost-member.jpg` | P3 · Team App | Profile header |
| 22 | **Private Browsing is unprotected by default.** Safari's "Izinkan di Penelusuran Pribadi" is off after setup, and onboarding doesn't mention it. A scam link opened in a private tab gets no check. | E8; `e12-p-ext-toggled-off.jpg` (row visible before the toggle) | P3 · Team App (onboarding copy) | onboarding ON-03 |
| 23 | **Members who never ran Shoo show "Aktif · Safari".** Pak Budi and Kak Dewi joined by API only and never had the app or extension. Same root as #3, listed so the contract change covers it. | E5; `e3-g-home-three.jpg` | P3 · Team App + Lead | see #3 |

## Cases

### E1. Expired, reused and third-phone codes

| Step | Bu Sari (Protected) | Rina (Guardian) |
|---|---|---|
| Fresh code | | <img src="img/edge-cases-1111/g-code-fresh.jpg" width="160"><br>"berlaku 29.55" (#16) |
| Code expired on the server (`expires_at` moved into the past) | <img src="img/edge-cases-1111/e1-p-expired-code.jpg" width="160"><br>"Kode kedaluwarsa, minta kode baru dan coba lagi." ✅ | <img src="img/edge-cases-1111/e1-g-expired-code.jpg" width="160"><br>Still shows 315801, "berlaku 22.23" (#15) |
| Same code reused by two more phones (Pak Budi, Kak Dewi, `curl`) | | Both joined. The code is multi-use until the family has 3 ✅ |
| Fourth phone (Om Agus) on the same code | | `409 family_full` ✅ (contract) |

**Expected:** an expired code is refused on both sides, and the Guardian card asks for a new code. **Actual:** refused correctly, but the Guardian card keeps the old code. **Severity:** P3 (#15, #16).

### E2. Bahaya → Aman and Aman → Bahaya on the same scan

| Step | Bu Sari | Rina |
|---|---|---|
| e4a: BCA form blocked | <img src="img/edge-cases-1111/e4-p-blocked.jpg" width="160"><br>100%, "Link terkirim ke Rina Sekar Ayuningty" | |
| Rina taps Bahaya | <img src="img/edge-cases-1111/e4-p-after-bahaya.jpg" width="160"><br>"Dipastikan penipuan oleh Rina Sekar Ayuningty" ✅ | <img src="img/edge-cases-1111/e4-g-after-bahaya.jpg" width="160"> <img src="img/edge-cases-1111/e4-g-detail-after-bahaya.jpg" width="160"><br>Verified as scam |
| Try to change back to Aman | | <img src="img/edge-cases-1111/e4-g-detail-no-change.jpg" width="160"><br>No "Ubah" (#5) |
| e5b: blocked | <img src="img/edge-cases-1111/e5-p-blocked.jpg" width="160"> | |
| Rina taps Aman | <img src="img/edge-cases-1111/e5-p-after-aman.jpg" width="160"><br>Page reloads to the form (known figma-parity #3) | <img src="img/edge-cases-1111/e5-g-detail-safe.jpg" width="160"><br>"Diverifikasi aman · Ubah" |
| Ubah → Bahaya | <img src="img/edge-cases-1111/e5-p-open-after-bahaya.jpg" width="160"><br>Open form stays usable (#20) | <img src="img/edge-cases-1111/e5-g-detail-ubah.jpg" width="160"> <img src="img/edge-cases-1111/e5-g-after-bahaya.jpg" width="160"><br>"Situs Sudah Ditandai Blokir!" |
| Reload, 23 s after Bahaya | <img src="img/edge-cases-1111/e5-p-reload-after-bahaya.jpg" width="160"><br>Blocked, "Dipastikan penipuan" ✅ | |

**Expected:** either decision can be changed, and the other phone follows. **Actual:** Aman → Bahaya works after a reload. Bahaya → Aman is impossible in the app. **Severity:** P2 (#5). Row 20 is known.

### E3. Push: app open, app killed, phone locked

| Step | Rina |
|---|---|
| App open on Home, push arrives | <img src="img/edge-cases-1111/e4-g-home-after-push.jpg" width="160"> <img src="img/edge-cases-1111/e4-g-home-stale-20s.jpg" width="160"><br>Banner, but Home stays "Belum ada situs berisiko" (#4) |
| Pull to refresh | <img src="img/edge-cases-1111/e4-g-home-after-pull.jpg" width="160"><br>"Keluarga Dalam Ancaman" |
| App killed, push for a scan that retention already deleted | <img src="img/edge-cases-1111/e7-g-push-killed-banner.jpg" width="160"> <img src="img/edge-cases-1111/e7-g-push-killed-deleted-scan.jpg" width="160"><br>Tap opens "Item ini sudah tidak ada" ✅ |
| Phone locked | <img src="img/edge-cases-1111/e7-g-push-locked.jpg" width="160"><br>Shown on the Lock Screen, with no domain in the text ✅ |

**Severity:** P2 (#4). The rest passes.

### E4. Subdomains and block memory

| Step | Bu Sari |
|---|---|
| After Bahaya on `bca-verifikasi.e4a.localhost`, open `news.e4a.localhost/benign.html` (no form) | <img src="img/edge-cases-1111/e10-p-sibling-subdomain.jpg" width="160"><br>Blocked with the old page's reasons; no new scan row (#9) |
| Block memory after Aman (e5b) | Cleared: the page reloads (see E2) ✅ |

**Expected:** the sibling page is either checked on its own, or blocked with honest copy ("this site was confirmed as a scam"). **Actual:** the old reasons are shown. **Severity:** P3.

### E5. Guardian with several Protected; a second family

| Step | Bu Sari | Rina |
|---|---|---|
| Paired with a 20-character Guardian name | <img src="img/edge-cases-1111/e16-p-join-success-longname.jpg" width="160"> <img src="img/edge-cases-1111/e16-p-home-paired-longname.jpg" width="160"><br>Chip cut at the left (#18) | <img src="img/edge-cases-1111/e16-g-home-paired-longname.jpg" width="160"> |
| Three members | | <img src="img/edge-cases-1111/e3-g-home-three.jpg" width="160"><br>All "Aktif", although two never ran Shoo (#23) |
| Bu Sari opens another Guardian's invite link (`shoo://join?code=701989`) | <img src="img/edge-cases-1111/e3-p-second-family-link.jpg" width="160"> <img src="img/edge-cases-1111/e3-p-second-family-open.jpg" width="160"> <img src="img/edge-cases-1111/e3-p-second-family-result.jpg" width="160"><br>"Kamu sudah terhubung ke Guardian. Putuskan dulu di Profil." ✅ | |

**Severity:** P3 (#18, #21, #23). Joining a second family is refused correctly. (The locked disconnect row it points to is figma-parity #7.)

### E6. Both sides delete their accounts at the same moment

A fresh family (Guardian "Bu Lina", Protected "Nenek Ida", by `curl`). Four `DELETE /devices/me` calls for each side, all at once:

| Result | |
|---|---|
| HTTP | 8 × `200` (all passed auth before the first commit) |
| Rows left in `devices`, `family_links`, `family_codes` | 0, 0, 0 ✅ |
| Old token afterwards | `401 unauthorized` ✅ |

**Severity:** pass. No storage objects were involved (no scans).

### E7. 14-day retention boundary

Two of my own scans were moved back: e4a to 14 days − 1 hour, e5b to 14 days + 1 minute. Then the retention cron was run (`/cdn-cgi/handler/scheduled?cron=0+19+*+*+*`).

| Before | After |
|---|---|
| <img src="img/edge-cases-1111/e6-g-home-backdated.jpg" width="160"><br>e4a "27 Okt 2026, 23.01" and e5b | <img src="img/edge-cases-1111/e6-g-home-after-retention.jpg" width="160"><br>e5b gone, e4a kept ✅ |

**Expected and actual:** the cut is exact. The verdict row of the deleted scan stays with its full URL (#13). **Severity:** P3 question.

### E8. Extension turned off during a scan

The scan finished in about 1 s, so the switch landed just after it (15:07:36 stored, switch at 15:07:37+).

| Step | Bu Sari | Rina |
|---|---|---|
| Safari › Ekstensi › Shoo › off | <img src="img/edge-cases-1111/e12-p-ext-toggled-off.jpg" width="160"> <img src="img/edge-cases-1111/e12-p-page-after-ext-off.jpg" width="160"><br>Safari closes the block tab | |
| Same scam page again | <img src="img/edge-cases-1111/e12-p-scam-ext-off.jpg" width="160"><br>Loads with no check (expected with the extension off) | |
| Apps | <img src="img/edge-cases-1111/e12-p-app-ext-off.jpg" width="160"><br>"Anda Belum Terlindungi · Nyalakan sekarang" ✅ | <img src="img/edge-cases-1111/e12-g-home-ext-off.jpg" width="160"> <img src="img/edge-cases-1111/e12-g-members-ext-off.jpg" width="160"> <img src="img/edge-cases-1111/e12-g-profile-ext-off.jpg" width="160"><br>"Bu Sari · Aktif · iPhone · Safari" (#3) |

**Expected:** the Guardian learns that Bu Sari is unprotected. **Actual:** Rina still sees "Aktif". **Severity:** P1 (#3).

### E9. Session expiry (and offline)

The server forgot Bu Sari's device (row deleted, as the 30/90-day inactive cleanup would do).

| Step | Bu Sari |
|---|---|
| Open the app | <img src="img/edge-cases-1111/e11-p-app-session-gone.jpg" width="160"><br>"Sesi berakhir · Mulai lagi" ✅ |
| Open the BCA PIN/OTP/KTP page on a fresh domain (e19) | <img src="img/edge-cases-1111/e11-p-ext-session-gone.jpg" width="160"> <img src="img/edge-cases-1111/e11-p-pill-session-gone.jpg" width="160"><br>No block; pill "RISIKO RENDAH 14%" (#1) |

**Expected:** with no server, the extension either still catches credential forms on the device or says the check is incomplete, and the Guardian is told. **Actual:** a confident low score. Offline takes the same path: `analyze()` in `background.js` catches every failure and returns no signals. **Severity:** P1.

### E10. App reinstalled on the Protected side

| Step | Bu Sari | Rina |
|---|---|---|
| Uninstall + install the same build | <img src="img/edge-cases-1111/e17-p-after-reinstall.jpg" width="160"><br>Onboarding from the start; new device `179de6d7…` | <img src="img/edge-cases-1111/e17-g-ghost-member.jpg" width="160"><br>Old Bu Sari still "Aktif · 7 mnt lalu" (#6) |
| Join with Rina's code 687354 (family has 3 with the ghost) | <img src="img/edge-cases-1111/e17-p-rejoin-family-full.jpg" width="160"><br>"Terlalu banyak percobaan…" from `429 rate_limited` on `POST /devices` (#2) | |

The invite link opened during onboarding was dropped (#14). No old data showed on the new device. The "Bahaya Terdeteksi" it showed was a fresh rescan of the e18 tab still open in Safari. The Guardian side was not reinstalled, to keep the family for the other cases.

**Severity:** P1 (#2), P2 (#6), P3 (#14).

### E11. Notifications denied, then turned on later

| Step | Rina |
|---|---|
| Denied in onboarding | <img src="img/edge-cases-1111/g-notif-denied-alert.jpg" width="160"><br>"Notifikasi mati" alert |
| Next launch | <img src="img/edge-cases-1111/e13-g-notif-alert-relaunch.jpg" width="160"><br>Same alert again (#19) |
| Turned on in Settings, back to Shoo | <img src="img/edge-cases-1111/e13-g-settings-notif-on.jpg" width="160"> <img src="img/edge-cases-1111/e13-g-home-after-enable.jpg" width="160"><br>APNs token reached the server within ~15 s ✅ |

### E12. Time zone change

| WIB (Asia/Jakarta) | WITA (Asia/Makassar) |
|---|---|
| <img src="img/edge-cases-1111/e6-g-home-backdated.jpg" width="160"><br>e4a "27 Okt 2026, 23.01" | <img src="img/edge-cases-1111/e14-g-home-tz-wita.jpg" width="160"><br>e4a "28 Okt 2026, 0.01" ✅ |

The date rolls over correctly at midnight.

### E13. Long domain and punycode / IDN look-alike

| Case | Bu Sari | Rina |
|---|---|---|
| 62-character label | <img src="img/edge-cases-1111/e15-p-long-domain.jpg" width="160"><br>Chip cut at the end (#10) | <img src="img/edge-cases-1111/e15-g-home-long-domain.jpg" width="160"><br>Cut in the middle ✅ |
| `xn--bc-7kc` (Cyrillic "а") | <img src="img/edge-cases-1111/e15-p-idn-domain.jpg" width="160"><br>Raw punycode (#11) | |

Domain signals are skipped for `*.localhost` (`detector.js:295`), so the live pages were blocked by their form only. The domain scoring was checked by running the built detector in Node (`detector/scripts/build.mjs`, the same script the extension gets), with no page text:

| Host | Signals | Score |
|---|---|---|
| `xn--klikbc-8nf.com` (klikbcа) | lookalike_domain 25, suspicious_link 11 | 36 card |
| `xn--bc-8kc.co.id` (bcа.co.id) | lookalike_domain 25 | 25 nothing |
| `login.klikbca.com.verifikasi-akun.xyz` | brand_plus_keyword 14, cheap_tld 15 | **29** nothing |
| `bca.verifikasi-data.info` | brand_plus_keyword 14 | 14 nothing |
| `verifikasi-akun-nasabah-prioritas-bank-central-asia-2026-resmi.com` | none | 0 nothing |

**Severity:** P2 (#8), P3 (#10, #11).

### E14. Tier edges 29/30, 49/50, 79/80

Checked in code: every place uses `>=`, so 29 → nothing, 30 → card, 49 → card, 50 → sheet, 79 → sheet, 80 → block.

| Place | Rule |
|---|---|
| Extension | `pipeline.js:8` `{30, 50, 80}`; `popup.js:12-17` `tierFor`; thresholds from `/config/public` (`thresholds.js:25-30`, `warnAt` 30–60, `blockAt` 50–95) |
| Server | `routes/scans.ts:76` refuses `blocked` below 50 |
| App | `ScoreLevel.swift:17-21` and `ScoreActivityAttributes.swift:19-21`: fixed 30 / 50 / 80 (#12) |

A real host sits right on an edge: `login.klikbca.com.verifikasi-akun.xyz` = 29 (E13). **Severity:** P3 (#12); see #8.

### E15. Onboarding odd paths

| Step | Rina |
|---|---|
| Name with 21+ characters | <img src="img/edge-cases-1111/g-name-over-20.jpg" width="160"><br>Disabled, no error (#17) |
| Back from Settings without turning Shoo on | <img src="img/edge-cases-1111/g-ext-return-overlap.jpg" width="160"><br>Steps overlap the checkbox (#7) |
| Fresh Pribadi Home | <img src="img/edge-cases-1111/p-home-fresh.jpg" width="160"> |

## Follow-ups

- Question issues for lead-owned and AI-owned work: #1 (extension + AI), #3 (contract field for extension status), #8–#11 (detector and block page), #12 (thresholds in ShooShared).
- The rest is Team App (`ios/ShooApp/`, `backend/`).
