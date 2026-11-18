# Fixbug — tracker perbaikan dari QA (Alief)

Dipakai setelah setiap ronde QA (06Q dan 16). Satu bug = satu test yang gagal dulu = satu commit = satu branch `fix/QA-<ronde>-<ID>-<slug>` (atau beberapa bug kecil yang berkaitan dalam satu PR). Centang kotak saat commit-nya sudah ada di branch fix dan PR dibuka.

## Aturan

- Urutan: semua P0, lalu P1, lalu P2. P3 hanya kalau sempat.
- Setiap perbaikan dimulai dari test yang mereproduksi bug (Swift Testing / XCUITest / vitest / pgTAP) — `superpowers:systematic-debugging` sebelum mengubah kode.
- Setelah merge, jalankan **retest** sesuai langkah di laporan QA dan tulis blok "Retest" di laporan (R7 §4).
- Bug di luar folder kita (extension, detector, kontrak) → jangan diperbaiki. Tulis di bagian "Diteruskan" dengan isi pesan untuk Umar/Imelda (TODO §C).

## Ronde QA-A (fase 06Q)

Laporan: [`qa/QA-A-2026-10-22.md`](qa/QA-A-2026-10-22.md). P0 = 0, P1 = 0; P2 kecil yang berkaitan (tata letak XL / layar kecil) digabung dalam satu PR, satu commit per bug.

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| P2-1 | P2 | ON-01 | Titik halaman menimpa teks splash di XL | `QALayoutUITests.testSplashDotsDoNotCoverText` | `fix/QA-A-P2-layout` | [x] `8da5da0` |
| P2-2 | P2 | ON-03 | Kata terpotong di kartu mode (XL) | screenshot retest (kartu satu elemen VoiceOver) | `fix/QA-A-P2-layout` | [x] `17b442e` |
| P2-3 | P2 | DT-01 | Cincin skor Detail memenuhi layar di XL | `ComponentLogicTests.scoreRingGrowsUpToItsCap` | `fix/QA-A-P2-layout` | [x] `8acfe63` |
| P2-4 | P2 | GD-03 | Tombol Invite tertutup tab bar | `QALayoutUITests.testInviteButtonIsAboveTabBar` | `fix/QA-A-P2-layout` | [x] `1e1f719` |
| P2-5 | P2 | PR-05 / komponen | Judul empty state terpotong, deskripsi `.secondary` | screenshot retest (judul terpotong tidak terlihat di pohon aksesibilitas) | `fix/QA-A-P2-layout` | [x] `01cb7fd` |
| P2-7 | P2 | GD-01/03 | Banner notifikasi menempel memakan layar (SE + XL) | `QALayoutUITests.testInviteButtonIsReachableAtAccessibilitySizes` | `fix/QA-A-P2-layout` | [x] `509366a` |
| P2-6 | P2 | A11y | Suara VoiceOver tidak ikut bahasa app | butuh iPhone + VoiceOver | ditunda ke QA-E2E #14 | [ ] |

## Ronde QA-E2E (fase 16)

Laporan: [`qa/QA-E2E-2026-11-09.md`](qa/QA-E2E-2026-11-09.md) (simulator + stack lokal). P0 = 0, P1 = 0. Ronde iPhone fisik (TestFlight) belum.

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| P2-1 | P2 | GD-02 / PF-01 | Guardian dengan anggota tetap "Personal" + kartu "Become a Guardian" sampai Family mode dinyalakan | – | – | [ ] menunggu keputusan desain |

## Ronde Fase 27 (audit state machine tersirat)

Plan + bukti: [`fase-27-state-machines.md`](fase-27-state-machines.md), [`log/fase-27.md`](log/fase-27.md). Test repro di `log/fase-27-repro/` (pindahkan ke suite saat memperbaiki).

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| F-A1 | T | ON-04 | Link undangan melewati consent di tengah alur + ON-04 + izin notifikasi | `inviteJoinDoesNotSwapOnboardingOutForConsent`, `protectedAfterInviteStillReachesTurnOnExtension` | `fix/ON-04-invite-onboarding-states` | [ ] |
| F-A2 | S | ON-04 | Join undangan gagal sudah menyimpan mode Protected (terkunci, tanpa jalan batal) | `failedInviteJoinSavesNoMode` | `fix/ON-04-invite-onboarding-states` | [ ] |
| F-B1 | S | PF-01 | Become-protected dengan kode sendiri → Protected tanpa Guardian | `F-B1` | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B2 | S | PF-01 | Cek `has_members` tanpa kunci, anggota baru kehilangan link | `F-B2 replay` | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B3 | S | PF-01 | Join commit sebelum delete → salinan hantu memakan slot | `F-B3 state-only` | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B6 | S | PF-01 | Batas percobaan join di become-protected tidak bekerja (id salinan baru tiap kali) | baru di 27a | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B4 | S | DT-06 | Verdict `safe` terlepas saat url baris ditulis ulang | `F-B4` | `fix/DT-06-verdict-row-frozen` | [ ] (tunggu Q4) |
| F-A4 | S | GD-01 | Verdict Home ditimpa refresh lama | `homeVerdictIsNotUndoneByAnOlderRefresh` | `fix/GD-01-home-verdict-state` | [ ] |
| F-N1 | R | GD-01 | Home memasang verdict ke seluruh domain (aturan salah; tidak terlihat karena server satu baris per situs) | baru di 27e | `fix/GD-01-home-verdict-state` | [ ] |
| F-A5 | S | PR-05 | Spinner "memuat lagi" macet | `loadingMoreSpinnerClearsAfterAFailedRefresh` | `fix/PR-05-activity-list-states` | [ ] |
| F-A6 | S | PR-05 | Activity memakai model device lama setelah jadi Protected | baru di 27f | `fix/PR-05-activity-list-states` | [ ] |
| F-N2 | S | GD-06 | Push Protected dengan `scanId` membuka Shield | ganti `protectedPushTapOpensShield` | `fix/GD-06-push-tap-and-clear` | [ ] |
| F-N3 | S | GD-06 | Putus dari detail anggota tidak menghapus push (P13) | baru di 27g | `fix/GD-06-push-tap-and-clear` | [ ] |
| F-A3 | S | PF-01 | 401 lama saat switch → Session expired dengan sesi baru valid | baru di 27h | `fix/PF-01-session-lifecycle` | [ ] |
| F-A8 | S | PF-01 | `register()` tidak mereset `sentDeviceInfo` | baru di 27h | `fix/PF-01-session-lifecycle` | [ ] |
| F-B7 | R | GD-07 | Domain yang ditolak kembali ke antrean | `F-B7` | `fix/GD-07-rejected-stays-rejected` | [ ] |
| F-N4 | S | PF-01 | Salinan Protected membawa weekly summary + quiet hours tak terlihat | perbarui `settings.test.ts:296-312` | `fix/PF-01-protected-copy-settings` | [ ] (quiet hours tunggu Q2) |
| F-B5 | R/? | GD-05 | Guardian melihat riwayat anggota sebelum terhubung | probe `F-B5` | – | [ ] tunggu Q1 |
| F-A14 | R | ON-04 | Relaunch setelah registrasi undangan langsung `.done` | baru di 27d | `fix/ON-04-invite-onboarding-states` | [ ] |
| F-A15 | R | PR-05 | Verdict Detail tidak muncul di list Activity | baru di 27f | `fix/PR-05-activity-list-states` | [ ] |
| F-A12, F-A13, F-N7 | R | PF-01 | `me()` lama menulis guardian, key App Group tersisa, hapus akun → Session expired | baru di 27h | `fix/PF-01-session-lifecycle` | [ ] |
| F-A11/F-N5, F-N6 | R | PF-01 | Rollback toggle, quiet hours mulai = selesai | baru di 27i | `fix/PF-01-settings-rollback` | [ ] |
| F-A9 | R | GD-03 | "Dimatikan" lambat sampai ke Guardian | – | – | [ ] tunggu Q3 |
| F-B8, F-B9, F-B12, F-N10, F-A10 | R | – | Favicon ready, replica macet, kelas kunci, cron limit, refresh kode | lihat plan §27k | lihat plan §27k | [ ] |
| F-B10, F-B11, F-B13, F-N8, F-N9 | R | – | Diterima, dicatat di 27z | – | – | diterima |

## Ronde Fase 28 (truth hunt)

Plan + bukti: [`fase-28-truth-hunt.md`](fase-28-truth-hunt.md), [`qa/edge-matrix-2026-11-13.md`](qa/edge-matrix-2026-11-13.md), [`log/fase-28.md`](log/fase-28.md). Test repro di `log/fase-28-repro/` (pindahkan ke suite saat memperbaiki). Prio = putusan akhir reviewer. P0 = 0. A-01 dan U-01 menjadi P0 menurut bacaan ketat "status menenangkan yang salah": Alief memutuskan (plan K19). Hanya bug milik Alief yang bertahan, ditambah optimasi yang punya langkah kerja (OPT-02 + OPT-06, OPT-01, OPT-10; tabel kedua). Butir lapor saja, pertanyaan, optimasi lain, dan produk ada di plan.

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| A-01 | P1 | GD-01 / PR-04 | Guardian Home dan Protected Home menyimpan isi lama tanpa tanda setelah refresh gagal (D-alief-A12) | `BUG_A01_*`, `cell_refreshFailsAfterALoad` | `fix/GD-01-home-truth-states` (28a), `fix/PR-04-shield-stale-notice` (28b) | [ ] |
| U-01 | P1 | GD-01 | Hero Guardian Home "Keluarga Terlindungi!" saat muatan pertama masih berjalan | `test022_home_g_loading` | `fix/GD-01-home-truth-states` (28a) | [ ] |
| A-02 | P2 | GD-07 | Detail tetap "Blocked" + tombol setelah server menjawab `verdict_locked` (jawaban pertama hilang) | `BUG_A02_detailShowsNoVerdictAfterTheServerSaysTheLinkIsLockedSafe` | `fix/GD-07-detail-locked-reload` (28c) | [ ] |
| X-01 (paruh app) | P2 | GD-03 | App tetap mengirim `extensionLastSeenAt` saat akses Safari dipersempit; Guardian melihat "connected" | baru di 28d | `fix/GD-03-no-heartbeat-when-narrowed` (28d) | [ ] |
| U-02 | P2 | GD-07 | Pesan "Gagal menyimpan" di kartu pending setengah tertutup tab bar | `test025_home_g_verdict_failed` (merah: iPhone 17, ID, ukuran default; penjaga: SE, EN) | `fix/GD-07-home-verdict-notice-visible` (28e) | [ ] |
| U-05 | P2 | GD-05 / GD-03 | Baris Activity memotong nama di ekor; bagian domain hilang | baru di 28f: unit pemecahan judul (`Tests/ActivityModelTests.swift`) + screenshot SE (label aksesibilitas memuat teks penuh) | `fix/GD-05-activity-row-keeps-domain` (28f) | [ ] |
| U-17 | P2 | DT-01 | Isi tercetak menembus baris pertanyaan di footer Detail (ukuran default) | baru di 28g: kepekatan latar footer di tepi atas pertanyaan (`Tests/DetailFooterTests.swift`) | `fix/DT-01-footer-question-readable` (28g) | [ ] |
| U-06, U-08 | P2 | ON-04 | Langkah onboarding di belakang footer di SE ukuran default; tombol consent terpotong di AX5 | `test003_on_ext`, `test008_on_safariDefault` (merah: SE, EN, ukuran default; penjaga: iPhone 17, ID); label consent dan kolom nama ON-02 diukur di AX3 (28n) | `fix/ON-04-onboarding-footer-scroll` (28h); kolom nama ON-02 kalau rusak di AX3: `fix/ON-02-name-field-at-ax` (28p) | [ ] (tunggu PR #484) |
| B-04, A-09 | P3 | EX-07 | URL scan disimpan mentah: verdict tidak ditemukan untuk bentuk tidak normal; spasi di tepi → 500 (termasuk paruh backend A-03) | `h1-identity`, `h2-poison` (ditulis ulang) | `fix/EX-07-scan-url-normal-form` (28j) | [ ] |
| H5-02 | P3 | PF-01 | Klaim ringkasan mingguan 6,8 s terhadap batas 10 s; kalau melempar, push "protection off" yang sudah diklaim hilang | `h5-explain` N04, `h5-proto` P4 | `fix/PF-01-weekly-summary-query` (28k) | [ ] |
| B-02 | P3 | GD-05 / GD-06 | Baris tetap `warning` setelah kunjungan blocked dengan skor tidak lebih tinggi; push blocked berulang | "BUG B-02a", "BUG B-02b" | `fix/GD-06-blocked-status-push-once` (28l) | [ ] (hanya baris tanpa verdict; baris ber-verdict tunggu Q4 fase 27) |
| B-06 | P3 | EX-06 | `GET /verdicts` dengan URL > 2048 karakter → 500, seharusnya 422 | "BUG B-06" | `fix/EX-06-verdicts-long-url-422` (28m) | [ ] |
| B-07 | P3 | GD-04 | NUL di path param anggota → 500, seharusnya 404 | "BUG B-07" | `fix/GD-04-member-id-nul-404` (28m) | [ ] |
| A-03, A-10 | P3 | GD-05 | Satu baris tidak terbaca menggagalkan seluruh daftar; error decode / 500 dibaca "Check your connection" | `BUG_A03_*` | `fix/GD-05-decode-error-copy` (28m, teks saja) | [ ] (toleransi baris tunggu Q11) |
| A-06 | P3 | GD-01 | Home Pribadi "belum terlindungi" sekilas sebelum status dibaca | `BUG_A06_personalHomeClaimsOffBeforeTheFirstRead` | `fix/GD-01-home-truth-states` (28a) | [ ] |
| A-08 | P3 | GD-03 | "active in 0s" / "active dlm 0 dtk" | `BUG_A08_*` | `fix/GD-03-last-seen-just-now` (28m) | [ ] |
| A-12 | P3 | GD-06 | Hanya Guardian Home yang memuat ulang saat push datang di depan | baru di 28m | `fix/GD-06-push-refreshes-open-screens` (28m) | [ ] |
| A-14 | P3 | PF-01 | "1 people you protect will be disconnected." | `h2-l10n-audit` | `fix/PF-01-plural-people` (28m) | [ ] |
| A-15 | P3 | GD-01 / PF-01 | Teks ID "Hubungi agar…" (kata salah; Home Pribadi + kartu Profile); "belajar mingguan" tunggu Q22b | baru di 28m | `fix/GD-01-id-copy-connect` (28m) | [ ] |
| U-09 | P3 | PR-01 | Catatan 14 hari di Connect berjalan di bawah "Nanti saja" | `test128_connect_scan` (merah: iPhone 17, ID, ukuran default) | `fix/PR-01-connect-scan-note` (28m) | [ ] |
| U-11 | P3 | GD-07 | "Tandai Aman" di bawah keyboard di sheet alasan aman | `test082_dt_safe_reason` (merah: iPhone 17, ID, ukuran default; SE, EN: rekam ulang dulu, merah kedua kalau tertutup; tanpa penjaga) | `fix/GD-07-safe-reason-submit-reachable` (28m) | [ ] |
| U-13 | P3 | PR-03 | Baris kode halaman undangan melewati padding pada 320 px | `h4-pages` | `fix/PR-03-join-page-polish` (28m) | [ ] |
| U-15 | P3 | PR-03 | Petunjuk halaman undangan bilang link sudah disalin sebelum tap | `h4-pages` | `fix/PR-03-join-page-polish` (28m) | [ ] |
| U-14 | P3 | PF-01 | `/terms`: "(/privacy)" teks biasa, bukan link | `h4-pages` | `fix/PF-01-terms-privacy-link` (28m) | [ ] |
| U-18 | P3 | PR-01 | "1 hour" di pesan vs "60 minutes" di tombol | baru di 28m | `fix/PR-01-rate-limit-copy` (28m) | [ ] |
| H5-01 | P3 | BE | README kapasitas DB ≈ 2× terlalu tinggi (terukur ≈ 3,3 KB per scan, 500 MB di sekitar 150 ribu scan) | – (dokumen) | `fix/BE-readme-db-capacity` (28m) | [ ] |
| U-03, U-04 | P3 (P2 kalau muncul di AX3) | GD-01 / PF-01 | Badge `.fixedSize()` melebarkan halaman dan memeras kolom domain di AX5 | sel F / D di matriks | `fix/GD-01-badge-wraps-at-ax` | [ ] ukur AX3 dulu (28n) |
| U-07 | P3 (P2 kalau muncul di AX3) | DT-01 | Footer Detail dan halaman gagal / hilang menutup judul di AX5 | sel F / D di matriks | `fix/DT-01-footer-at-ax` | [ ] ukur AX3 dulu (28n) |
| U-12 | P3 (P2 kalau muncul di AX3) | GD-05 | Kata terpotong di tengah pada AX5 ("Semu/a", "Wasp/ada") | sel `act-*` F / D | `fix/GD-05-filter-words-at-ax` | [ ] ukur AX3 dulu (28n) |
| A-04 | P3 | GD-04 | Hitung mundur kode mengikuti jam HP (desain diputuskan, #227) | `BUG_A04_*` | – | [ ] tunggu Q4 |
| A-07 | P3 | PF-01 | Sheet hapus akun tanpa kalimat keluarga kalau daftar belum termuat | `BUG_A07_*` | – | [ ] tunggu Q17 |
| X-07 | P3 | GD-07 | `not_safe` di shared host `host_path` menyebar ke host lain di domain yang sama | `h3-chain.test.ts` "BUG X-07 candidate" | – | [ ] tunggu Q7a |
| U-10 | P3 | – | 36 dari 164 kontrol < 44 pt menurut frame aksesibilitas (likely) | `h4-check` SMALL | – | [ ] cek di iPhone dulu |
| H5-03 | P3 | BE / CI | `bundle-size.mjs` gagal di `main` (317.017 B / 295.000 B), tidak dijalankan di CI | `node backend/ci/bundle-size.mjs` | – | [ ] tunggu Q26 |

Optimasi yang punya langkah kerja di plan (dicentang di sini juga, per PR):

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| OPT-02, OPT-06 | P2 (performa) | GD-01 | Family Home membaca sampai 10 halaman `GET /scans` berurutan; `GET /devices/me` dua kali per foreground | baru di 28i (repository penghitung) | `fix/GD-01-family-home-paging` (28i) | [ ] |
| OPT-01 | P3 | GD-05 | `listScans` menghitung lateral verdict untuk setiap scan owner sebelum membatasi halaman (keluarga terberat 1.895 ms) | `h5-explain` S17 sampai S21, `h5-proto` P2, P3 | `fix/GD-05-family-list-query` (28o) | [ ] |
| OPT-10 | P3 | PR-02 | `ConnectedBackground@2x.jpg` 2.297.706 B, bisa 657.475 B (JPEG q80) | screenshot sebelum / sesudah | `fix/PR-02-connected-background-size` (28m) | [ ] |

## Diteruskan ke tim lain

| ID | Ke | Isi singkat | Status |
|---|---|---|---|
| | | | |
