# Fase 27 — Audit state machine tersirat + perbaikan (app + backend)

| Field | Nilai |
|---|---|
| Track | c (app + backend; sub-fase tidak saling menunggu kecuali disebut) |
| Branch | 27-0 `docs/alief-fase-27-state-machines` (plan + bukti, **tanpa** file test di `backend/` / `ios/`) · 27a `fix/PF-01-become-protected-atomic` · 27b `fix/DT-06-verdict-row-frozen` (tunggu Q4) · 27c `fix/GD-07-rejected-stays-rejected` · 27d `fix/ON-04-invite-onboarding-states` · 27e `fix/GD-01-home-verdict-state` · 27f `fix/PR-05-activity-list-states` · 27g `fix/GD-06-push-tap-and-clear` · 27h `fix/PF-01-session-lifecycle` · 27i `fix/PF-01-settings-rollback` · 27j `fix/PF-01-protected-copy-settings` · 27k (rendah, satu branch per butir, §27k) · 27z `docs/alief-R4-state-machine` |
| Prasyarat | 27a, 27c–27i, 27j (tanpa butir Q2): tidak ada. 27b: jawaban Q4 (makna kontrak). Butir quiet hours 27j: Q2. Filter riwayat (F-B5): Q1. "Dimatikan" ke Guardian (F-A9): Q3. Desain consent jalur undangan: Q5 (27d jalan dengan usulan, ditinjau di PR) |
| Urutan | 27-0 → 27d dan 27a dulu → 27e, 27f, 27g, 27h → 27c, 27i, 27j → 27b (setelah Q4) → 27k → 27z |
| Requirement | ON-04, PR-01/03/05, GD-01/06/07, DT-06, PF-01; SECURITY §3 P13 (hapus/putus = langsung hilang); D-alief-40 (data tanpa tujuan dihapus); hard rule CLAUDE.md 1–4 + 7 (hanya `backend/` + `ios/ShooApp/`, kontrak tidak berubah, satu branch = satu PRD ID, pertanyaan lewat issue) |
| Model + reviewer ECC | Opus 5.5 · backend: `ecc:typescript-reviewer` → `ecc:database-reviewer` → `ecc:security-reviewer` · app: `ecc:swift-reviewer` → `ecc:security-reviewer` (satu per satu, tidak paralel) |
| Fase berikutnya | 27z memperbarui `ref/R4-state-machine.md` setelah 27a + 27d merge |

## Tujuan

**Asal.** Prompt "Find all the implicit state machines in my app" (video TikTok @arjay_mccandless, 11 Nov 2026). State machine tersirat = siklus hidup yang aturannya tersebar di banyak fungsi, flag, kolom nullable, cron, dan handler. Setiap fungsi benar dan semua test hijau, tapi gabungannya bisa masuk keadaan yang tidak pernah direncanakan.

**Yang dilakukan (11 Nov 2026, `main` `02d590e4`, setelah batch #402):**

1. Tiga audit baca-saja: backend, ShooApp, lalu area yang belum tersentuh (live, replica, blocklist, push, cron, Profile, push tap).
2. Setiap temuan sedang/tinggi diverifikasi dengan **test yang menegaskan perilaku benar** sehingga **gagal di kode sekarang**; kegagalan itu buktinya. Test ada di `log/fase-27-repro/`. Sub-fase memindahkannya ke suite dan **menulis ulang harapannya sesuai keputusan K** (tabel "Test repro → test permanen").
3. Temuan rendah diverifikasi dengan membaca kode. Yang belum terbukti ditandai **BT**.
4. Plan direview ulang sampai tidak ada temuan kritis/tinggi (Riwayat verifikasi).

**Hasil akhir.** Semua temuan tinggi dan sedang diperbaiki dengan test merah → hijau, atau ditanyakan lewat issue bila menyentuh kontrak/produk. Temuan rendah diputuskan satu per satu. Tidak ada perubahan `contracts/`, `project.yml`, `ShooShared/`, atau folder tim lain.

## Bacaan wajib

- Bukti: `log/fase-27.md`, `log/fase-27-repro/fase27-repro.test.ts.txt`, `log/fase-27-repro/Fase27ReproTests.swift.txt`, `log/fase-27-repro/audit-env.sh.txt`
- Backend: `src/routes/devices.ts:163-199` (become-protected) dan `:205-240` (DELETE + retry), `src/services/family.ts:58-91`, `src/db/repo/joinAttempts.ts` (urutan kunci device → IP), `src/db/repo/devices.ts:140-155,215-260`, `src/db/repo/scans.ts:28-57,478-495,518`, `src/db/repo/verdicts.ts:36-125`, `src/db/repo/codes.ts`, `src/routes/scans.ts:186-262`, `src/services/push/notify.ts`, `src/cron/notifications.ts:80-100`, `src/cron/retention.ts`, migrasi `20261022120000_hardening.sql:12-14` (grant kolom `blocklist_entries`), `20261102190630_admin_schema.sql:138-146,252-356` (`admin.review_decisions`, `admin.vote`, `add`), `20261028130000_notification_settings.sql:13-17`, `backend/db/supabase/tests/admin_grants.test.sql` + `hardening.test.sql` (pola grant fungsi)
- App: `App/AppEnvironment.swift:188` (`needsDataConsent`), `:200-228` (`register`), `:234-260` (`sceneBecameActive`), `:310-323` (`handleUnauthorized`/`markSessionExpired`), `:351-357` (`restartOnboarding`), `:384-402` (`becomeProtected`), `:436-450` (`openPush`); `App/RootView.swift:12-26`; `Features/Onboarding/OnboardingModel.swift:70-260`; `Features/Pairing/ConnectModel.swift`; `Features/Shield/GuardianHomeModel.swift:136-218`; `Features/Activity/ActivityModel.swift:132-290`, `ActivityView.swift:90`; `Features/Main/MainTabView.swift:66-79`; `Features/Profile/MemberDetailModel.swift:108-128`, `MemberDetailView.swift:50-58`, `ProfileModel.swift:282-295,340-350`, `ProfilePages.swift:28-36,930-1040`; `Features/Pairing/FamilyCodeModel.swift:190-200`; `Data/ApiRepository.swift:38-69`, `Data/SessionStore.swift:24-30,121,140`, `Data/MockRepository.swift:365-375`; `Onboarding/DataConsentView.swift`
- Kontrak (baca saja): `contracts/api.md:57` (**satu baris per situs**, push pertama + eskalasi), Devices, Family, Verdicts per link (#241)
- Plan: `SECURITY.md` §3 P13, `log/DECISIONS.md` D-alief-40, `ref/R4-state-machine.md` (usang, 27z), memori "Backend vitest wipes dev DB", "UI PR screenshots", "No parallel subagents"

## Metode verifikasi (bisa diulang)

- **DB terpisah.** `vitest` mengosongkan DB di `SHOO_TEST_DB_URL`; `wrangler dev` sesi lain memakai DB `postgres` lokal. Semua run memakai DB `shoo_audit` (skema dari `pg_dump --schema-only`, data referensi `admin.*` sebagian). Cara membuat + skrip env: `log/fase-27.md` §DB.
- **Baseline `shoo_audit`:** 724/732 lulus. 7 gagal di trigger arsip admin (`fragments.test.ts` 4, `scans-rdap.test.ts` 2, `verdicts.test.ts` 1) karena data `admin` tidak lengkap; bukan temuan fase ini.
- **Simulator terpisah.** "Shoo Fase27" (`008727CA-5EB3-4FD4-9817-3DAFEDB0338F`, iPhone 17), derived data di scratchpad. Run tanpa batas waktu macet 27 menit; **selalu** `-test-timeouts-enabled YES -maximum-test-execution-time-allowance 60`.
- **Batas.** Race lewat `call()` (route di pool workerd) + koneksi `postgres()` kedua yang memegang kunci macet 20 s. Race diuji di level fungsi (dua koneksi `postgres()` biasa, hook jeda yang disuntik), bukan lewat `call()`.

## Temuan terverifikasi

Tingkat: T tinggi · S sedang · R rendah. Bukti: **test** = test repro gagal di `02d590e4` · **baca** = dari kode · **BT** = belum terverifikasi.

### Backend

| ID | T | Temuan | Bukti | Sub-fase |
|---|---|---|---|---|
| F-B1 | S | Guardian tanpa anggota memakai **kodenya sendiri** di `POST /devices/me/protected`: salinan Protected bergabung ke device lama, lalu `deleteDevice(oldId)` (`routes/devices.ts:196`) men-cascade link itu. Respons 200 menyebut Guardian; `GET /devices/me` berikutnya `guardian: null`. `joinFamily` tidak menolak `found.guardianId === oldId` (`services/family.ts:67-78`) | test `F-B1`: "200 but the new protected device has no guardian" | 27a |
| F-B2 | S | Cek `has_members` = check-then-act: `count(*)` tanpa kunci (`routes/devices.ts:183-184`). Anggota yang bergabung dengan kode Guardian lama di antara cek dan `deleteDevice(oldId)` kehilangan link + verdict tanpa push | test `F-B2 replay` (urutan panggilan sama dengan route): "Mom silently lost her guardian" | 27a |
| F-B3 | S | Join commit (`:191`) sebelum delete (`:196`). Delete gagal (55P03/40P01; role `shoo_api` `lock_timeout=5s`) → 500, client mencoba lagi dengan token lama → salinan kedua ikut bergabung, memakan 1 dari 3 slot; salinan yatim tidak dibersihkan retensi (aturan 30 hari melewati device terhubung) | test `F-B3 state-only`: "expected 2 to be 1". Pemicu di produksi **BT**, tapi `lock_timeout` 5 s nyata | 27a |
| F-B6 | S | Batas percobaan join di become-protected tidak bekerja: tiap percobaan memakai id salinan baru (`routes/devices.ts:187-191`), jadi batas 5/device/600 s (`joinAttempts.ts:3`) tidak pernah tercapai, dan baris kegagalan per IP ikut terhapus cascade bersama salinan (`init.sql:42`, kolom `join_attempts.device_id`). Yang tersisa hanya 30/jam per device (`rateLimit.ts:21`, dari #402) | baca (review ronde 1) | 27a |
| F-B4 | S | Verdict `safe` terlepas dari barisnya: kunjungan ulang dengan skor lebih tinggi menulis ulang `url`/judul/sinyal baris yang sama (`db/repo/scans.ts:39-42`); join Activity memakai link sekarang (`:486-489`). Baris tampil tanpa verdict; `safe` lama di `/a` tinggal sampai 14 hari dan tidak ada scan yang menyebut `/a`, jadi tidak bisa direvisi | test `F-B4`: `{ rowVerdict: null, orphanSafe: 1 }` | 27b (Q4) |
| F-B5 | R/? | Guardian melihat scan anggota **sebelum** terhubung (`routes/scans.ts:250` tanpa filter waktu link). Dengan kode kedaluwarsa yang dipakai ulang (`codes.ts:34-36`), Guardian asing bisa melihat riwayat | test probe `F-B5` | Q1 |
| F-B7 | R | Domain yang **ditolak** reviewer kembali ke antrean: dukungan 0 menghapus baris "rejected or not" (`verdicts.ts:114-116`, sengaja, D-alief-40), lalu `not_safe` berikutnya menyisipkan baris baru dengan `rejected_at` null | test `F-B7` (perlu diubah memakai `admin.vote`, lihat tabel test) | 27c |
| F-B8 | R | Favicon tanpa flag siap: path ditulis sebelum upload (`scans.ts:185`, `favicons.ts:56-61`) | baca | 27k |
| F-B9 | R | Replica "reserved" bisa macet 14 hari kalau `waitUntil` mati setelah `scans.ts:307` | **BT** | 27k |
| F-B10 | R | Arsip admin menyimpan data kunjungan pertama (`on_scan_insert` hanya insert) | baca | terima |
| F-B11 | R | Check-then-act lain: GET /scans membership vs list, target push dibaca sebelum respons, cap push hitung lalu kirim | baca | terima |
| F-B12 | R | Kelas advisory lock ganda: kelas 4 (`scans.ts:180` favicon + `verdicts.ts:21` domain), kelas 7 (`scans.ts:30` + admin `(7,1)`); komentar `scans.ts:269` keliru | baca | 27k |
| F-B13 | R | Baris yang terus dikunjungi kedaluwarsa menurut `created_at` (`retention.ts:241`) padahal `detected_at` maju | baca | terima (janji retensi), catat di Q1 |
| F-B14 | R | `GET /verdicts?domain=` (usang) memakai `safe` terbaru dari link mana pun | baca, sesuai kontrak | ditutup |
| F-N4 | S | Guardian → Protected menyalin `weekly_summary` + `quiet_hours` (`db/repo/devices.ts:145-150`), padahal halaman Protected menyembunyikan keduanya (`ProfilePages.swift:941`). Default kolom `quiet_hours = true` 22:00–06:00 (`notification_settings.sql:16-17`) juga menahan push **waspada** Protected tentang scan miliknya (push blokir tetap terkirim, `notify.ts:35`) | baca + `settings.test.ts:296-312` mengunci perilaku sekarang | 27j, Q2 |
| F-N8 | R | Cursor blocklist memakai waktu tulis (`clock_timestamp()`), bukan waktu commit | **BT** | terima |
| F-N9 | R | Paging Activity pada `(detected_at, id)`; baris halaman 2 yang dikunjungi ulang melompat ke atas cursor | baca | terima + dokumentasi |
| F-N10 | R | Cron "Protection off": `limit 200` sebelum filter quiet hours (`cron/notifications.ts:84-96`) | baca | 27k |

### App (ShooApp)

| ID | T | Temuan | Bukti | Sub-fase |
|---|---|---|---|---|
| F-A1 | T | Instal baru lewat link undangan: Connect mendaftarkan device (`OnboardingModel.swift:169`) sebelum consent (consent normal di ON-04, `:148`). `register()` menyimpan mode → `needsDataConsent` (`AppEnvironment.swift:188`) → `RootView.swift:18` mengganti `OnboardingFlow` dengan `DataConsentView`. Setelah dijawab, model baru mulai di `.done` (`OnboardingModel.swift:76-77`) → ON-04, Safari default, sukses, izin notifikasi terlewati. Selain itu `session.save` (`AppEnvironment.swift:204`) sudah memberi extension token + `apiBaseURL`, jadi scan + salinan halaman bisa terkirim sebelum consent (`dataConsent` hanya mengatur URL AI, `SessionStore.swift:140`) | test `inviteJoinDoesNotSwapOnboardingOutForConsent`, `protectedAfterInviteStillReachesTurnOnExtension` | 27d |
| F-A2 | S | Join undangan yang gagal sudah menyimpan `mode=.protected` (register dulu, `:169-170`). Back tersembunyi (`canGoBackToName` = `mode == nil`, `:133`), "Not now" lanjut sebagai Protected tanpa Guardian; komentar `:178` "nothing is saved yet" salah. Keadaan itu didukung app (Profile menawarkan Connect lagi), jadi tidak ada data hilang, tapi pengguna terkunci di mode yang tidak dipilih | test `failedInviteJoinSavesNoMode` × 3 kode | 27d |
| F-A14 | R | App ditutup setelah registrasi undangan → buka lagi langsung `.done` (akar sama dengan F-A1) | baca | 27d |
| F-A3 | S | "Punya kode undangan?": 401 dari request lama tiba setelah server menukar device tapi sebelum `session.save` (`AppEnvironment.swift:387`) → `handleUnauthorized` (`:310-313`) mencocokkan token lama = token sekarang → `markSessionExpired()` mengosongkan sesi; `sessionExpired` tetap true setelah sesi baru disimpan | baca; timing **BT** | 27h |
| F-A4 | S | Verdict di Home ditimpa refresh yang membaca list sebelum verdict (`GuardianHomeModel.decide` tanpa epoch; Detail punya `verdictEpoch`, `DetailModel.swift:129-136`) | test `homeVerdictIsNotUndoneByAnOlderRefresh` | 27e |
| F-N1 | R | `GuardianHomeModel.decide` memasang verdict ke **semua** scan pemilik dengan domain sama (`GuardianHomeModel.swift:207`), padahal backend per link (#241). Dalam praktik tidak terlihat: backend menyimpan satu baris per owner + domain (`scans.ts:30-45`, `api.md:57`), jadi dua kartu domain sama tidak datang dari server. Tetap dirapikan (per id) karena aturan ini menyesatkan dan `MockRepository.swift:369-371` meniru aturan yang salah | baca | 27e |
| F-A5 | S | Spinner "memuat lagi" Activity macet: `loadMore` keluar tanpa reset `isLoadingMore` saat generasi berganti (`ActivityModel.swift:180-187`); refresh gagal tidak mereset (`:273-282`) | test `loadingMoreSpinnerClearsAfterAFailedRefresh` | 27f |
| F-A6 | S | Setelah Pribadi → Protected, tab Activity memakai model device yang sudah dihapus: `screenIdentity` = repository + familyMode (`MainTabView.swift:76-78`); `ActivityView.swift:90` hanya memuat kalau belum `.loaded` | baca | 27f |
| F-A15 | R | Verdict di Detail tidak muncul di list Activity (model terpisah, tanpa refresh saat kembali) | baca | 27f |
| F-N2 | S | Push Protected tentang scan miliknya (backend `ownPush` dengan `scanId`, `routes/scans.ts:192`, `notify.ts:72`) dibuka ke Shield: `AppEnvironment.swift:442` hanya Guardian; komentar di atas `openPush` salah. `PushTests.swift:137` mengunci perilaku salah | baca + test lama | 27g |
| F-N3 | S | Putus anggota dari halaman detail anggota tidak menghapus push yang tampil (`MemberDetailModel.swift:112-126`, `MemberDetailView.swift:54-56`), padahal `FamilyCodeModel.swift:196` menghapusnya (P13) | baca | 27g |
| F-A8 | S | Daftar lagi di peluncuran yang sama tidak mengirim info device: `register()` (`AppEnvironment.swift:200-228`) tidak mereset `sentDeviceInfo` (`:27`), `becomeProtected` mereset (`:398`) → zona waktu kosong | baca | 27h |
| F-N7 | R | "Hapus akun" bisa berakhir di "Session expired": 401 request lain dengan token sama sebelum respons DELETE → `markSessionExpired`; jalur hapus tidak mereset `sessionExpired` | baca; timing **BT** | 27h |
| F-A12 | R | `me()` lama yang menjawab setelah `becomeProtected` menulis `setGuardian(nil)` (`ApiRepository.swift:42`) | **BT** | 27h |
| F-A13 | R | Key `link.autoSend`, `history.shareWarnings`, `notify.linkVerified` tidak ada di `SessionStore.appKeys` (`:24`); `restartOnboarding`/`leaveDemo` tidak menghapusnya. Extension sudah membaca `link.autoSend` + `history.shareWarnings` (`contracts/app-group-keys.md:23-24`), jadi nilai `false` dari akun lama menghentikan scan `warning` akun berikutnya (Guardian tidak melihatnya) | baca | 27h |
| F-A11 / F-N5 | R | Rollback toggle notifikasi memakai `before` tiap panggilan (`ProfileModel.swift:282-294`) | baca | 27i |
| F-N6 | R | Quiet hours mulai = selesai = "sepanjang hari" di server (`quiet.ts:52`); sheet menyimpan pasangan apa pun (`ProfilePages.swift:1005+`) | baca | 27i |
| F-A9 | R | "Dimatikan" di HP Protected tidak sampai ke Guardian sampai jendela `extensionLastSeenAt` habis (`AppEnvironment.swift:234-250`) | baca, sesuai kontrak `api.md:29` | Q3 |
| F-A10 | R | `FamilyCodeModel.refreshCode` bisa jalan paralel tanpa token request | **BT** | 27k |
| F-A16 | R | Flag Debug (`-UITestCheckStats`, `-UITestReset`) meninggalkan data | baca, Debug saja | ditutup |
| F-A7 | – | Live Activity tidak pernah mulai | sudah diperbaiki di `main` (#386 lewat #402, `App/LiveActivityTokens.swift`) | ditutup |

### Yang sudah aman (dicek, tidak perlu kerja)

Verdict setelah anggota keluar (`for share`, `verdicts.test.ts:140`); dua Guardian memutuskan bersamaan (PK `family_links.protected_id`); slot terakhir paralel (`family.test.ts:287`); replica ready tanpa path (CHECK); klaim live/reminder atomik; retensi vs hapus device (`retention.test.ts:420-509`); link screenshot/favicon/replica (HMAC, akses DB per request, no-store); `ops.ts`; `auth.ts`; window rate limit; 410 APNs compare-and-clear; DeepLink; Detail saat 404; Detail Protected (`EvidenceList.swift:32`) dan akses pemilik `GET /scans/{id}` (`db/repo/scans.ts:518`); `SessionStore` membersihkan App Group; double tap Turn on/Connect/verdict/remove/save/delete.

## Peta dampak

| Sisi | Berubah | Tidak berubah |
|---|---|---|
| Backend | `routes/devices.ts`, `services/family.ts`, `db/repo/joinAttempts.ts` (tanpa ubah urutan), `db/repo/devices.ts`, `db/repo/verdicts.ts`, `cron/notifications.ts`; 27b `db/repo/scans.ts` (setelah Q4); migrasi baru hanya 27c (fungsi `security definer`) dan 27k F-B8 kalau dikerjakan (`favicon_ready_at`) + pgTAP di `hardening.test.sql` (`admin_grants.test.sql` hanya dijalankan ulang) | Bentuk JSON, kode error (pakai `code_invalid`, `has_members`), arti "satu baris per situs" (`api.md:57`) |
| App | `OnboardingModel`, `OnboardingFlow`, `ConnectModel` (flag batal), `AppSettings` (key lokal baru), `AppEnvironment`, `GuardianHomeModel`, `ActivityModel`, `MainTabView`, `MemberDetailModel`/`View`, `ProfileModel`, `ProfilePages`, `SessionStore`, `MockRepository`, test | `project.yml`, `ShooShared/`, extension, App Group keys kontrak |
| Data cloud | Tidak ada migrasi data | Baris lama tetap |
| Tim lain | Q1–Q5 lewat issue (aturan 7) | Tidak ada perubahan kode Umar/Imelda |

## Keputusan

| # | Keputusan | Alasan |
|---|---|---|
| K1 | **27a: become-protected dalam satu transaksi.** Sebelum transaksi tetap ada pre-check murah `has_members` (409 cepat, tidak menghabiskan percobaan). Di dalam transaksi: (1) `lockAttempts(tx, oldId, ipHash)` (device lalu IP, urutan `joinAttempts.ts`) → (2) `attemptsRetryAfter(oldId, ip)` → (3) `findCode` → tidak ada/kedaluwarsa → catat gagal `device_id = oldId`, commit, lempar → (4) kode milik `oldId` sendiri → catat gagal, `code_invalid` → (5) `lockGuardian` untuk `oldId` dan Guardian tujuan, **urut id** → (6) cek ulang: kode masih milik tujuan, anggota tujuan < 3, anggota `oldId` = 0 (kalau tidak: `has_members`) → (7) sisipkan salinan → (8) `deleteDeviceInTx(oldId)` (link, kode, verdict + hitung ulang antrean, scan, device lama, tombstone storage) → (9) `insertLink(copy, tujuan)` → commit. **Tidak** mencatat attempt sukses (baris sukses tidak dihitung, `joinAttempts.ts:28`, dan id lama sudah dihapus). Error di (7)–(9) membatalkan seluruh transaksi lalu dipetakan: 23505 → `already_connected`, 23503 → `code_invalid`, 23514 `family_full` → `family_full`, **23514 lain** (trigger `family_links_check` `init.sql:150-158`: Guardian tujuan menghapus diri setelah langkah 6) → `code_invalid`. Guardian tujuan sengaja tidak dikunci baris lebih awal (akan membuka lagi siklus domain ↔ device) | Validasi sebelum salinan dibuat, jadi jalur gagal tanpa savepoint. Kunci `oldId` dipegang sampai commit dan device lama terhapus di transaksi yang sama, jadi tidak ada yang bisa bergabung ke `oldId` sesudahnya (F-B2). Tidak ada keadaan "join commit, device lama masih ada" (F-B3). Kode sendiri ditolak (F-B1). Batas percobaan per device + IP bekerja (F-B6). Saat become-protected **sukses**, baris gagal device lama ikut terhapus cascade sehingga hitungan IP turun: diterima (sama dengan `DELETE /devices/me`, K6), yang tersisa batas `createDevice`/`becomeProtected` di `rate_limit_hits` |
| K2 | `services/family.ts`: validasi join dipisah dari penautan: `validateJoinInTx(tx, { attemptDeviceId, ipHash, code, excludeGuardianId?, alsoLockGuardianId?, checkAlreadyConnected? })` → `{ guardianId } \| { fail }` (langkah 1–6 K1, kunci Guardian urut id; `checkAlreadyConnected` = cek `guardianOf` → `already_connected` sebelum `findCode`, tanpa mencatat attempt, hanya untuk `/family/join`, `family.ts:65`, `family.test.ts:257`). `joinFamily` = `sql.begin` → `validateJoinInTx` (`attemptDeviceId = protectedId`) → `insertLink` → catat sukses (perilaku `POST /family/join` tidak berubah, `family.test.ts` tetap). Become-protected memakai validasi yang sama lalu langkah 7–9. `db/repo/devices.ts`: `deleteDeviceInTx(tx, id)` = isi delete sekarang termasuk `addTombstones` (`devices.ts:257`) dan mengembalikan path storage; `deleteDevice(sql, id, opts?)` tetap membungkusnya, cabang retensi `opts` (`lock_timeout`, `for share`, cek ulang, `:226-244`) tetap di pembungkus | Satu sumber validasi; id salinan tidak dibutuhkan sebelum validasi |
| K3 | Urutan kunci (diperiksa reviewer database): advisory attempt kelas 1 (device) → kelas 2 (IP) → kelas 0 Guardian (urut id) → `deleteDeviceInTx(oldId)`: row lock `family_links` → advisory domain verdict (`dropVerdicts`) → `scans … for update` → `devices` lama → terakhir FK share pada device Guardian tujuan (`insertLink`). `DELETE /devices/me` Guardian tujuan mengambil kunci domain dulu lalu row device-nya (`devices.ts:247,254`): urutan "domain sebelum row device tujuan" sama, jadi tidak ada siklus (alasan menaruh `insertLink` setelah delete). `POST /family/join` biasa: attempt → Guardian → link, juga searah. Dua Guardian yang saling memakai kode mengunci Guardian dalam urutan id yang sama. Seluruh transaksi tetap diulang sekali pada 40P01/40001/55P03 (pola `routes/devices.ts:211-224`) sebagai jaring pengaman | Deadlock dicegah urutan; retry hanya cadangan |
| K4 | **27b ditahan sampai Q4.** `contracts/api.md:57` = satu baris per situs (owner + domain), push pertama + eskalasi; app hanya menampilkan satu baris per `owner\|domain` (`ActivityModel.swift:201-205`). Usulan yang menjaga kontrak (opsi A): setelah link baris punya verdict, kunjungan ulang **tidak** menulis ulang `url`/judul/sinyal/status (`scans.ts:39-42`); `detected_at`, `score` maksimum, dan hitungan tetap diperbarui. Konsekuensi: link lain di domain itu tidak bisa diputuskan dari Activity (extension tetap memblokirnya); kalau status ikut dibekukan, push eskalasi waspada → blokir hilang, kalau tidak, skor/status baris tidak cocok dengan link yang tampil (disebut di Q4). Opsi B (baris baru per link yang diputuskan) = perubahan kontrak, hanya kalau Umar memilihnya | Aturan 2/3/7: makna kontrak milik lead |
| K5 | **27c:** migrasi baru `public.queue_blocklist_domain(p_domain text, p_families int) returns void`, `security definer`, `set search_path = pg_catalog, pg_temp` (semua nama diberi skema, seperti fungsi definer lain di repo), `revoke execute … from public, anon, authenticated` (pola `verdicts_per_link.sql:63`), `grant execute … to shoo_api`; validasi `p_families >= 1`. Fungsi melakukan insert/`on conflict … do update set families` seperti sekarang; bila **aksi terakhir** domain itu di `admin.review_decisions` adalah `reject` (`unreject`/`approve`/`add` sesudahnya membatalkannya), baris baru disisipkan dengan `rejected_at = now()` dan `rejected_by` = `actor` aksi itu (memenuhi `blocklist_rejected_needs_by`). `recountFamilies` (`verdicts.ts:105-118`) memanggil fungsi ini sebagai ganti `insert`. Tidak mengambil kunci admin `(7,1)` (urutan kunci admin vs domain verdict tidak diubah). pgTAP baru di `backend/db/supabase/tests/hardening.test.sql` (pola grant fungsi publik seperti `verdicts_per_link.test.sql:12-14`): `execute` hanya `shoo_api` (bukan `public`/`anon`/`authenticated`), `prosecdef`, `proconfig`, `shoo_api` tetap tanpa akses baca `admin.review_decisions`. Batasan dicatat: penolakan lama lewat SQL editor tanpa baris `review_decisions` tidak dikenali | `shoo_api` tidak punya grant baca `admin.review_decisions` dan hanya boleh menulis `domain, families` (`hardening.sql:12-14`). Baris tanpa dukungan tetap dihapus (D-alief-40). Setelah disisipkan ulang sebagai ditolak, reviewer tetap bisa `unreject` |
| K6 | **27d:** (1) **Consent di dalam alur undangan:** kode undangan diambil ke model saat `submitName` (sebelum app bisa ke background dan `RootView.swift:41` membuang `pendingJoinCode`); bila `dataConsent == nil`, langkah `.consent` (pakai `DataConsentView`) tampil **sebelum** Connect, jawaban lewat `env.setDataConsent`. (2) ON-04: checkbox consent hanya tampil bila `dataConsent == nil`; gerbang tombol menjadi `dataConsent != nil || consentChecked` di **tiga** tempat (`activateExtension` `:148`, `refreshExtensionStatus` `:206`, `TurnOnExtensionView.swift:40,90-114`); `activateExtension` menulis `.granted` **hanya** bila `dataConsent == nil` dan checkbox dicentang (sekarang `:149` menimpa `.declined`). (3) `needsDataConsent` hanya untuk device yang sudah `onboardingCompleted` (jalur upgrade); `aRegisteredDeviceWithoutAnAnswerIsAskedOnce` diberi `onboardingCompleted = true`. (4) `OnboardingModel.init`: **hanya Protected** yang `connectPassed` tapi belum `onboardingCompleted` → `.turnOnExtension` (Guardian tetap `.done` sesuai catatan Figma `:72-73`; Protected tidak punya pengingat Home). (5) **Batal setelah join gagal:** flag `settings.inviteRegistrationPending` (UserDefaults app, masuk `AppSettings.Keys.all`) disimpan **sebelum** `ensureRegistered()` di jalur join (dihapus lagi kalau registrasi gagal), dihapus saat join sukses; `OnboardingModel.init` menghapusnya bila `mode == nil` (app mati di tengah `POST /devices`). Selama flag menyala, `already_connected` dari join (respons join sebelumnya hilang setelah server commit, `family.ts:65`) tidak ditampilkan sebagai pesan "Only they can disconnect you" (`ConnectModel.swift:52`), tapi dipetakan di closure join `OnboardingModel.connect()` (tempat flag bisa dibaca): `me()` → `guardian != nil` → joined dengan `GuardianInfo` dari `me()`; `me()` gagal → pesan offline, flag tetap. Back/"Not now" saat flag menyala: `isWorking` bersama menonaktifkan Connect, Back, dan "Not now" selama batal **dan** selama `ConnectModel.state == .joining`; `me()` harus berhasil (galat jaringan → pesan, tidak menghapus; 401 = device sudah dihapus server, mis. retensi device tak terpakai `devices.ts:184-188` → lewat `markSessionExpired` ke layar Session expired, yang "Start again"-nya = hasil yang sama; dicatat, tidak diubah); `guardian != nil` (join sempat commit) → tandai Connect lulus, tampilkan keadaan joined; `guardian == nil` → `repository.deleteMe()`, 404/401 = sukses (seperti `ProfileModel.swift:336-337`); setelah sukses jalankan rutinitas lokal yang sama dengan hapus akun, diekstrak ke `AppEnvironment.forgetDeletedDevice(linked: LinkedAccountSettings)` = **hanya** `linked.clear()` + `CheckStats.clear()` (parameter bisa disuntik seperti `ProfileModel.swift:64,75-78`; session sudah kosong); `ProfileModel.deleteMyData` tetap memanggil `onSessionEnd()` + `settings.reset()` sendiri, lalu metode baru `AppSettings.forgetInviteRegistration()` (mode nil, `onboardingConnectPassed` false, flag false; bahasa dan jawaban consent **tetap**, beda dengan `reset()`; `reset()` juga diberi `inviteRegistrationPending = false` karena `Keys.all` hanya membersihkan UserDefaults, bukan properti di memori; `mode` `private(set)` dan `chooseMode` menolak menimpa, `AppSettings.swift:56,190`), lalu model: `connectModel = nil`, `selectedMode = .guardian`, kode undangan yang diambil di `submitName` dilupakan; Back → Nama (Next berikutnya lanjut sebagai Pribadi karena kode sudah dilupakan), "Not now" → ON-04 sebagai Pribadi (perilaku `skipConnect` sekarang). Back dari langkah `.consent` (belum registrasi) → Nama dengan kode **tetap** disimpan. Galat jaringan saat delete → tetap di Connect, sesi utuh. Setelah relaunch (step `.connect`, flag tetap) aturan sama. Setelah relaunch di ON-04 (Protected yang sudah terhubung), Back ke Connect disembunyikan (model Connect baru akan `already_connected`). (6) Komentar `OnboardingModel.swift:178` diperbaiki | Consent sebelum data apa pun dikirim (extension baru punya token setelah `session.save`, kini setelah consent). Jawaban "tidak" tidak pernah ditimpa. Mode Protected permanen di server (trigger I1), jadi batal yang jujur = hapus device (P13). `DELETE /devices/me` ikut menghapus `join_attempts` device; batas IP tetap lewat `createDevice` 30/jam per IP — diterima dan dicatat |
| K7 | **27e:** `decide` memasang verdict **hanya ke scan yang diputuskan** (per id); baris lain menunggu refresh (server tahu `verdict_link`/`verdict_shared`). `verdictEpoch` seperti Detail: refresh yang dimulai sebelum verdict menggabungkan verdict lokal yang lebih baru per id. `MockRepository.setVerdict` diselaraskan (per link sederhana: origin + path) | Tidak menyalin regex SQL ke Swift |
| K8 | **27f:** `isLoadingMore = false` di setiap jalan keluar `loadMore` dan saat refresh gagal; `screenIdentity` ditambah `env.session?.deviceId` (komentar: `session` `@ObservationIgnored`, refresh terjadi karena `settings.mode` ikut berubah); penghitung baru `AppEnvironment.verdictSaves` (Int, `@Observable`) dinaikkan oleh `DetailModel` dan `GuardianHomeModel` setelah verdict sukses (lewat closure yang disuntik); `ActivityView` memuat ulang (`refresh`) saat tampil lagi bila nilainya berubah sejak muatan terakhir | – |
| K9 | **27g:** push dengan `scanId` membuka Detail di mode apa pun (`GET /scans/{id}` mengizinkan pemilik, `db/repo/scans.ts:518`; Detail Protected ada). `MemberDetailModel.disconnect()` sukses → `onDisconnected` (disuntik, default `DeliveredPushes.clear`) | P13 |
| K10 | **27h:** `becomeProtected` menandai `isSwitchingSession` (direset di `defer`, sukses maupun gagal); `handleUnauthorized` mengabaikan 401 untuk token lama **hanya selama request berjalan**. Setelah sukses token sekarang sudah baru, jadi 401 token lama otomatis diabaikan; setelah gagal (mis. respons hilang setelah server commit) 401 berikutnya memunculkan Session expired seperti biasa. `register()` mereset `sentDeviceInfo`. Jalur hapus akun mereset `sessionExpired`. `ApiRepository.me()` hanya menulis App Group bila token yang dipakai masih token sekarang. `SessionStore.appKeys` + 3 key | "Respons untuk sesi lama tidak mengubah sesi baru" |
| K11 | **27i:** rollback hanya membalik key milik update yang gagal di atas state sekarang; Save quiet hours nonaktif bila mulai = selesai, teks EN/ID | – |
| K12 | **27j:** `insertProtectedCopy` mengisi `weekly_summary = false` (halaman Protected tidak punya ringkasan). Quiet hours **menunggu Q2**: bila "ya", `ownPush` mengabaikan quiet hours untuk Protected (salinan dan device Protected baru sekaligus, tanpa menyentuh kolom); bila "tidak", salinan diberi `quiet_hours = false` supaya pengaturan tersembunyi tidak menyala | Pengaturan yang tidak terlihat tidak boleh aktif diam-diam; quiet hours = keputusan produk |
| K13 | **F-B5:** tidak diubah sebelum Q1. Bila Umar memilih filter: `GET /scans` keluarga hanya baris `s.created_at >= l.created_at` **dan** `recordScan` hanya menggabungkan ke baris yang dibuat setelah link (kalau tidak, kunjungan baru ke domain lama masuk baris tersembunyi tanpa push, `scans.ts:33-44`, `routes/scans.ts:173`) | Keputusan produk |

### Test repro → test permanen

| Test repro | Pindah ke | Harapan setelah perbaikan |
|---|---|---|
| `F-B1` | `test/settings.test.ts` | `404 code_invalid`, device lama tetap Guardian, tidak ada device baru |
| `F-B2 replay` | `test/settings.test.ts` | Diganti test fungsi: dua koneksi `postgres()`; koneksi A menjalankan `becomeProtectedTx` dengan hook jeda setelah langkah (6), koneksi B `joinFamily(Mom, kodeG)`. B menunggu kunci Guardian `oldId`; setelah A commit, kode G sudah terhapus bersama device lama → B `code_invalid`. Atau B menang lebih dulu → A `has_members`. Mom tidak pernah tanpa Guardian tanpa salah satu error itu. `set local lock_timeout = '2s'` di test |
| `F-B3 state-only` | `test/settings.test.ts` | Hook gagal yang disuntik di langkah (9) → transaksi batal: 0 salinan, device lama utuh; retry → tepat 1 link |
| baru (F-B6) | `test/settings.test.ts` | 5 kode salah lewat become-protected → percobaan ke-6 `too_many_attempts`; 20 dari satu IP lintas device → kena batas IP |
| baru (K3) | `test/settings.test.ts` | Dua Guardian saling memakai kode bersamaan (level fungsi) → selesai < 10 s, satu 200, satu `has_members`/`code_invalid`; Mom satu IP dengan Guardian yang sedang switch → tidak 500 |
| `F-B4` | `test/verdicts.test.ts` | Opsi A: baris tetap `/a` + `safe`; `again === id` tetap benar. Opsi B: harapan ditulis ulang setelah Q4 |
| `F-B7` | `test/verdicts.test.ts` | Tolak lewat `admin.vote(domain,'reject',…)` (bukan UPDATE langsung) → dukungan 0 (baris terhapus) → `not_safe` → baris ada dengan `rejected_at` + `rejected_by` terisi; lalu `unreject` → antrean → dukungan 0 → terhapus → `not_safe` → antrean normal (`rejected_at` null) |
| `F-B5` probe | – | Tidak dipindah sebelum Q1; tidak masuk DoD |
| `inviteJoin…` + `protectedAfterInvite…` | `Tests/OnboardingTests.swift` | Langkah `.consent` muncul sebelum registrasi; kode tetap ada setelah consent (app sempat ke background); setelah join `needsDataConsent == false`; relaunch Protected → `.turnOnExtension`; consent diberi di langkah `.consent` → ON-04 tanpa checkbox → tombol aktif → sampai `.safariDefault`; tolak consent → join → ON-04 tanpa checkbox → sampai `.safariDefault` dan `dataConsent` tetap `.declined`; tolak → join gagal → "Not now" → ON-04 Pribadi → tombol aktif |
| `failedInviteJoinSavesNoMode` | `Tests/OnboardingTests.swift` | Ditulis ulang: setelah join gagal mode **masih** `.protected` (registrasi dijaga untuk coba lagi); Back → `deleteMe` sekali → `mode == nil`, step Nama; "Not now" → ON-04 Pribadi; `deleteMe` 404 → dianggap sukses; `me()` gagal → tidak menghapus; `me().guardian != nil` → joined; join kedua `already_connected` saat flag menyala → joined (bukan pesan "Only they can disconnect you"); Connect tidak bisa ditekan selama batal; `AppSettingsTests.forgetInviteRegistration` menjaga bahasa + consent; flag dibersihkan di `init` bila `mode == nil` |
| `homeVerdictIsNotUndone…` | `Tests/GuardianHomeModelTests.swift` | Sama; jeda diganti gerbang `CheckedContinuation` (bukan `Task.sleep`) |
| `loadingMoreSpinnerClears…` | `Tests/ActivityModelTests.swift` | Sama; jeda diganti gerbang |

## Langkah kerja

Aturan setiap sub-fase: branch dari `main` terbaru; `superpowers:systematic-debugging` + `superpowers:test-driven-development`; test dari tabel di atas dulu (merah karena alasan yang benar), lalu kode (hijau). Backend test **selalu** dengan DB terpisah selama ada sesi e2e lain (`lsof -iTCP:8787`). xcodebuild **selalu** dengan batas waktu dan simulator milik sesi sendiri. PR UI → screenshot sebelum/sesudah EN + ID.

### 27-0 Plan + bukti (`docs/alief-fase-27-state-machines`)

1. File ini, `log/fase-27.md`, `log/fase-27-repro/*.txt`, baris PROGRESS 27, ronde `fixbug.md` "Fase 27". Test repro disimpan sebagai `.txt` (folder `plan/` = dokumen saja; bukan kode yang dijalankan). **Jangan** commit salinan test ke `backend/api/test/` atau `ios/ShooApp/Tests/` (CI merah); salinan lokal di worktree (`backend/api/test/fase27-repro.test.ts`, `ios/ShooApp/Tests/Fase27ReproTests.swift`) dihapus sebelum commit; `git status` harus hanya menampilkan `plan/alief/`.
2. Draf Q1–Q5 di LANGKAH MANUAL; dibuka setelah Alief setuju.

### 27a Backend — become-protected atomik (`fix/PF-01-become-protected-atomic`)

1. **Merah:** test baris F-B1, F-B2, F-B3, F-B6, K3 di tabel. Hook disuntik lewat parameter opsional `becomeProtectedTx(tx, input, hooks?)` yang hanya dipakai test.
2. **Hijau:** K1–K3. `services/family.ts` (`validateJoinInTx`), `db/repo/devices.ts` (`deleteDeviceInTx`), `routes/devices.ts:171-199` (satu `sql.begin`, retry sekali, `waitUntil(deleteScreenshots)` setelah commit), `services/` baru `becomeProtected.ts` kalau route jadi panjang.
3. Tetap hijau: `test/family.test.ts`, `test/settings.test.ts`, `test/devices*.test.ts`, `test/retention.test.ts`, `test/delete-notifies-family.test.ts`.
4. Reviewer: typescript → database (urutan kunci K3, lama transaksi, retry) → security (batas percobaan, tidak ada enumerasi kode lewat pesan error berbeda).
5. Setelah merge: CI `backend.yml` deploy; uji asap cloud (LANGKAH MANUAL).

### 27b Backend — baris yang sudah diputuskan dibekukan (`fix/DT-06-verdict-row-frozen`, setelah Q4)

1. Opsi A: **Merah** `F-B4` (tabel) + kunjungan ulang tanpa verdict tetap menimpa + eskalasi (`scans.test.ts:176` tetap). **Hijau:** `recordScan` CTE (`db/repo/scans.ts:31-53`): `url/page_title/signals` hanya berubah bila `not exists (verdict untuk owner di verdict_link(url lama))`; `status` (+ push eskalasi) dibekukan atau tetap naik sesuai jawaban Q4 butir 2.
2. Opsi B: rencana ulang setelah kontrak diubah Umar.
3. Reviewer: typescript → database.

### 27c Backend — penolakan reviewer bertahan (`fix/GD-07-rejected-stays-rejected`)

1. **Merah:** `F-B7` (tabel) + pgTAP di `hardening.test.sql`: `shoo_api` boleh `execute` fungsi baru, tetap tidak bisa `select admin.review_decisions` / `update rejected_at`.
2. **Hijau:** K5 (migrasi baru + `recountFamilies`).
3. Reviewer: database → security (fungsi `security definer`: `search_path` tetap, input divalidasi `p_families >= 1`, tidak membocorkan `actor`).

### 27d App — onboarding undangan (`fix/ON-04-invite-onboarding-states`)

1. **Merah:** baris app di tabel + `OnboardingTests`: urutan undangan = splash → Nama → **Consent** → Connect; hitung `registerDevice` (sekali, termasuk setelah kode salah lalu benar); batal saat `ConnectModel.state == .joining` diabaikan.
2. **Merah** `UITests/PairingUITests` (dengan `-debug.askDataConsent YES`, karena mode mock memberi consent otomatis, `AppEnvironment.swift:108-110`): instal baru + link → Nama → Consent → Connect → join → **ON-04** → tap Turn on → layar berikut (lewat ON-04, bukan berhenti di situ); kode `999999` → error, Back → Nama.
3. **Hijau:** K6 (`OnboardingModel`, `OnboardingFlow`, `TurnOnExtensionView` (checkbox bersyarat), `ConnectModel` (gate `isWorking` bersama), `AppSettings.inviteRegistrationPending` + `Keys.all` + `forgetInviteRegistration()`, `AppEnvironment.forgetDeletedDevice(linked:)`, `AppEnvironment.needsDataConsent`, `ProfileModel.deleteMyData` memakai rutinitas bersama, `MockRepository.deleteMe` mengosongkan mode mock bila belum).
4. Screenshot sebelum/sesudah EN + ID: Consent di alur undangan, Connect error + Back, ON-04 setelah join.
5. Reviewer: swift → security (hapus device = data server hilang; Keychain + App Group bersih; tidak ada scan terkirim sebelum consent: extension hanya punya token setelah `session.save`, yang kini setelah consent).

### 27e App — verdict Home (`fix/GD-01-home-verdict-state`)

1. **Merah:** tabel + `decide` hanya mengubah scan dengan id itu (scan lain di list tidak tersentuh); `MockRepositoryTests.setVerdict` per link. (Tidak ada test dua link satu domain: server tidak menghasilkannya.)
2. **Hijau:** K7. Reviewer: swift.

### 27f App — state list Activity (`fix/PR-05-activity-list-states`)

1. **Merah:** tabel + `loadMore` yang dibuang lalu refresh sukses/gagal → `isLoadingMore == false`; `MainTabView.identity(repository:familyMode:deviceId:)` statis dites.
2. **Merah (wajib):** `ActivityModelTests`: `verdictSaves` naik → `refreshIfVerdictsChanged()` memanggil `scans` sekali; tidak naik → tidak memanggil.
3. **Hijau:** K8. UITest opsional: Detail → Mark safe → kembali → badge di list. Reviewer: swift.

### 27g App — push tap + hapus push saat putus (`fix/GD-06-push-tap-and-clear`)

1. **Merah:** `PushRoutingTests.protectedPushWithScanIdOpensDetail` (di `Tests/PushTests.swift`) menggantikan `protectedPushTapOpensShield`; `MemberDetailModelTests.disconnectClearsDeliveredPushes`.
2. **Hijau:** K9, komentar `openPush`. Uji simulator `xcrun simctl push` payload `scanId` milik Protected → Detail. Reviewer: swift → security.

### 27h App — siklus sesi (`fix/PF-01-session-lifecycle`)

1. **Merah** `AppEnvironmentSessionTests`: (a) 401 token lama selama `becomeProtected` → `sessionExpired == false`, sesi baru tersimpan; (b) register → hapus akun → register → `sceneBecameActive` mengirim `deviceModel` (repository perekam); (c) 401 saat hapus akun → onboarding, bukan Session expired; (d) `me()` token lama setelah switch tidak menghapus `guardian.name`; (e) `becomeProtected` gagal → flag switch direset, 401 berikutnya memunculkan Session expired; `SessionStoreTests`: 3 key terhapus.
2. **Hijau:** K10. Reviewer: swift → security.

### 27i App — rollback pengaturan (`fix/PF-01-settings-rollback`)

1. **Merah** `ProfileModelTests`: toggle A gagal lambat + B sukses → A kembali, B tetap; `canSave` quiet hours.
2. **Hijau:** K11 + string EN/ID. Screenshot sheet. Reviewer: swift.

### 27j Backend — pengaturan salinan Protected (`fix/PF-01-protected-copy-settings`)

1. **Merah:** `settings.test.ts:296-312` → `weeklySummary: false` setelah switch. Asersi quiet hours ditambah sesuai jawaban Q2: "ya" → `ownPush` Protected tidak ditahan quiet hours; "tidak" → salinan `quietHours: false`.
2. **Hijau:** K12. Reviewer: typescript.

### 27k Rendah

Setiap butir yang diperbaiki tetap TDD (test merah dulu).

| Butir | Keputusan | Test merah | Branch |
|---|---|---|---|
| F-B12 kelas kunci | Perbaiki: konstanta kelas di `db/locks.ts`, kelas unik per tujuan, komentar `scans.ts:269` | `test/locks.test.ts`: semua konstanta unik (tidak ada dua tujuan dengan kelas sama) | `fix/PR-05-advisory-lock-classes` |
| F-N10 cron limit | Perbaiki: filter quiet hours di SQL sebelum `limit`, memakai jam yang disuntik (`opts.now`, `notifications.ts:38`; test `settings.test.ts:223-225` bergantung padanya): `${now}::timestamptz at time zone coalesce((select name from pg_timezone_names where name = g.time_zone), 'Asia/Jakarta')`, menit = `extract(hour)*60 + extract(minute)`, dibandingkan `quiet_start`/`quiet_end`, termasuk rentang lewat tengah malam dan mulai = selesai = sepanjang hari, sama dengan `quiet.ts` (zona tak dikenal → WIB seperti `quiet.ts:29`, bukan error yang menggagalkan seluruh query) | `test/settings.test.ts`: 201 Guardian dalam quiet hours + 1 di luar → yang di luar tetap dapat push; tabel kasus SQL vs `isQuiet` untuk zona `Asia/Jakarta`/`Asia/Makassar`/`UTC`/zona tak dikenal | `fix/GD-03-protection-off-cron` |
| F-B8 favicon | Perbaiki bila sempat: `favicon_ready_at` seperti `replica_ready_at` (migrasi `20261108110000`) | `test/favicons.test.ts`: list tidak menampilkan `faviconUrl` sebelum upload selesai | `fix/PR-05-favicon-ready` |
| F-B9 replica macet | Ukur dulu (LANGKAH MANUAL); > 0 → sweep di retensi + test | – | – |
| F-A10 kode keluarga | Token request di `FamilyCodeModel.refreshCode` | `PairingTests`: dua refresh bersamaan, jawaban lama datang terakhir → kode baru tetap tampil | `fix/GD-04-code-refresh-token` |
| F-B10, F-B11, F-B13, F-N8, F-N9 | Terima; dicatat di 27z (F-N9 juga di `backend/API.md`) | – | – |

### 27z Docs (`docs/alief-R4-state-machine`)

Tulis ulang `ref/R4-state-machine.md` dari peta state audit (device, link keluarga, kode, scan, verdict, blocklist, replica, favicon, live activity, push token, ops_jobs, onboarding, sesi, pairing, push) dengan `file:baris` transisi + guard, setelah 27a + 27d merge; hapus isi usang (60 s, 4 digit, verdict per domain, verdict bertahan setelah putus). `log/fase-27-repro/` **tidak** dihapus di 27z: PR kecil terpisah setelah Q1 dan Q4 ditutup (probe F-B5 dan F-B4 opsi B masih di sana; probe F-B5 juga ditempel di issue Q1 sebagai bukti). Perbarui nomor baris di file ini kalau berubah.

## LANGKAH MANUAL

- [ ] Alief menyetujui isi Q1–Q5, lalu issue dibuka dengan template **Question / proposal** (`.github/ISSUE_TEMPLATE/question.yml`: PRD ID, Context, Proposal, Questions bernomor, Until answered), label `question`, assign `umarmuhdhor`, satu topik per issue, nomor ditautkan di `TODO.md` + `fixbug.md`. Draf:
  - **Q1** — judul `GD-05: should a guardian see a member's scans from before they connected?` · PRD `GD-05` · Context: Guardian melihat semua scan anggota 14 hari terakhir, termasuk sebelum terhubung (`routes/scans.ts:250`); dengan kode kedaluwarsa yang dipakai ulang (`codes.ts:34-36`), Guardian asing bisa melihatnya (peluang kecil). Baris yang terus dikunjungi hilang di hari ke-14 sejak kunjungan pertama (janji retensi, tidak diubah). · Proposal: filter "sejak terhubung"; kunjungan baru ke situs yang pertama terlihat sebelum terhubung jadi baris baru supaya Guardian tetap dapat push. · Questions: 1) Filter "sejak terhubung" boleh? 2) Kalau ya, baris baru untuk situs lama seperti di Proposal boleh? · Until answered: tidak diubah.
  - **Q2** — `PF-01: quiet hours for Protected devices` · PRD `PF-01` · Context: halaman Protected tidak menampilkan quiet hours, tapi server menahan push **waspada** Protected tentang scan miliknya pada default 22:00–06:00 (push blokir tetap terkirim, `notify.ts:35`); salinan Guardian → Protected membawa pengaturan Guardian. · Proposal: quiet hours tidak berlaku untuk Protected. · Questions: 1) Quiet hours diabaikan untuk Protected? 2) Kalau tidak, salinan Guardian → Protected diset quiet hours mati? · Until answered: hanya `weeklySummary = false` di salinan.
  - **Q3** — `GD-03: should "extension switched off" reach the guardian sooner?` · PRD `GD-03` · Context: kontrak hanya punya `extensionLastSeenAt` (`api.md:29`); Guardian melihat Active sampai jendela habis walau HP Protected menampilkan Off. · Proposal: field tambahan opsional di `PATCH /devices/me` (aditif). · Questions: 1) Perlu? 2) Kalau ya, nama + nilai field-nya? · Until answered: tidak diubah.
  - **Q5** — `ON-04: consent before registering on the invite path` · PRD `ON-04` · Context: Figma "Flow" tidak punya layar consent terpisah; consent ada di checkbox ON-04 (`OnboardingModel.swift:36`, `OnboardingTests.swift:111`). Jalur undangan mendaftar di Connect, **sebelum** ON-04, jadi extension sudah bisa mengirim scan sebelum consent (F-A1). · Proposal: di jalur undangan saja, tampilkan `DataConsentView` yang sudah ada (layar upgrade) sebelum Connect bila consent belum dijawab; ON-04 menyembunyikan checkbox kalau sudah dijawab. · Questions: 1) Boleh layar consent terpisah di jalur undangan, atau ada desain lain (mis. checkbox di Connect)? · Until answered: 27d memakai Proposal, screenshot sebelum/sesudah di PR untuk review.
  - **Q4** — `DT-06: a decided site whose newer visit is on another link` · PRD `DT-06` · Context: `api.md:57` = satu baris per situs; kunjungan ulang dengan skor lebih tinggi menulis ulang link baris, jadi keputusan "safe" pada link lama hilang dari Activity dan tidak bisa direvisi (test repro di `plan/alief/log/fase-27.md`). · Proposal: opsi A (tanpa ubah kontrak) baris yang sudah diputuskan tidak ditulis ulang; link baru tetap diblokir extension tapi tidak bisa diputuskan dari Activity, dan push eskalasi waspada → blokir hilang atau skor/status tidak cocok dengan link. Opsi B (ubah kontrak) baris baru per link bila link lama sudah diputuskan, dengan push. · Questions: 1) A atau B? 2) Untuk A: status ikut dibekukan atau tetap naik? · Until answered: 27b tidak dikerjakan.
- [ ] 27a/27c/27j setelah merge: run CI `backend.yml` hijau; uji asap cloud 27a dengan dua device uji (Guardian A tanpa anggota memakai kode Guardian B → 200; memakai kodenya sendiri → 404); device uji dihapus.
- [ ] 27k F-B9: `supabase db query --linked` (baca saja): `select count(*) from scans where replica_path is not null and replica_ready_at is null and created_at < now() - interval '1 hour'`; catat di `log/fase-27.md`.

## Verifikasi

```bash
# dari root repo; DB terpisah (log/fase-27.md §DB). audit-env berhenti kalau URL tidak menunjuk shoo_audit
cp plan/alief/log/fase-27-repro/audit-env.sh.txt "$TMPDIR/audit-env.sh" && . "$TMPDIR/audit-env.sh"
(cd backend/api && npx vitest run test/settings.test.ts test/family.test.ts test/verdicts.test.ts test/scans.test.ts \
  test/retention.test.ts test/devices.test.ts test/devices-me.test.ts test/delete-notifies-family.test.ts && npx tsc --noEmit)
(cd backend/db && supabase test db)   # pgTAP (27c), seperti CI backend.yml:40 — DB lokal penuh, jalankan saat tidak ada e2e

# catatan: di shoo_audit verdicts.test.ts punya 1 gagal yang diketahui (trigger arsip admin, log §DB); gerbangnya CI backend.yml

# app; SIM_ID = simulator milik sesi ini
(cd ios && xcodegen)
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "id=$SIM_ID" \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 60 \
  -only-testing:ShooAppTests/OnboardingModelTests -only-testing:ShooAppTests/GuardianHomeModelTests \
  -only-testing:ShooAppTests/ActivityModelTests -only-testing:ShooAppTests/PushRoutingTests \
  -only-testing:ShooAppTests/NotificationRouterTests -only-testing:ShooAppTests/MemberDetailModelTests \
  -only-testing:ShooAppTests/AppEnvironmentSessionTests -only-testing:ShooAppTests/SessionStoreTests \
  -only-testing:ShooAppTests/ProfileModelTests -only-testing:ShooAppTests/MockRepositoryTests \
  -only-testing:ShooAppTests/AppSettingsTests -only-testing:ShooAppTests/ConnectModelTests \
  -only-testing:ShooAppUITests/PairingUITests

# 27k per butir: npx vitest run test/locks.test.ts | test/favicons.test.ts (backend/api); -only-testing:ShooAppTests/ConnectModelTests -only-testing:ShooAppTests/FamilyCodeModelTests (app; keduanya ada di Tests/PairingTests.swift:61,142)

# tidak ada verdict per domain tersisa di app setelah 27e (harus kosong)
grep -rn "domain == scan.domain" ios/ShooApp --include='*.swift'
```

## Kriteria selesai (DoD)

- [ ] Setiap baris tabel "Test repro → test permanen" (kecuali F-B5 dan F-B4 opsi B) ada di suite dan hijau.
- [ ] 27a: reviewer database menulis "urutan kunci aman" atau temuannya diperbaiki; test K3 selesai tanpa deadlock.
- [ ] 27d: UITest instal-baru-dengan-undangan sampai ON-04 hijau di CI `ios-app.yml`; screenshot EN + ID di PR.
- [ ] Tidak ada perubahan di `contracts/`, `ios/project.yml`, `ios/ShooShared/`, `ios/ShooExtension/`, `detector/`, `ai/` (`git diff --stat main...` per PR).
- [ ] Q1–Q5 terbuka dan ditautkan di `TODO.md`; pekerjaan yang menunggu jawaban tidak dikerjakan.
- [ ] `fixbug.md` ronde "Fase 27" dicentang per butir dengan nomor PR; baris PROGRESS 27 diperbarui.
- [ ] 27z merge: `ref/R4-state-machine.md` cocok dengan kode. `log/fase-27-repro/` dihapus di PR kecil terpisah setelah Q1 + Q4 ditutup (tidak memblokir 27z).

## Risiko & rollback

| Risiko | Mitigasi | Rollback |
|---|---|---|
| 27a: transaksi memegang kunci attempt + Guardian + scan lebih lama | Validasi sebelum salinan dibuat; retry sekali; `lock_timeout` 5 s role; test K3; reviewer database | Revert PR 27a (tanpa migrasi) |
| 27a: Mom satu IP dengan Guardian yang switch | Keduanya mengambil kunci IP setelah kunci device masing-masing, lalu Guardian; tidak ada siklus (K3); test | Revert |
| 27c: fungsi `security definer` | `search_path` tetap, `revoke … from public`, `execute` hanya `shoo_api`, pgTAP grant | Revert kode Worker dulu (kembali ke `insert`), deploy; `drop function` di migrasi berikutnya setelah deploy itu live |
| 27d: menghapus device saat batal membuang Guardian yang baru terhubung (join sukses + tap Back) | Batal nonaktif selama `.joining`; hapus hanya bila `me()` sukses dan `guardian == nil` | Revert PR 27d |
| 27d: langkah Consent baru di alur undangan | Pakai `DataConsentView` yang sudah ada; screenshot; UITest | Revert |
| 27g: Protected membuka Detail scan miliknya | Detail Protected sudah ada (`labelSimple`, tanpa tombol validasi) | Revert |
| Uji lokal mengganggu sesi lain | DB `shoo_audit` + simulator sendiri | – |

## Catatan handoff

- Race lewat `call()` macet di pool workerd (dicoba 11 Nov). Uji race di level fungsi dengan dua koneksi `postgres()` dan hook yang disuntik.
- `MockRepository` memakai aturan verdict per domain sampai 27e merge; test berbasis Mock tidak membuktikan perilaku per link sebelum itu.
- F-A7 tertutup oleh #402. F-B6 **belum**: batas per device #402 (30/jam) tidak menggantikan batas percobaan join.
- Simulator "Shoo Fase27" dan DB `shoo_audit` dihapus setelah 27z (`xcrun simctl delete 008727CA-5EB3-4FD4-9817-3DAFEDB0338F`; `drop database shoo_audit`).

## Riwayat verifikasi

- Verifikasi temuan (11 Nov 2026): backend 6 test repro gagal sesuai prediksi (F-B1, F-B2, F-B3, F-B4, F-B7, probe F-B5); app 5 test / 7 asersi gagal (F-A1 ×2, F-A2 ×3 kode, F-A4, F-A5). Keluaran di `log/fase-27.md`.
- Review plan ronde 1 (11 Nov 2026, reviewer independen): **BELUM SIAP**, 21 temuan (1 kritis, 2 tinggi, 10 sedang, 8 rendah). Diperbaiki di versi ini: K4 mengubah makna kontrak `api.md:57` → 27b ditahan, Q4; K1/K3 urutan kunci bertentangan + deadlock attempt(IP)↔Guardian → urutan baru, validasi sebelum salinan; K5 (a) mustahil (tanpa grant, kolom `rejected_*` tidak bisa ditulis `shoo_api`) → fungsi `security definer` yang menyisipkan; aturan "aksi terakhir = reject"; test F-B7 lewat `admin.vote`; K12 `quiet_hours = false`; F-B6 dibuka lagi; jalur gagal tanpa savepoint; test race di level fungsi; harapan test repro per K (tabel baru); K6(4) spesifikasi batal lengkap; K6(1) consent sebelum registrasi (celah scan extension); K13 catatan merge; K7 per id; nomor baris disesuaikan ke `02d590e4`; `join_attempts.device_id`; branch 27k ber-PRD ID; F-A2 jadi S; jeda test diganti gerbang; komentar `session` di K8.
- Review plan ronde 2 (11 Nov 2026, reviewer independen baru): **BELUM SIAP**, 24 temuan (2 tinggi, 9 sedang, 13 rendah). Diperbaiki: consent "tidak" ditimpa ON-04 → checkbox bersyarat + `activateExtension` tidak menimpa; batal saat `deleteMe` 404/401 meninggalkan setengah sesi → 404/401 = sukses + rutinitas hapus lokal bersama; Connect ditekan selama batal → `isWorking` bersama; kode undangan hilang saat background → diambil di `submitName`; siklus FK target ↔ kunci domain → `insertLink` setelah `deleteDeviceInTx`, tanpa attempt sukses; K2 bertentangan dengan K1 → `validateJoinInTx`; nama suite test salah (`PushRoutingTests`, `NotificationRouterTests`) + suite yang hilang + `supabase test db`; F-N1 turun ke R (server satu baris per situs); flag switch K10 direset di `defer`; test F-B7 memakai `unreject` (bukan `add`/`approve`); batasan K5 + `revoke from public`; path `backend/db/supabase/tests/`; `selectedMode = .guardian`, "Not now" → ON-04, key masuk `Keys.all`; kasus `guardian != nil`; K6(4) hanya Protected; F-N4/Q2 "push waspada"; quiet hours salinan dipindah ke Q2; pre-check `has_members` tetap; Q4 menyebut push eskalasi; rollback 27c urutan aman; UITest `-debug.askDataConsent YES`; test repro sebagai `.txt`; alasan F-A13; draf Q1–Q4 mengikuti template.
- Review plan ronde 3 (11 Nov 2026, reviewer independen baru): **BELUM SIAP**, 15 temuan (1 tinggi, 1 sedang, 13 rendah). Urutan kunci K1–K3 dinyatakan tanpa siklus (POST /family/code, DELETE /family/members, DELETE /family/guardian, POST /verdicts, recordScan, retensi, DELETE /devices/me Guardian tujuan); K5 "aksi terakhir = reject" cocok dengan semua aksi admin. Diperbaiki: tombol ON-04 macet bila consent dijawab di luar checkbox → gerbang `dataConsent != nil \|\| consentChecked` di tiga tempat + test/UITest melewati ON-04; test 27j quiet hours mengikuti Q2; pemetaan 23514 non-`family_full` → `code_invalid`; cek `already_connected` di `validateJoinInTx`; `deleteDeviceInTx` menyebut tombstone + cabang retensi; flag disimpan sebelum registrasi; hasil 401 di `me()` saat batal dicatat; Back setelah relaunch disembunyikan; `p_families >= 1`; pgTAP di `hardening.test.sql`; `search_path = pg_catalog, pg_temp`; layar consent terpisah = penyimpangan Figma → Q5; catatan gagal lokal `verdicts.test.ts`; konsistensi fixbug/log.
- Review plan ronde 4 (11 Nov 2026, reviewer independen baru): **SIAP DENGAN CATATAN**, 13 temuan (0 kritis, 0 tinggi, 2 sedang, 11 rendah). K1–K3 (urutan kunci, tanpa siklus), K5, K9, K12, nomor baris, dan hitungan lintas dokumen dinyatakan benar. Diperbaiki: `already_connected` setelah respons join hilang → diperlakukan sebagai joined; `settings.mode = nil` tidak bisa dikompilasi → `AppSettings.forgetInviteRegistration()` (bahasa + consent tetap); rutinitas hapus lokal dengan `linked` yang bisa disuntik; aturan kode undangan setelah Back; flag dibersihkan di `init` bila `mode == nil`; peta dampak pgTAP; `revoke … from public, anon, authenticated`; status 27b mengikuti Q4; `AppEnvironment.verdictSaves` + test wajib; 27z menunggu Q1 + Q4; langkah merah + pendekatan SQL per butir 27k; reset hitungan IP setelah sukses dicatat di K1; daftar salinan lokal yang dihapus sebelum commit.
- Review plan ronde 5 (11 Nov 2026, konfirmasi): **SIAP DENGAN CATATAN**, 13 perbaikan ronde 4 terverifikasi ada dan cocok dengan kode; 8 temuan (1 sedang, 7 rendah), 0 kritis/tinggi untuk ronde kedua berturut-turut. Diperbaiki: SQL F-N10 memakai jam yang disuntik + zona tak dikenal → WIB; `forgetDeletedDevice` hanya `linked` + `CheckStats`; pemetaan `already_connected` di closure join + kasus `me()` gagal; `reset()` mereset flag di memori; migrasi F-B8 di peta dampak; suite test yang hilang di Verifikasi; penghapusan repro tidak memblokir 27z; `fixbug.md` menyebut sub-fase per butir rendah + F-A9 → Q3. Plan dinyatakan aman dieksekusi.
