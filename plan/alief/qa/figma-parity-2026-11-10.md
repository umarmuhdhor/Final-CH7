# QA report: does the iOS app match the new Figma, and what happens in the edge cases?

Run on 2026-11-10. App `main` @ c6d34a88. Follows [figma-parity-2026-10-31.md](figma-parity-2026-10-31.md).

## Short version

- **Screens vs Figma:** 86 Figma frames from 8 sections. 16 the same, 41 with small differences (mostly iOS: top bar position, tab names Perisai / Aktivitas), 22 clearly different, 3 not built, 4 not shot. The biggest gaps are listed in [Screens that differ from Figma](#screens-that-differ-from-figma).
- **Two real phones, real local server:** pairing, warning, block, the Guardian's "Aman" and "Bahaya", disconnect, and account delete on both sides all work end to end. 17 problems found (5 P1, 6 P2, 6 P3), plus one setup limit.
- **Biggest problems:**
  1. Tapping a scan notification can **freeze the Guardian's app** (100% CPU, never recovers).
  2. After the Guardian **deletes their account**, Maria's block page still says "Link terkirim ke Adhella". Nobody gets it.
  3. After the Guardian taps **Aman**, the two phones say opposite things. The Guardian is told "Maria tetap melihat peringatan Shoo". Maria's Safari reloads the scam form with **0% "Tidak ada tanda bahaya"**.
  4. A Protected person whose Guardian disconnected them **cannot rejoin from Profile**. They get "Kamu masih melindungi seseorang".
  5. **Dynamic Island never starts** in the real flow. The widget itself looks right when started by hand.
- **Notifications:** every kind the server sends is shown below. On a laptop the server cannot reach Apple (`failed:network`, same as last report), so each banner was delivered with `simctl push` using the server's exact text.

## How to read this report

**Screen status:**

| Mark | Meaning |
|---|---|
| ✅ same | Looks like the Figma frame. |
| 🟡 small diff | Small visual difference, often caused by iOS itself. |
| 🟠 clear diff | Clearly different. Needs a design or product decision. |
| 🔴 missing | The screen is not built. |
| ⚪ not shot | No app screenshot for this frame. |

**How bad:** P0 blocks the core flow or leaks data. P1 is a core feature that is wrong or contradicts itself. P2 is visible quality or UX. P3 is cosmetic.

**Scam score** (from `contracts/README.md`): 0 to 29 nothing, 30 to 79 a warning, 80 to 100 the page is blocked.

## What was tested

| Test | What it checks | How |
|---|---|---|
| Screens | Every frame of the 8 sections next to the app. | Figma file *[CH7] Shoo Scam App*, sections ONBOARDING `141:5987`, HOME `141:6094`, Profile `416:9961` and `455:9046`, Activity `413:1778` and `450:4935`, Detail Aktivitas Guardian REVISI PRU `1252:9850`, Detail Aktivitas Ortu REVISI PRU `1211:19924`. App side: `FigmaParityUITests` with fake data (scenario `figma` and the `protected*` / `homePribadi*` scenarios). |
| Edge cases | What each phone sees when the other one acts. | Two simulators paired by code, real Safari extension, real local server and database. Adhella is the Guardian, Maria is Protected. |
| Mock-only cases | States a real run can't easily reach. | Same app with `-UITestMock YES` and the debug flags named in each row. |

| | |
|---|---|
| Devices | "Shoo QA Guardian 1110" and "Shoo QA Protected 1110", iPhone 17 Pro simulator, iOS 26.5. |
| Settings | Bahasa Indonesia, light mode, app clock Asia/Jakarta (WIB). The simulator status bar shows the Mac's time (WITA), one hour ahead. |
| Server | `wrangler dev` on `localhost:8787`, local Supabase, AI server on `localhost:8789` (app flag `-debug.aiBaseURL`). Test scam pages served on port 8899 from wildcard test hosts (`*.sslip.io`, `*.lvh.me`, `*.nip.io`, `*.traefik.me`, `*.localhost`). |
| Figma | Exported at 1x through the TalkToFigma plugin (`figma-export` relay, channel of 2026-11-10). |

## Problems found

| # | Problem | Where to see it | How bad |
|---|---|---|---|
| 1 | **Guardian app freezes after tapping a scan notification.** The app opens on Aktivitas with an empty spinner, CPU stays at 100%, and no tab responds. It happened twice in 3 tries: when the app was on Home and when it was not running. It worked when Detail was already open. A stack sample shows `DetailFooter.body` re-evaluated nonstop. Likely loop: `onGeometryChange` sets `bottomInset`, which changes `.padding(.bottom, …)`, which changes the geometry again (`DetailFooter.swift:66`, `:82`). | E3; `e2e/e-g-push-tap-cold.jpg`, `e2e/hang-sample-detailfooter.txt` | P1 · Team App |
| 2 | **Block page names a Guardian who no longer exists.** After Adhella deletes her account, Maria's block page still says "Link terkirim ke Adhella", even after the app has refreshed and Home shows no Guardian. | E8; `e2e/e-p-safari-blocked-after-g-delete-2.jpg` | P1 · Lead (extension) + Team App |
| 3 | **"Aman" means different things on the two phones.** Guardian Detail: "Maria tetap melihat peringatan Shoo saat membuka situs ini" (`DetailFooter.swift:42`). Maria's open block page reloads the PIN/OTP/KTP form with no warning. The badge says "RISIKO RENDAH 0% · Tidak ada tanda bahaya di halaman ini". Maria's Aktivitas says "Shoo tetap tak menyarankan untuk membuka link ini". 3 minutes later the same page scored 48% and reached Adhella again as a new item. One rule is needed. | E4 | P1 · product decision (Lead + Team App) |
| 4 | **A disconnected Protected person can't rejoin from Profile.** Profile › Mode akun › "Punya kode undangan?" shows "Kamu masih melindungi seseorang", but Maria protects nobody. Cause: `canJoinAnotherFamily` needs `mode == .guardian` (`ProfileModel.swift:316`), and Maria is still `protected`. The Home card "Hubungkan" works. Mode akun also shows no mode selected. | E6; `e2e/e-p-rejoin-blocked-alert.jpg`, `e2e/e-p-mode-after-disconnect.jpg` | P1 · Team App |
| 5 | **Dynamic Island never starts in the real flow.** The extension calls `POST /live` on every page, and the server answers `no_start_token` each time: no app code sends `liveActivityStartToken`. `simctl push` push-to-start also shows nothing. Started by hand, the widget renders well in all 5 tones, expanded, and on the Lock Screen. Island text is Indonesian only. | E9 | P1 · Team App (token) + Lead (EX-03) |
| 6 | **No notice when the other side deletes their account.** The server sends no push on `DELETE /devices/me`. The Guardian's Maria simply disappears, and an old notification opens "Item ini sudah tidak ada". Maria's "Akun Tertaut" says only "Belum terhubung ke Guardian", with no reason and no button to connect. | E7, E8 | P2 · Team App |
| 7 | **Join error points to a locked row.** "Kamu sudah terhubung ke Guardian. Putuskan dulu di Profil." But a Protected person's disconnect row is locked ("Harus menggunakan akun <Guardian>"). | E11; `e2e/m-join-already.jpg` | P2 · Team App |
| 8 | **Two-line join errors overlap the 14-day note.** "Terlalu banyak percobaan…" and "Kamu sudah terhubung…" are drawn on top of "Shoo menyimpan salinan halaman…". | E11; `e2e/m-join-tries.jpg` | P2 · Team App |
| 9 | **Tab bar covers the Aman / Bahaya buttons.** In Detail opened from a notification (inside Aktivitas) and on the Guardian Home card at rest. The "Apakah situs ini berbahaya?" line also sits on the page copy. | E3; `e2e/e-g-push-tap-hang2.jpg`, `e2e/e-g-home-warning.jpg` | P2 · Team App |
| 10 | **"Bahaya" doesn't reach a warning page that is already open.** Only the block page polls for verdicts. After a reload the page is blocked with "Dipastikan penipuan oleh Adhella". The rescan then overwrites the same scan (40% warning becomes 100% blocked), so Maria's Home shows "Situs Berbahaya 100/100", not Figma's "warning and approved scam" (`1382:2227`). | E5 | P2 · Lead + Team App |
| 11 | **Counters count events, not sites.** Profile showed "2 Situs diblokir · 2 Peringatan" for 2 sites: the lvh.me page counted once as a warning and again as blocked, and the sslip.io page once blocked and once as a warning after "Aman". The server sums `blocked_total` / `warning_total` per event (`db/repo/families.ts:70`), so the number is right, but the label "Situs" reads as distinct sites. | E6; `e2e/e-g-profile.jpg` | P3 · wording decision |
| 12 | **The Mode TERAWASI card has no Aman / Bahaya buttons.** Figma `1382:2393` lets a Protected person without a Guardian decide on the card. The app shows the score only. | E6; `e2e/e-p-home-after-disconnect.jpg` | P2 · design check |
| 13 | **"Risiko Tinggi" on a 54% sheet.** The 50 to 79 sheet labels its gauge "Risiko Tinggi". The 40% card says "Waspada". Same family of issue as the 39% one last time. | E2; `e2e/e-p-safari-sheet.jpg` | P3 · Lead |
| 14 | **Name shown as "…".** Guardian Aktivitas, first row: "M … · 20.14 WIB" although "Maria" fits. | E5; `e2e/e-g-activity.jpg` | P3 · Team App |
| 15 | **One site, two names.** Lists mix the registrable domain ("sslip.io") with the full host ("bca-verifikasi-akun.127…"). Partly a test-host effect, but the same mix happens with real subdomains. | E6; `e2e/e-g-member-2.jpg` | P3 · Team App |
| 16 | **Connect title is cut off.** With the keyboard up, the title above the code boxes is pushed under the top edge ("…dan Guardian."). | E1, E11; `e2e/p-connect.jpg` | P3 · Team App |
| 17 | **Avatar not shown to others.** Each person picks an owl in onboarding, but the Home button and the Guardian's member list show a letter ("A", "M"). Only one's own Profile shows the owl. | E1; `e2e/e-p-home-paired.jpg` | P3 · Team App |
| 18 | **Push can't leave a laptop.** Every real push attempt logs `{"event":"push","result":"failed:network"}`. Not an app bug. Pushes need a real device or a cloud run. | all | ⚪ setup |

### Screens that differ from Figma

| Area | Frames | What differs | Who decides |
|---|---|---|---|
| Detail, PRU revision | `1252:9851` `1252:11249` `1252:10337` `1375:9638` `1211:19925` `1252:2346` `1252:2473` `1211:20018` `1211:20080` | No numbered summary card at the bottom (1 Minta PIN, 2 Meniru tampilan, 3 Domain baru). Reason cards show "Sinyal: …" lines. Footer differs after a decision (`1252:11249`, `1375:9638`). | Team App |
| Detail, older designs | `487:4221` `487:5990` `1187:3398` `1196:3985` `1196:4116` | Older options (gauge, BAHAYA label). The app builds the PRU revision. Designer should mark which is final. | Designer |
| Onboarding art | `1352:4375` `1352:4039` | Top illustration is grey placeholder cards, not Figma's phone and magnifier art. | Team App (asset) |
| Expired code, QR tab | `926:7974` | No red "Kode kadaluarsa" under the scanner on the simulator (no camera). Check on a phone. | Team App |
| Protected Home, no Guardian | `1382:2393` | No Aman / Bahaya on the card (problem 12). | Design check |
| Akun Tertaut | `455:9515` `457:10896` | Toggles say "Segera hadir". Putuskan koneksi is a locked grey row, not red. | Product |
| Notifications | `1115:14717` `455:9627` | Different switches. App adds Ringkasan mingguan and Jam tenang. Protected lacks "Link terblokir". | Product |
| Not built | `1326:12651` `1279:9348` `1286:12515` | Web invite redesign (only a plain join page), Protected disconnect sheet, "Tambah nomor HP" sheet (no phone row in Kelola profil). | Team App |
| Wording | Guardian Aktivitas | Filter says "Bahaya" where Figma and the row badges say "Diblokir". | Team App |

## Edge cases, end to end

Left phone is Maria (Protected), right phone is Adhella (Guardian), unless the caption says otherwise. All images are under `img/figma-parity-1110/e2e/`.

### E1. Pairing

| Step | Maria | Adhella |
|---|---|---|
| Fresh install, after onboarding | <img src="img/figma-parity-1110/e2e/p-home-fresh.jpg" width="160"><br>Pribadi Home with "Tidak yakin? Hubungkan" | <img src="img/figma-parity-1110/e2e/g-invite.jpg" width="160"><br>After "Lindungi orang terdekat": code and QR |
| Wrong code `111111` | <img src="img/figma-parity-1110/e2e/e-join-wrongcode.jpg" width="160"><br>"Kode itu tidak cocok dengan keluarga mana pun." | |
| Right code | <img src="img/figma-parity-1110/e2e/e-join-success.jpg" width="160"><br>"Berhasil Terhubung dengan Adhella!" | |
| Paired | <img src="img/figma-parity-1110/e2e/e-p-home-paired.jpg" width="160"><br>"Terhubung dengan Adhella" | <img src="img/figma-parity-1110/e2e/e-g-home-paired.jpg" width="160"><br>"Keluarga Terlindungi!", Maria · Aktif |

### E2. Warning and block in Safari

The extension has three levels. All three seen on Maria's phone:

| 30 to 49: small card | 50 to 79: sheet | 80 to 100: page blocked |
|---|---|---|
| <img src="img/figma-parity-1110/e2e/e-p-safari-warning.jpg" width="160"><br>Shopee prize page, 40% "Waspada" | <img src="img/figma-parity-1110/e2e/e-p-safari-sheet.jpg" width="160"><br>DANA login with OTP, 54% "Situs ini mencurigakan", Tinggalkan halaman / Tetap lanjutkan | <img src="img/figma-parity-1110/e2e/e-p-safari-blocked.jpg" width="160"><br>BCA PIN/OTP/KTP form, 100% "Halaman ini diblokir", "Link terkirim ke Adhella" |

Signed out (after Maria deleted her account) the extension keeps working offline only. The same BCA page then gets 40% from the link alone, and nothing is sent: <img src="img/figma-parity-1110/e2e/e-p-safari-signedout-warning.jpg" width="120">

### E3. Notifications

Each banner is the server's exact text (`backend/api/src/services/push/messages.ts`), delivered with `simctl push` because the laptop can't reach Apple.

| Who | When | Banner |
|---|---|---|
| Adhella | Maria hit a blocked page | <img src="img/figma-parity-1110/e2e/e-g-push-blocked.jpg" width="160"><br>"Maria membuka situs yang diblokir · 100%" |
| Adhella | Maria opened a warning page | <img src="img/figma-parity-1110/e2e/e-g-push-warning.jpg" width="160"><br>"Maria membuka situs mencurigakan · 40%" |
| Maria | Her own warning (if switched on) | <img src="img/figma-parity-1110/e2e/e-p-push-own-warning.jpg" width="160"><br>"Shoo memperingatkanmu soal situs berisiko · 40%" |
| Maria | Adhella disconnected her | <img src="img/figma-parity-1110/e2e/e-p-push-disconnected.jpg" width="160"><br>"Adhella berhenti melindungimu" |
| Maria | Adhella taps "remind" | <img src="img/figma-parity-1110/e2e/e-p-push-remind.jpg" width="160"><br>"Adhella mengingatkan: nyalakan Shoo di Safari" |
| Adhella | Maria's Shoo hasn't run for a day (hourly job) | <img src="img/figma-parity-1110/e2e/e-g-push-protection-off.jpg" width="160"><br>"Perlindungan Maria mati: Shoo tidak berjalan di Safari sejak sehari" |
| Adhella | Monday weekly summary | <img src="img/figma-parity-1110/e2e/e-g-push-weekly.jpg" width="160"><br>"Ringkasan minggu ini untuk kamu dan keluargamu: …" |
| Maria | Lock Screen with a Live Activity and a waiting banner | <img src="img/figma-parity-1110/e2e/e-island-lockscreen.jpg" width="160"> |

**Tapping the notification (problem 1):**

| App on Home or closed | Detail already open |
|---|---|
| <img src="img/figma-parity-1110/e2e/e-g-push-tap-cold.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-push-tap-detail.jpg" width="160"><br>Frozen: spinner or blank shield, 100% CPU, tabs dead | <img src="img/figma-parity-1110/e2e/e-g-push-tap-hang2.jpg" width="160"><br>Opens, but the tab bar covers Aman / Bahaya (problem 9) |

### E4. Maria is blocked, Adhella taps **Aman**

| Step | Maria | Adhella |
|---|---|---|
| Before | <img src="img/figma-parity-1110/e2e/e-p-safari-blocked.jpg" width="160"><br>Block page stays open | <img src="img/figma-parity-1110/e2e/e-g-home-blocked.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-detail-blocked.jpg" width="160"><br>"Keluarga Dalam Ancaman", Detail 100/100 |
| Adhella taps Aman | <img src="img/figma-parity-1110/e2e/e-p-safari-after-safe.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-safari-after-safe-badge.jpg" width="160"><br>Within 5 s the page reloads to the scam form. Badge: "RISIKO RENDAH 0% · Tidak ada tanda bahaya" | <img src="img/figma-parity-1110/e2e/e-g-detail-after-safe.jpg" width="160"><br>"Anda Menandai ini Aman", "Maria tetap melihat peringatan Shoo saat membuka situs ini" |
| Maria opens Shoo | <img src="img/figma-parity-1110/e2e/e-p-home-blocked-safe.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-detail-blocked-safe.jpg" width="160"><br>"Adhella menandai aman" (Figma `1373:12752`), Detail "Blokir Dibuka" | |
| Both lists | <img src="img/figma-parity-1110/e2e/e-p-activity.jpg" width="160"><br>"Menurut Adhella link ini aman. Shoo tetap tak menyarankan…" | <img src="img/figma-parity-1110/e2e/e-g-activity.jpg" width="160"><br>"Ditandai aman" |

Result: the unblock works, but the words disagree (problem 3). No notification tells Maria that Adhella decided.

### E5. Maria gets a warning, Adhella taps **Bahaya**

| Step | Maria | Adhella |
|---|---|---|
| Warning | <img src="img/figma-parity-1110/e2e/e-p-safari-warning.jpg" width="160"><br>40% card | <img src="img/figma-parity-1110/e2e/e-g-home-warning.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-detail-warning.jpg" width="160"><br>"Keluarga Butuh Konfirmasi" |
| Adhella taps Bahaya | <img src="img/figma-parity-1110/e2e/e-p-safari-after-scam.jpg" width="160"><br>Open page unchanged (problem 10) | <img src="img/figma-parity-1110/e2e/e-g-detail-after-scam.jpg" width="160"><br>"Situs Sudah Ditandai Blokir!" |
| Maria reloads | <img src="img/figma-parity-1110/e2e/e-p-safari-reload-after-scam.jpg" width="160"><br>Blocked, "Dipastikan penipuan oleh Adhella" | |
| Maria opens Shoo | <img src="img/figma-parity-1110/e2e/e-p-home-warning-scam.jpg" width="160"><br>"Situs Berbahaya! 100/100 · Adhella menandai berbahaya" | |

### E6. Adhella disconnects Maria

| Step | Maria | Adhella |
|---|---|---|
| Before | | <img src="img/figma-parity-1110/e2e/e-g-profile.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-member.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-member-2.jpg" width="160"> |
| Confirm | | <img src="img/figma-parity-1110/e2e/e-g-disconnect-confirm.jpg" width="160"><br>"Putuskan koneksi dengan Maria?" |
| After | <img src="img/figma-parity-1110/e2e/e-p-push-disconnected.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-home-after-disconnect.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-activity-after-disconnect.jpg" width="160"><br>History kept. Adhella's notes are gone, Mode TERAWASI card is back | <img src="img/figma-parity-1110/e2e/e-g-after-disconnect.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-home-after-disconnect.jpg" width="160"><br>"Belum ada yang Anda lindungi", new code |
| Maria tries to rejoin from Profile | <img src="img/figma-parity-1110/e2e/e-p-mode-after-disconnect.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-rejoin-blocked-alert.jpg" width="160"><br>No mode selected, then "Kamu masih melindungi seseorang" (problem 4). Rejoining from the Home card works. | |

### E7. Maria (Protected) deletes her account

| Step | Maria | Adhella |
|---|---|---|
| Confirm | <img src="img/figma-parity-1110/e2e/e-p-profile-bottom.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-delete-confirm.jpg" width="160"><br>"Adhella tidak akan menerima peringatanmu lagi." | |
| After | <img src="img/figma-parity-1110/e2e/e-p-after-delete.jpg" width="160"><br>Back to onboarding. Server: device, link, scans and verdicts gone. | <img src="img/figma-parity-1110/e2e/e-g-activity-after-p-delete.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-g-old-scan-after-p-delete.jpg" width="160"><br>No notice. List empty. An old notification opens "Item ini sudah tidak ada" |

### E8. Adhella (Guardian) deletes her account

| Step | Maria | Adhella |
|---|---|---|
| Before | <img src="img/figma-parity-1110/e2e/e-p-safari-blocked-paired2.jpg" width="160"><br>"Link terkirim ke Adhella" | <img src="img/figma-parity-1110/e2e/e-g-delete-confirm.jpg" width="160"><br>"1 orang yang kamu lindungi akan terputus." |
| After | <img src="img/figma-parity-1110/e2e/e-p-home-after-g-delete.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-connection-after-g-delete.jpg" width="160"><br>No notice. Home is Mode TERAWASI. "Belum terhubung ke Guardian" with no reason (problem 6) | <img src="img/figma-parity-1110/e2e/e-g-after-delete.jpg" width="160"><br>Back to onboarding |
| Maria opens a new scam page | <img src="img/figma-parity-1110/e2e/e-p-safari-blocked-after-g-delete.jpg" width="160"> <img src="img/figma-parity-1110/e2e/e-p-safari-blocked-after-g-delete-2.jpg" width="160"><br>Still "Link terkirim ke Adhella", also after the app refreshed (problem 2) | |

### E9. Dynamic Island

In the real flow nothing appears (problem 5): <img src="img/figma-parity-1110/e2e/e-p-island-push-to-start-none.jpg" width="120">

To check the widget itself, the island was started by hand with a temporary debug build (an `Activity.request` in `AppDelegate`, **not committed**), then Safari was opened:

| Tone | Compact | Expanded |
|---|---|---|
| Blocked, 100 | <img src="img/figma-parity-1110/e2e/e-island-compact-blocked-top.jpg" width="240"> | <img src="img/figma-parity-1110/e2e/e-island-expanded-blocked-top.jpg" width="240"><br>"Diblokir · bca-verifikasi.site" |
| Danger, 72 | <img src="img/figma-parity-1110/e2e/e-island-compact-danger-top.jpg" width="240"> | <img src="img/figma-parity-1110/e2e/e-island-expanded-danger-top.jpg" width="240"><br>"Risiko tinggi · promo-shopee88.xyz" |
| Warning, 40 | <img src="img/figma-parity-1110/e2e/e-island-compact-warning-top.jpg" width="240"> | |
| Analyzing | <img src="img/figma-parity-1110/e2e/e-island-compact-analyzing-top.jpg" width="240"> | |
| Safe, 0 | <img src="img/figma-parity-1110/e2e/e-island-compact-safe-top.jpg" width="240"> | |
| Lock Screen | <img src="img/figma-parity-1110/e2e/e-island-lockscreen.jpg" width="160"><br>Also asks "Allow Live Activities from Shoo?" | |

Full-screen versions: `e2e/e-island-compact-*.jpg`, `e2e/e-island-expanded-*.jpg`.

### E10. Becoming a Guardian

| Pribadi Home | "Lindungi orang terdekat" | Guardian Home, nobody yet |
|---|---|---|
| <img src="img/figma-parity-1110/e2e/g-home-fresh.jpg" width="160"> | <img src="img/figma-parity-1110/e2e/g-switch.jpg" width="160"><br>Figma `1382:11008` | <img src="img/figma-parity-1110/e2e/g-invite.jpg" width="160"> |

### E11. Mock-only cases

| Case | Flags | Screen |
|---|---|---|
| Family full | code `888888` | <img src="img/figma-parity-1110/e2e/m-join-full.jpg" width="160"> |
| Too many tries | code `777777` | <img src="img/figma-parity-1110/e2e/m-join-tries.jpg" width="160"><br>Overlaps the note (problem 8) |
| Already has a Guardian | code `666666` | <img src="img/figma-parity-1110/e2e/m-join-already.jpg" width="160"><br>Points to a locked row (problem 7) |
| Session expired | `-debug.sessionExpired YES` | <img src="img/figma-parity-1110/e2e/m-session-expired.jpg" width="160"><br>"Sesi berakhir", Mulai lagi |
| Notifications off | `-UITestNotifications denied` | <img src="img/figma-parity-1110/e2e/m-notif-denied.jpg" width="160"><br>"Notifikasi mati" |
| Extension switched off | `-UITestExtensionStatus switchedOff` | <img src="img/figma-parity-1110/e2e/m-ext-switchedOff.jpg" width="160"><br>"Anda Belum Terlindungi · Nyalakan sekarang" |
| Extension on some sites only | `someSitesOnly` | <img src="img/figma-parity-1110/e2e/m-ext-someSitesOnly.jpg" width="160"><br>Same Home as switched off |
| Extension not seen yet | `notSeen` | <img src="img/figma-parity-1110/e2e/m-ext-notSeen.jpg" width="160"><br>Same Home as switched off |

## Screen by screen

Left: the app now. Right: the Figma frame. Figma frames show the whole scroll height; the app screenshot shows one screen. Scrolled versions of the same state are `<name>-1`/`-2` (Home) or `-2`/`-3` (Detail) in `img/figma-parity-1110/app/`. Tables are built by `figma-parity-1110-report.mjs` from `figma-parity-1110-map.json` and `img/figma-parity-1110/notes.json`.

<!-- screens:start -->

**86 frames:** 16 ✅ same · 41 🟡 small diff · 22 🟠 clear diff · 3 🔴 missing · 4 ⚪ not shot.

### ONBOARDING (141:5987)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Splash Screen](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3585)<br>`110:3585` | no screenshot | <img src="img/figma-parity-1110/figma/110-3585.jpg" width="160"> | ⚪ not shot | Built: the app has a launch screen with the shield logo. Not captured by the UI test, so it cannot be compared with Figma's blue gradient splash. |
| [Onboarding](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1352-4375)<br>`1352:4375` | <img src="img/figma-parity-1110/app/on-splash-1.jpg" width="160"><br>`app/on-splash-1` | <img src="img/figma-parity-1110/figma/1352-4375.jpg" width="160"> | 🟠 clear diff | Same: title, body text, Lewati and arrow button. Different: the top illustration is grey placeholder cards. Figma shows two phone mockups (Anda Terlindungi home and a 72% warning). |
| [Onboarding](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1352-4039)<br>`1352:4039` | <img src="img/figma-parity-1110/app/on-splash-2.jpg" width="160"><br>`app/on-splash-2` | <img src="img/figma-parity-1110/figma/1352-4039.jpg" width="160"> | 🟠 clear diff | Same: title, body text, Lewati and arrow button. Different: the top illustration is grey placeholder cards. Figma shows a magnifier over a fake bank login page. |
| [Atur Nama](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-3912)<br>`110:3912` | <img src="img/figma-parity-1110/app/on-name.jpg" width="160"><br>`app/on-name` | <img src="img/figma-parity-1110/figma/110-3912.jpg" width="160"> | 🟡 small diff | Same: title, avatars, field, disabled button. Different: the app already shows the hint "*Nama harus terdiri dari maksimal 20 karakter" under the empty field. Figma shows no hint here. |
| [Atur Nama](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4023)<br>`110:4023` | <img src="img/figma-parity-1110/app/on-name-typed.jpg" width="160"><br>`app/on-name-typed` | <img src="img/figma-parity-1110/figma/110-4023.jpg" width="160"> | 🟡 small diff | Same: avatar row, field with clear button, hint. Different: with the keyboard up, the app scrolls the title and large avatar off screen and shows Selanjutnya above the keyboard. Figma keeps the title and hides the button. |
| [Atur Nama](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4271)<br>`110:4271` | <img src="img/figma-parity-1110/app/on-name-tooLong.jpg" width="160"><br>`app/on-name-tooLong` | <img src="img/figma-parity-1110/figma/110-4271.jpg" width="160"> | 🟡 small diff | Same: layout, long name, grey hint. Different: the app keeps Selanjutnya off for a name over 20 characters. Figma shows it on. |
| [Connect with Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=140-5762)<br>`140:5762` | <img src="img/figma-parity-1110/app/on-connect-qr.jpg" width="160"><br>`app/on-connect-qr` | <img src="img/figma-parity-1110/figma/140-5762.jpg" width="160"> | 🟡 small diff | Same: title, tabs, QR frame. Different: the simulator has no camera, so the frame says "Pemindaian tidak tersedia di iPhone ini". The app adds the 14-day copy note and a Nanti saja link. |
| [Connect with Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=926-7974)<br>`926:7974` | <img src="img/figma-parity-1110/app/on-connect-expired-qr.jpg" width="160"><br>`app/on-connect-expired-qr` | <img src="img/figma-parity-1110/figma/926-7974.jpg" width="160"> | 🟠 clear diff | Same: QR tab layout. Different: the red "Kode kadaluarsa" error under the QR frame is not shown; the simulator shows its no-camera text instead. The app adds the 14-day note and Nanti saja. Check on a device. |
| [Connect with Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=141-5887)<br>`141:5887` | <img src="img/figma-parity-1110/app/on-connect-typed.jpg" width="160"><br>`app/on-connect-typed` | <img src="img/figma-parity-1110/figma/141-5887.jpg" width="160"> | 🟡 small diff | Same: title, tabs, code boxes. Different: the app has 6 boxes (Figma shows 5) and keeps Hubungkan off until all 6 digits are in. Figma shows it on. The app adds the 14-day note and Nanti saja. |
| [Connect with Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=926-7992)<br>`926:7992` | <img src="img/figma-parity-1110/app/on-connect-expired.jpg" width="160"><br>`app/on-connect-expired` | <img src="img/figma-parity-1110/figma/926-7992.jpg" width="160"> | 🟡 small diff | Same: code boxes, red error, Hubungkan button. Different: the app spells "kedaluwarsa" (Figma "kadaluarsa"), shows 6 boxes, and adds the 14-day note and Nanti saja. |
| [Aktifkan Ekstensi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=110-4440)<br>`110:4440` | <img src="img/figma-parity-1110/app/on-turnOnExtension.jpg" width="160"><br>`app/on-turnOnExtension` | <img src="img/figma-parity-1110/figma/110-4440.jpg" width="160"> | ✅ same | Same: Safari illustration, steps 01 to 03, ticked consent, Aktifkan Ekstensi button, Tonton Tutorial link. |
| [Aktifkan Ekstensi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=856-19332)<br>`856:19332` | <img src="img/figma-parity-1110/app/on-extensionOn.jpg" width="160"><br>`app/on-extensionOn` | <img src="img/figma-parity-1110/figma/856-19332.jpg" width="160"> | ✅ same | Same: glass shield, "Yeay, kamu berhasil lebih terlindungi!", body text, Selanjutnya button. |
| [Aktifkan Ekstensi · Belum setuju (tombol nonaktif)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1328-13421)<br>`1328:13421` | <img src="img/figma-parity-1110/app/on-turnOnExtension-agreed.jpg" width="160"><br>`app/on-turnOnExtension-agreed` | <img src="img/figma-parity-1110/figma/1328-13421.jpg" width="160"> | ✅ same | Same: unticked consent and grey disabled Aktifkan Ekstensi button. Note: the screenshot file name says agreed but it shows the not-agreed state. |
| [Sheet · Data yang dikirim (dari link)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1328-13313)<br>`1328:13313` | <img src="img/figma-parity-1110/app/on-dataSent-sheet.jpg" width="160"><br>`app/on-dataSent-sheet` | <img src="img/figma-parity-1110/figma/1328-13313.jpg" width="160"> | 🟡 small diff | Same: title, four rows, texts, Mengerti button. Different: the iOS sheet is taller and inset with rounded corners, and the row icons are lighter outlines. |
| [Jadikan Safari Default](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=846-7977)<br>`846:7977` | <img src="img/figma-parity-1110/app/on-safariDefault.jpg" width="160"><br>`app/on-safariDefault` | <img src="img/figma-parity-1110/figma/846-7977.jpg" width="160"> | ✅ same | Same: App Browser illustration, title, three steps, Jadikan Safari default button, Tonton Tutorial link. |
| [Success Screen](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=929-8067)<br>`929:8067` | <img src="img/figma-parity-1110/app/on-connected.jpg" width="160"><br>`app/on-connected` | <img src="img/figma-parity-1110/figma/929-8067.jpg" width="160"> | 🟡 small diff | Same: title, body text, shield with orbit, Selanjutnya. Different: the avatars sit in other spots and the guardian name chip ("Nisrina · Guardian") is missing. Only the "Kamu · Dilindungi" chip shows. |
| [Undangan keluarga · Web · Redesign](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1326-12651)<br>`1326:12651` | no screenshot | <img src="img/figma-parity-1110/figma/1326-12651.jpg" width="160"> | 🔴 missing | Not built as designed. The backend join page exists in a plain form. The redesign (two avatars, split code boxes, Salin kode, "Berlaku 24 jam", Buka di app Shoo button) is not built. |
| [Pribadi/Home kalau belum setting guardian or protected](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1336-2677)<br>`1336:2677` | <img src="img/figma-parity-1110/app/hs-pribadi-cta-0.jpg" width="160"><br>`app/hs-pribadi-cta-0` | <img src="img/figma-parity-1110/figma/1336-2677.jpg" width="160"> | 🟡 small diff | Same: hero, MODE TERAWASI card, recent list, scam tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |

### HOME (141:6094)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Pribadi/Home](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20058)<br>`435:20058` | <img src="img/figma-parity-1110/app/hs-pribadi-0.jpg" width="160"><br>`app/hs-pribadi-0` | <img src="img/figma-parity-1110/figma/435-20058.jpg" width="160"> | 🟡 small diff | Same: hero, recent list, Scam Terbaru tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [Pribadi/Home kalau belum setting guardian or protected](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-10567)<br>`1382:10567` | <img src="img/figma-parity-1110/app/hs-pribadi-cta-0.jpg" width="160"><br>`app/hs-pribadi-cta-0` | <img src="img/figma-parity-1110/figma/1382-10567.jpg" width="160"> | 🟡 small diff | Same frame as 1336:2677. Same: hero, MODE TERAWASI card, list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [To be guardian (guardian not set up yet)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-11008)<br>`1382:11008` | <img src="img/figma-parity-1110/e2e/g-switch.jpg" width="160"><br>`e2e/g-switch` | <img src="img/figma-parity-1110/figma/1382-11008.jpg" width="160"> | ✅ same | Same: family card illustration, "Lindungi orang terdekat", body text, Mulai button. |
| [protected/Home/ no recent warning or blocked](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-17162)<br>`1115:17162` | <img src="img/figma-parity-1110/app/hs-prot-quiet-0.jpg" width="160"><br>`app/hs-prot-quiet-0` | <img src="img/figma-parity-1110/figma/1115-17162.jpg" width="160"> | 🟡 small diff | Same: hero, "Terhubung dengan Virellia" chip, list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home/blocked](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-17294)<br>`1115:17294` | <img src="img/figma-parity-1110/app/hs-prot-blocked-0.jpg" width="160"><br>`app/hs-prot-blocked-0` | <img src="img/figma-parity-1110/figma/1115-17294.jpg" width="160"> | 🟡 small diff | Same: hero, blocked card with 92/100 and "Virellia akan mengecek kembali", list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home/blocked and approved scam](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1373-13100)<br>`1373:13100` | <img src="img/figma-parity-1110/app/hs-prot-blocked-scam-0.jpg" width="160"><br>`app/hs-prot-blocked-scam-0` | <img src="img/figma-parity-1110/figma/1373-13100.jpg" width="160"> | 🟡 small diff | Same: blocked card, "Virellia menandai berbahaya" with badge avatar, list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home/blocked open and approve safe](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1373-12752)<br>`1373:12752` | <img src="img/figma-parity-1110/app/hs-prot-blocked-safe-0.jpg" width="160"><br>`app/hs-prot-blocked-safe-0` | <img src="img/figma-parity-1110/figma/1373-12752.jpg" width="160"> | 🟡 small diff | Same: orange "Situs Mencurigakan!" card, "Virellia menandai aman", list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home/warning](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1363-12167)<br>`1363:12167` | <img src="img/figma-parity-1110/app/hs-prot-warning-0.jpg" width="160"><br>`app/hs-prot-warning-0` | <img src="img/figma-parity-1110/figma/1363-12167.jpg" width="160"> | 🟡 small diff | Same: warning card 70/100, "Virellia akan mengecek kembali", list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home/warning and approved scam](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-2227)<br>`1382:2227` | <img src="img/figma-parity-1110/app/hs-prot-warning-scam-0.jpg" width="160"><br>`app/hs-prot-warning-scam-0` | <img src="img/figma-parity-1110/figma/1382-2227.jpg" width="160"> | 🟡 small diff | Same: red card 70/100, "Virellia menandai berbahaya", list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home /warning approved safe](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1373-12376)<br>`1373:12376` | <img src="img/figma-parity-1110/app/hs-prot-warning-safe-0.jpg" width="160"><br>`app/hs-prot-warning-safe-0` | <img src="img/figma-parity-1110/figma/1373-12376.jpg" width="160"> | 🟡 small diff | Same: orange card 70/100, "Virellia menandai aman", list, tiles. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. |
| [protected/Home/warning (no guardian, MODE TERAWASI)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-2393)<br>`1382:2393` | <img src="img/figma-parity-1110/app/hs-prot-alone-0.jpg" width="160"><br>`app/hs-prot-alone-0` | <img src="img/figma-parity-1110/figma/1382-2393.jpg" width="160"> | 🟠 clear diff | Same: hero, warning card, MODE TERAWASI card, list. Different: the warning card has no Aman / Bahaya buttons. Figma lets the user judge the site themself in this no-guardian mode. |
| [Guardian/Home/ no recently blocked or warning](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=435-20373)<br>`435:20373` | <img src="img/figma-parity-1110/app/home-guardian-members.jpg" width="160"><br>`app/home-guardian-members` | <img src="img/figma-parity-1110/figma/435-20373.jpg" width="160"> | 🟡 small diff | Same: teal hero, three members row, recent list. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. Mock data adds "Tidak terhubung" and a "Ditandai aman" chip. |
| [Guardian/Home/warning](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-2599)<br>`1382:2599` | <img src="img/figma-parity-1110/e2e/e-g-home-warning.jpg" width="160"><br>`e2e/e-g-home-warning` | <img src="img/figma-parity-1110/figma/1382-2599.jpg" width="160"> | 🟡 small diff | Same: "Keluarga Butuh Konfirmasi" hero, warning card, name tag, Aman / Bahaya. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. The reason line is the short detector text, not Figma's paragraph. |
| [Guardian/Home/blocked](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-10314)<br>`1382:10314` | <img src="img/figma-parity-1110/app/home-guardian.jpg" width="160"><br>`app/home-guardian` | <img src="img/figma-parity-1110/figma/1382-10314.jpg" width="160"> | 🟡 small diff | Same: "Keluarga Dalam Ancaman" hero, red card, Aman / Bahaya, list. Different: the top bar sits lower (iOS) and the tabs say Perisai / Aktivitas, not Shield / Activity. The reason is one short line, and the list ends with a Lihat Semua pill. |
| [Guardian/Home · Belum ada orang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1382-10466)<br>`1382:10466` | <img src="img/figma-parity-1110/app/home-guardian-empty.jpg" width="160"><br>`app/home-guardian-empty` | <img src="img/figma-parity-1110/figma/1382-10466.jpg" width="160"> | 🟡 small diff | Same: hero, QR invite card, Bagikan / Salin, Cara Kerja. Different: 6-digit code and a countdown ("berlaku 29:56") where Figma says 24 jam. The MODE TERAWASI card below the fold is not in the shot. |

### Activity (413:1778, 450:4935)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Aktivitas · Semua · Belum ada aktivitas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5490)<br>`480:5490` | <img src="img/figma-parity-1110/app/act-empty-all.jpg" width="160"><br>`app/act-empty-all` | <img src="img/figma-parity-1110/figma/480-5490.jpg" width="160"> | ✅ same | Same: tabs, shield, "Belum ada aktivitas", text, green status chip. Only the tab labels differ (Perisai / Aktivitas). |
| [Aktivitas · Waspada · Kosong](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5520)<br>`480:5520` | <img src="img/figma-parity-1110/app/act-empty-warning.jpg" width="160"><br>`app/act-empty-warning` | <img src="img/figma-parity-1110/figma/480-5520.jpg" width="160"> | ✅ same | Same: Waspada tab, shield, "Tidak ada yang mencurigakan", text, status chip. |
| [Aktivitas · Diblokir · Kosong](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5550)<br>`480:5550` | <img src="img/figma-parity-1110/app/act-empty-blocked.jpg" width="160"><br>`app/act-empty-blocked` | <img src="img/figma-parity-1110/figma/480-5550.jpg" width="160"> | ✅ same | Same: Diblokir tab, shield, "Belum ada situs yang diblokir", text, status chip. |
| [Aktivitas · Semua · Perlindungan mati](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=480-5580)<br>`480:5580` | <img src="img/figma-parity-1110/app/act-off.jpg" width="160"><br>`app/act-off` | <img src="img/figma-parity-1110/figma/480-5580.jpg" width="160"> | ✅ same | Same: grey shield, "Perlindungan sedang mati", text, Aktifkan ekstensi button, "Mati sejak 2 hari lalu". |
| [Aktivitas - Profil Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-15028)<br>`1115:15028` | <img src="img/figma-parity-1110/app/act-pribadi.jpg" width="160"><br>`app/act-pribadi` | <img src="img/figma-parity-1110/figma/1115-15028.jpg" width="160"> | 🟡 small diff | Same: tabs, date groups, rows. Different: the title sits lower, and the Diblokir badge is a solid red pill without icon. Figma uses a light red badge with an icon. |
| [Aktivitas - Profil Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-15424)<br>`1115:15424` | <img src="img/figma-parity-1110/app/act-protected.jpg" width="160"><br>`app/act-protected` | <img src="img/figma-parity-1110/figma/1115-15424.jpg" width="160"> | 🟡 small diff | Same: rows with guardian notes. Different: the app adds a note under every blocked row, and the texts differ: "Menurut Virellia website ini berbahaya!" where Figma says "Virellia menandai bahaya". Solid red Diblokir pill. |
| [Aktivitas - Profil Pribadi : Filtered](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=450-8574)<br>`450:8574` | <img src="img/figma-parity-1110/app/act-protected-warning.jpg" width="160"><br>`app/act-protected-warning` | <img src="img/figma-parity-1110/figma/450-8574.jpg" width="160"> | 🟡 small diff | Same: Waspada tab, date groups, Waspada badges. Different: the title sits lower, and the app adds a guardian note under one row. Figma's last row says "Warning" in English. |
| [Aktivitas - Profil Pribadi : Filtered](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-16415)<br>`1115:16415` | <img src="img/figma-parity-1110/app/act-protected-blocked.jpg" width="160"><br>`app/act-protected-blocked` | <img src="img/figma-parity-1110/figma/1115-16415.jpg" width="160"> | 🟡 small diff | Same: Diblokir tab, solid red pills, guardian notes. Different: the note text says "Menurut Virellia website ini berbahaya!" where Figma says "Virellia menandai bahaya". The title sits lower. |
| [Aktivitas - Profil Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1128-17741)<br>`1128:17741` | <img src="img/figma-parity-1110/app/act-guardian.jpg" width="160"><br>`app/act-guardian` | <img src="img/figma-parity-1110/figma/1128-17741.jpg" width="160"> | 🟡 small diff | Same: avatar picker, rows with member name and time. Different: the third tab says "Bahaya" where Figma says "Diblokir". The title sits lower. |
| [Aktivitas - Profil Guardian / Only one selected](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-15897)<br>`1115:15897` | <img src="img/figma-parity-1110/app/act-guardian-one.jpg" width="160"><br>`app/act-guardian-one` | <img src="img/figma-parity-1110/figma/1115-15897.jpg" width="160"> | 🟡 small diff | Same: "Syahnaz" picker chip, rows with name. Different: the third tab says "Bahaya" where Figma says "Diblokir". The title sits lower. |
| [Guardian/Detail Aktivitas, sebelum di cek](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-4221)<br>`487:4221` | <img src="img/figma-parity-1110/app/dt-unchecked.jpg" width="160"><br>`app/dt-unchecked` | <img src="img/figma-parity-1110/figma/487-4221.jpg" width="160"> | 🟠 clear diff | Older design: gauge with 92%, "Virellia belum melihat link ini" banner, contribution bars per reason. The app builds the newer PRU revision (1252:9851): shield hero, 92/100 score, Aman / Bahaya bar. |
| [Guardian/Detail Aktivitas Waspada](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=487-5990)<br>`487:5990` | <img src="img/figma-parity-1110/app/dt-protected-warning.jpg" width="160"><br>`app/dt-protected-warning` | <img src="img/figma-parity-1110/figma/487-5990.jpg" width="160"> | 🟠 clear diff | Older design: orange gauge "72% Risiko Tinggi" with contribution bars. The app builds the PRU revision: orange shield hero, "Situs Mencurigakan!", 72/100 and Status situs. |
| [protected, sebelum di cek, tanpa angka](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1187-3398)<br>`1187:3398` | <img src="img/figma-parity-1110/app/dt-protected.jpg" width="160"><br>`app/dt-protected` | <img src="img/figma-parity-1110/figma/1187-3398.jpg" width="160"> | 🟠 clear diff | Older design: "BAHAYA" label with no score and a "Virellia belum melihat link ini" banner. The app shows the PRU revision: shield hero, 92/100 score, Diblokir chip. |
| [protected/Detail Aktivitas, sebelum di cek, pake angka](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1196-3985)<br>`1196:3985` | <img src="img/figma-parity-1110/app/dt-protected.jpg" width="160"><br>`app/dt-protected` | <img src="img/figma-parity-1110/figma/1196-3985.jpg" width="160"> | 🟠 clear diff | Older design: BAHAYA label, 92% and the not-checked banner. The app shows the PRU revision: shield hero, "Situs Berbahaya!", 92/100 and Diblokir chip. |
| [protected/Detail Aktivitas, sebelum di cek, pake angka](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1196-4116)<br>`1196:4116` | <img src="img/figma-parity-1110/app/dt-protected-safe.jpg" width="160"><br>`app/dt-protected-safe` | <img src="img/figma-parity-1110/figma/1196-4116.jpg" width="160"> | 🟠 clear diff | Older design: green "Virellia menyatakan aman" banner and blokir terbuka / ditandai aman chips. The app shows the PRU revision: guardian avatar hero, "Virellia Menandai ini Aman", Ditandai aman chip. |

### Detail Aktivitas Guardian REVISI PRU (1252:9850)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Guardian/Detail Aktivitas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1252-9851)<br>`1252:9851` | <img src="img/figma-parity-1110/app/dt-blocked.jpg" width="160"><br>`app/dt-blocked` | <img src="img/figma-parity-1110/figma/1252-9851.jpg" width="160"> | 🟠 clear diff | Same: shield hero, title, 92/100, profile chip, Aman / Bahaya bar. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. |
| [Guardian/Detail Aktivitas Setelah Validasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1252-11249)<br>`1252:11249` | <img src="img/figma-parity-1110/app/dt-validated.jpg" width="160"><br>`app/dt-validated` | <img src="img/figma-parity-1110/figma/1252-11249.jpg" width="160"> | 🟠 clear diff | Same: hero, "Situs Sudah Ditandai Blokir!", score, profile chip. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. The footer is a white bar, not Figma's red banner. |
| [Guardian/Detail Aktivitas Waspada](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1252-10337)<br>`1252:10337` | <img src="img/figma-parity-1110/app/dt-warning.jpg" width="160"><br>`app/dt-warning` | <img src="img/figma-parity-1110/figma/1252-10337.jpg" width="160"> | 🟠 clear diff | Same: orange hero, "Situs Mencurigakan!", 72/100, Aman / Bahaya bar. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. |
| [Guardian/Detail Aktivitas Waspada (Anda menandai aman)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1375-9638)<br>`1375:9638` | <img src="img/figma-parity-1110/app/dt-safe.jpg" width="160"><br>`app/dt-safe` | <img src="img/figma-parity-1110/figma/1375-9638.jpg" width="160"> | 🟠 clear diff | Same: hero, "Anda Menandai ini Aman", 72/100. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. The app footer shows "Diverifikasi aman · Ubah"; Figma keeps Aman / Bahaya. |

### Detail Aktivitas Ortu REVISI PRU (1211:19924)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Ortu/Detail · Bahaya · Belum dicek Virellia](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1211-19925)<br>`1211:19925` | <img src="img/figma-parity-1110/app/dt-protected-verdict.jpg" width="160"><br>`app/dt-protected-verdict` | <img src="img/figma-parity-1110/figma/1211-19925.jpg" width="160"> | 🟠 clear diff | Mapped by content: the frame shows the guardian avatar and "dikonfirmasi Virellia" despite its name. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. |
| [Ortu/Detail · Bahaya · Dikonfirmasi penipuan](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1252-2346)<br>`1252:2346` | <img src="img/figma-parity-1110/app/dt-protected.jpg" width="160"><br>`app/dt-protected` | <img src="img/figma-parity-1110/figma/1252-2346.jpg" width="160"> | 🟠 clear diff | Mapped by content: the frame shows the shield hero and "ditandai oleh Shoo" despite its name. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. |
| [Ortu/Detail · Bahaya · Dikonfirmasi penipuan](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1252-2473)<br>`1252:2473` | <img src="img/figma-parity-1110/e2e/e-p-detail-blocked-safe.jpg" width="160"><br>`e2e/e-p-detail-blocked-safe` | <img src="img/figma-parity-1110/figma/1252-2473.jpg" width="160"> | 🟠 clear diff | Same: guardian avatar with orange badge, "Menandai ini Aman" title, Blokir Dibuka chip, score. Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. |
| [Ortu/Detail · Waspada · Dikonfirmasi penipuan](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1252-2600)<br>`1252:2600` | no screenshot | <img src="img/figma-parity-1110/figma/1252-2600.jpg" width="160"> | ⚪ not shot | Waspada site that the guardian confirmed as scam: red shield, 72/100, Diblokir, "dikonfirmasi Virellia". The app has this state on Home but no detail screenshot. |
| [Ortu/Detail · Waspada · Belum dicek Virellia](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1211-20018)<br>`1211:20018` | <img src="img/figma-parity-1110/app/dt-protected-warning.jpg" width="160"><br>`app/dt-protected-warning` | <img src="img/figma-parity-1110/figma/1211-20018.jpg" width="160"> | 🟠 clear diff | Same: orange hero, "Situs Mencurigakan!", 72/100, Waspada chip, "ditandai oleh Shoo". Different: no numbered summary card (marked page copy, steps 1 to 3). Reason cards show "Sinyal:" instead of Figma's plain line. |
| [Ortu/Detail · Waspada · Ditandai aman Virellia](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1211-20080)<br>`1211:20080` | <img src="img/figma-parity-1110/app/dt-protected-safe.jpg" width="160"><br>`app/dt-protected-safe` | <img src="img/figma-parity-1110/figma/1211-20080.jpg" width="160"> | 🟠 clear diff | Different: the app shows the guardian avatar hero and title "Virellia Menandai ini Aman". Figma keeps the orange shield, "Situs Mencurigakan!", and a "Ditandai aman" chip with V avatar. No numbered summary card. |

### Profile (416:9961, 455:9046)

| Frame | App now | Figma | Status | Notes |
|---|---|---|---|---|
| [Profile/Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14593)<br>`1115:14593` | <img src="img/figma-parity-1110/app/pf-guardian.jpg" width="160"><br>`app/pf-guardian` | <img src="img/figma-parity-1110/figma/1115-14593.jpg" width="160"> | 🟡 small diff | Same: header card, members list, Akun and Preferensi lists, Hapus Akun. Different: the app adds a Bagikan undangan button and a Privasi · Cek online section. The third stat says Peringatan, not Pemeriksaan. |
| [Profile/Guardian · Belum ada orang](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14489)<br>`1115:14489` | <img src="img/figma-parity-1110/app/pf-guardian-empty.jpg" width="160"><br>`app/pf-guardian-empty` | <img src="img/figma-parity-1110/figma/1115-14489.jpg" width="160"> | 🟡 small diff | Same: header card, empty state with Undang Keluarga, Akun list. Different: the app adds a Bagikan undangan button on the header card. The top bar sits lower. |
| [Profile/Pribadi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14392)<br>`1115:14392` | <img src="img/figma-parity-1110/app/pf-pribadi.jpg" width="160"><br>`app/pf-pribadi` | <img src="img/figma-parity-1110/figma/1115-14392.jpg" width="160"> | 🟡 small diff | Same: header card with stats, Perlindungan, Akun, Preferensi. Different: the app shows the MODE GUARDIAN "Menjadi Guardian" card (Figma has it only in 1115:14279) and a Bagikan undangan button. |
| [Profile/Pribadi · Ajak jadi Guardian](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14279)<br>`1115:14279` | <img src="img/figma-parity-1110/app/pf-pribadi.jpg" width="160"><br>`app/pf-pribadi` | <img src="img/figma-parity-1110/figma/1115-14279.jpg" width="160"> | 🟡 small diff | Same: header card, MODE GUARDIAN card with Menjadi Guardian, Perlindungan, Akun, Preferensi. Different: the app adds a Bagikan undangan button on the header card. |
| [Profile/Pribadi · Konfirmasi hapus akun](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14173)<br>`1115:14173` | <img src="img/figma-parity-1110/e2e/e-p-delete-confirm.jpg" width="160"><br>`e2e/e-p-delete-confirm` | <img src="img/figma-parity-1110/figma/1115-14173.jpg" width="160"> | 🟡 small diff | Same: Hapus akun? alert, Batal / Hapus buttons. Different: the app adds "Adhella tidak akan menerima peringatanmu lagi." The alert sits higher because the page is scrolled. |
| [Profile/Pribadi (protected)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-10275)<br>`455:10275` | <img src="img/figma-parity-1110/app/pf-protected.jpg" width="160"><br>`app/pf-protected` | <img src="img/figma-parity-1110/figma/455-10275.jpg" width="160"> | 🟡 small diff | Same: header card with Terhubung chip, Terhubung row, Perlindungan, Akun, Preferensi. Different: the app adds a Privasi · Cek online section. The top bar sits lower. |
| [Profile/Pribadi (protected, bawah)](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-10571)<br>`455:10571` | <img src="img/figma-parity-1110/app/pf-protected.jpg" width="160"><br>`app/pf-protected` | <img src="img/figma-parity-1110/figma/455-10571.jpg" width="160"> | 🟡 small diff | This frame is the top of the protected profile, so it maps to the top shot. Same: header card, Terhubung, Perlindungan, Akun. Different: the top bar sits lower. |
| [Guardian/Detail Orang Dilindungi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1128-18167)<br>`1128:18167` | <img src="img/figma-parity-1110/app/pf-member.jpg" width="160"><br>`app/pf-member` | <img src="img/figma-parity-1110/figma/1128-18167.jpg" width="160"> | 🟡 small diff | Same: header card, stats, Perlindungan, recent list, Putuskan koneksi. Different: the app adds a Perangkat row and a "Perlindungan aktif" chip. The toggle says "Kabari saya" where Figma says "Pop up notification". |
| [Guardian/Detail Orang Dilindungi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1128-18472)<br>`1128:18472` | <img src="img/figma-parity-1110/app/pf-member.jpg" width="160"><br>`app/pf-member` | <img src="img/figma-parity-1110/figma/1128-18472.jpg" width="160"> | 🟡 small diff | Same frame as 1128:18167. Same: header card, Perlindungan, recent list, Putuskan koneksi. Different: extra Perangkat row and "Perlindungan aktif" chip; "Kabari saya" replaces "Pop up notification". |
| [Guardian/Detail Orang Dilindungi · Putuskan](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-10676)<br>`416:10676` | <img src="img/figma-parity-1110/app/pf-member-disconnect.jpg" width="160"><br>`app/pf-member-disconnect` | <img src="img/figma-parity-1110/figma/416-10676.jpg" width="160"> | ✅ same | Same: avatar with red badge, "Putuskan koneksi dengan Syahnaz?", body text, red button, Batal. The iOS sheet is inset with rounded corners. |
| [Pengaturan/Mode akun](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9515)<br>`455:9515` | <img src="img/figma-parity-1110/app/pf-protected-connection.jpg" width="160"><br>`app/pf-protected-connection` | <img src="img/figma-parity-1110/figma/455-9515.jpg" width="160"> | 🟠 clear diff | Same: Akun Tertaut title, two avatars with dots, two toggles. Different: toggles say "Segera hadir" instead of Figma's descriptions. Putuskan koneksi is locked grey ("Harus menggunakan akun Virellia"), not red. |
| [Pengaturan/Mode akun](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=457-10896)<br>`457:10896` | <img src="img/figma-parity-1110/app/pf-protected-connection.jpg" width="160"><br>`app/pf-protected-connection` | <img src="img/figma-parity-1110/figma/457-10896.jpg" width="160"> | 🟠 clear diff | Same: Akun Tertaut layout. Different: Figma has Kirim link off and an active red Putuskan koneksi. The app shows both toggles on as "Segera hadir" and locks Putuskan koneksi. |
| [Pengaturan/Mode akun](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1279-9348)<br>`1279:9348` | no screenshot | <img src="img/figma-parity-1110/figma/1279-9348.jpg" width="160"> | 🔴 missing | The protected side cannot disconnect: Putuskan koneksi is locked in Akun Tertaut, so this sheet ("Putuskan koneksi dengan Adhella?") is not built. Old map e2e/p-connect showed the Mode akun page. |
| [Pengaturan/Kelola profil](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12854)<br>`416:12854` | <img src="img/figma-parity-1110/app/pf-manage.jpg" width="160"><br>`app/pf-manage` | <img src="img/figma-parity-1110/figma/416-12854.jpg" width="160"> | 🟡 small diff | Same: avatar with edit badge, Ubah avatar, Info pribadi, Hapus akun. Different: the app has no Nomor HP row. Terhubung dengan lists the protected members. |
| [Pengaturan/Kelola profil](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=462-11043)<br>`462:11043` | <img src="img/figma-parity-1110/app/pf-protected-manage.jpg" width="160"><br>`app/pf-protected-manage` | <img src="img/figma-parity-1110/figma/462-11043.jpg" width="160"> | ✅ same | Same: avatar, "Aktif sejak" chip, Nama field, Hapus akun card. |
| [Pengaturan/Kelola profil · Sheet ubah avatar](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1286-12383)<br>`1286:12383` | no screenshot | <img src="img/figma-parity-1110/figma/1286-12383.jpg" width="160"> | ⚪ not shot | Built (ProfileSheets.swift, Ubah avatar). No screenshot of the sheet. |
| [Pengaturan/Kelola profil · Sheet ubah nama](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1286-12451)<br>`1286:12451` | no screenshot | <img src="img/figma-parity-1110/figma/1286-12451.jpg" width="160"> | ⚪ not shot | Built (ProfileSheets.swift, Ubah nama). No screenshot of the sheet. |
| [Pengaturan/Kelola profil · Sheet tambah nomor HP](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1286-12515)<br>`1286:12515` | no screenshot | <img src="img/figma-parity-1110/figma/1286-12515.jpg" width="160"> | 🔴 missing | Tambah nomor HP sheet is not built. The app also has no Nomor HP row in Kelola profil. |
| [Pengaturan/Notifikasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14717)<br>`1115:14717` | <img src="img/figma-parity-1110/app/pf-notifications.jpg" width="160"><br>`app/pf-notifications` | <img src="img/figma-parity-1110/figma/1115-14717.jpg" width="160"> | 🟠 clear diff | Different: Peringatan has two toggles (Situs berbahaya, Situs diblokir) where Figma has one Pop up notification. "Perlindungan mati" replaces "Ekstensi keluarga dimatikan". The app adds Ringkasan mingguan and Jam tenang. |
| [Pengaturan/Notifikasi](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9627)<br>`455:9627` | <img src="img/figma-parity-1110/app/pf-protected-notifications.jpg" width="160"><br>`app/pf-protected-notifications` | <img src="img/figma-parity-1110/figma/455-9627.jpg" width="160"> | 🟠 clear diff | Same: Situs berbahaya and Situs diblokir toggles. Different: the Akun Terhubung · Link terblokir toggle is missing. The app adds a "Notifikasi mati · Nyalakan" banner (simulator has notifications off). |
| [Pengaturan/Bahasa](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-12986)<br>`416:12986` | <img src="img/figma-parity-1110/app/pf-language.jpg" width="160"><br>`app/pf-language` | <img src="img/figma-parity-1110/figma/416-12986.jpg" width="160"> | ✅ same | Same: Bahasa Indonesia and English rows, radio, footnote. |
| [Pengaturan/Bahasa](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9697)<br>`455:9697` | <img src="img/figma-parity-1110/app/pf-language.jpg" width="160"><br>`app/pf-language` | <img src="img/figma-parity-1110/figma/455-9697.jpg" width="160"> | ✅ same | Same: Bahasa Indonesia and English rows, radio, footnote. |
| [Pengaturan/Tema](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-13007)<br>`416:13007` | <img src="img/figma-parity-1110/app/pf-theme.jpg" width="160"><br>`app/pf-theme` | <img src="img/figma-parity-1110/figma/416-13007.jpg" width="160"> | ✅ same | Same: three theme cards, radios, footnote, Kurangi efek kaca toggle. Mock data selects Otomatis; Figma shows Terang. |
| [Pengaturan/Tema](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9718)<br>`455:9718` | <img src="img/figma-parity-1110/app/pf-theme.jpg" width="160"><br>`app/pf-theme` | <img src="img/figma-parity-1110/figma/455-9718.jpg" width="160"> | ✅ same | Same: three theme cards, Otomatis selected, footnote, Kurangi efek kaca toggle. |
| [Pengaturan/Aksesibilitas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=1115-14753)<br>`1115:14753` | <img src="img/figma-parity-1110/app/pf-accessibility.jpg" width="160"><br>`app/pf-accessibility` | <img src="img/figma-parity-1110/figma/1115-14753.jpg" width="160"> | 🟡 small diff | Same: preview card, slider, Tampilan and Saat ada peringatan toggles. Different: the Bacakan peringatan line says "Skor dan alasan dibacakan lewat VoiceOver"; Figma says Shoo reads it without VoiceOver. Settings values differ (mock). |
| [Pengaturan/Aksesibilitas](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9785)<br>`455:9785` | <img src="img/figma-parity-1110/app/pf-accessibility.jpg" width="160"><br>`app/pf-accessibility` | <img src="img/figma-parity-1110/figma/455-9785.jpg" width="160"> | ✅ same | Same: preview card, slider, toggles, Bacakan peringatan text. Only the setting values differ (Standar, Kurangi gerakan off). |
| [Pengaturan/Tentang Shoo](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=416-13147)<br>`416:13147` | <img src="img/figma-parity-1110/app/pf-about.jpg" width="160"><br>`app/pf-about` | <img src="img/figma-parity-1110/figma/416-13147.jpg" width="160"> | 🟡 small diff | Same: logo, name, tagline, link rows, footer. Different: the app adds Lisensi pihak ketiga and says "Hubungi kami" where Figma says "Kontak". The long email wraps to two lines. |
| [Pengaturan/Tentang Shoo](https://www.figma.com/design/6PgxbrY0LSkcdaJ5u4YBJP/-CH7--Shoo-Scam-App?node-id=455-9858)<br>`455:9858` | <img src="img/figma-parity-1110/app/pf-about.jpg" width="160"><br>`app/pf-about` | <img src="img/figma-parity-1110/figma/455-9858.jpg" width="160"> | 🟡 small diff | Same: logo, rows, footer. Different: the email is Apple.a.day.bali@gmail.com on two lines where Figma shows halo@shoo.id. Version reads "1.0 (6)". |

<!-- screens:end -->

## How to repeat

1. Figma: open the file in Figma with the TalkToFigma plugin, join a channel, then list and export the 8 sections at 1x (same relay as `figma-export.mjs`). Convert with `sips` to JPEG 402 px wide into `img/figma-parity-1110/figma/`.
2. App screens: `TEST_RUNNER_QA_SHOT_DIR=<dir> xcodebuild test -only-testing:ShooAppUITests/FigmaParityUITests` on an iPhone 17 Pro simulator.
3. Edge cases: `supabase start` in `backend/db`, `pnpm dev` in `backend/api`, `PORT=8789 node src/dev-server.mjs` in `ai/`, and a static server for the test pages on port 8899. Launch the app with `-debug.aiBaseURL http://localhost:8789`. Each new test needs a new registrable domain, because the block memory keys on it. `*.localhost` gives a new one per subdomain.
4. Notifications: copy the body the server logs into an `.apns` file and run `xcrun simctl push <udid> com.shoo.app <file>`.
5. Then run `node plan/alief/qa/figma-parity-1110-report.mjs`.
