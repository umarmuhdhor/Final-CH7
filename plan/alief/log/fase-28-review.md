# Review fase 28: putusan reviewer dan review plan

Plan: [`../fase-28-truth-hunt.md`](../fase-28-truth-hunt.md). Log: [`fase-28.md`](fase-28.md). Matriks: [`../qa/edge-matrix-2026-11-13.md`](../qa/edge-matrix-2026-11-13.md).

File ini menyimpan dua hal supaya plan bisa dicek tanpa laporan mentah (laporan mentah hunter dan reviewer tidak disimpan di repo):

1. Tabel putusan tiga reviewer bantahan (r1, r2, r3, 13 Nov 2026), disalin ringkas dan diterjemahkan. **Putusan reviewer menang** atas hunter.
2. Ringkasan review plan ronde 1 sampai ronde 6 (14 Nov 2026).

Angka memakai format Indonesia: `1.258` = seribu dua ratus lima puluh delapan, `3,3` = tiga koma tiga.

Arti kolom putusan: **bertahan** · **bertahan dengan perubahan** (severity, pemicu, atau baris dikoreksi) · **ditolak** · **duplikat** (sudah dicatat di issue / BH) · **perlu pertanyaan** (perilaku mengikuti aturan tertulis, atau aturannya belum ada). Confidence: **verified (run)** = repro dijalankan ulang reviewer · **verified (read)** = dibaca dari kode · **rekam** = pohon aksesibilitas / screenshot terekam, tanpa asersi · **likely** = belum terbukti penuh.

## r1: backend dan performa (25 butir)

Hasil: bertahan 12, bertahan dengan perubahan 8, ditolak 1, duplikat 2, perlu pertanyaan 2.

| ID | Sev hunter | Putusan | Sev akhir | Confidence | Bukti kunci |
|---|---|---|---|---|---|
| B-01 | P1 | perlu pertanyaan (Umar) | P2 kalau dikonfirmasi | verified (run) untuk perilaku | Tiga repro gagal seperti ditulis, tetapi perilakunya = aturan tertulis (`backend/API.md:491-494`, `contracts/api.md:57`). Varian blocked (B-01b/c) tidak bisa terjadi dengan extension asli: situs blocked dijawab dari block memory 14 hari (`report.js:16`, `block-memory.js:1-6`, #231). Hanya situs warning yang dikirim ulang |
| B-02 | P2 | bertahan dengan perubahan | P3 | verified (run) | Dua test gagal seperti ditulis. B-02a butuh perubahan ambang admin; B-02b (5 push) butuh 4 post blocked untuk satu situs, yang tidak dikirim extension asli setelah blokir pertama. Hanya klien buatan atau setelah ambang diubah |
| B-03 | P2 | perlu pertanyaan (Umar) | P3 | verified (run) untuk 422 | 422 terulang. Aturan terdokumentasi (`backend/API.md:514`, `:252`); tidak ada keputusan soal jam cepat. Butuh jam manual > 5 menit di depan |
| B-04 | P3 | bertahan | P3 | verified (run) | 4 sel identitas gagal. Hanya klien buatan: extension mengirim `origin + pathname` hasil parse WHATWG (`report.js:33-36,55`). Akar sama dengan A-03 / A-09: `routes/scans.ts:53,163` menyimpan string mentah |
| B-05 | P3 | ditolak (sebagai bug backend) | - (kata dokumen, Umar) | verified (run) untuk perilaku | Harapan test salah: #377 (lead) memutuskan `notified` dari keputusan yang mengantre push, didokumentasikan "queued" (`backend/API.md:564-566`). Sisa: kata "got" di `contracts/api.md:51` |
| B-06 | P3 | bertahan | P3 | verified (run) | `{"over":500,"at2048":200,"postScansOver":422}` terulang. Tidak ada keputusan yang membuat 500 disengaja. URL yang sama tidak bisa disimpan, jadi hanya kode status yang salah (`routes/verdicts.ts:34-60`) |
| B-07 | P3 | bertahan | P3 | verified (run) | 3 × 500 terulang (22021). `DECISIONS.md:327` menutup NUL untuk nama device; tiga path param ini terlewat (`routes/family.ts:64-65,80,92`) |
| B-08 | P3 | duplikat issue #476 (terbuka) | P3 | verified (read) | Lead di #476 akan menambahkannya ke kontrak; teks kontrak Alief sudah ditempel di sana |
| A-03 (paruh backend) | P2 | bertahan dengan perubahan | P3 untuk paruh backend | verified (run) | Backslash → 201 terulang. Hanya klien buatan dengan token anggota. P2 milik paruh app (r2) |
| A-09 | P3 | bertahan | P3 | verified (run) | `POST 500`, `PostgresError 23514` (cek `scans.url`, `init.sql:53`). `new URL()` memotong spasi, string yang disimpan tidak. Akar sama dengan B-04 |
| H5-01 | P2 | bertahan dengan perubahan | P3 | verified (run), angka dikoreksi | Ukuran dibaca ulang: 1.258 MB, `scans` 683 MB, `scan_archive` 345 MB; ≈ 150 MB artefak seed. Koreksi: ≈ 3,3 KB per scan hidup, 500 MB di sekitar 150 ribu scan. README ≈ 2× terlalu tinggi. Alert `db_size_high` sudah ada |
| H5-02 | P2 | bertahan dengan perubahan | P3 (laten) | verified (run) untuk waktu; timeout belum terbukti | Ulang: 6.791 ms, 80 seq scan; prototipe 52 ms, hitungan sama. Di Supabase Free DB penuh di sekitar 150 ribu scan (≈ 3 s di Mac ini). Tambahan: kalau klaim melempar, push "protection off" yang sudah diklaim hilang (`cron/notifications.ts:43-44`) |
| H5-03 | P3 | bertahan | P3 | verified (run) | `index.js 317017 B (limit 295000), gzip 103739 B (limit 97500)` → `FAIL`. Tidak ada step di `backend.yml`. Celah CI sudah diketahui (fase 22 K11); yang baru: gerbangnya gagal |
| OPT-01 | P2 | bertahan dengan perubahan | P3 | verified (run) | Keluarga terberat (1.013 scan) 1.895 ms; prototipe 1,3 ms, 21 baris sama (md5 sama). Tetapi itu keluarga 1 % teratas seed; keluarga p90 24 ms. Prototipe hanya halaman pertama (tanpa cursor, tanpa filter status) |
| OPT-02 | P2 | bertahan | P2 | verified (read) | `GuardianHomeModel.swift:291-305`: Family membaca sampai 10 halaman berurutan, Personal berhenti lebih awal. Angka "14 s" = keluarga 1 % teratas saja |
| OPT-03 | P2 | bertahan dengan perubahan | P3 | verified (run) | Sama dengan H5-02: 52 ms, hitungan sama |
| OPT-04 | P2 | bertahan dengan perubahan | P3 | verified (run) | Sama dengan H5-01 dengan angka terkoreksi. Tidak ada yang menghapus baris `admin.scan_archive` (hanya `stripped_at`) |
| OPT-05 | P3 | bertahan | P3 | verified (run) | Sama dengan H5-03 |
| OPT-06 | P3 | bertahan | P3 | verified (read) | `AppEnvironment.swift:335` dan `GuardianHomeModel.swift:161` sama-sama memanggil `repository.me()`; tanpa penggabungan (`ApiRepository.swift:38-51`) |
| OPT-07 | P3 | bertahan | P3 | verified (read) | `FamilyShieldModel.swift:64-77`: satu daftar per anggota hanya untuk satu id. Perubahan kontrak (Umar) |
| OPT-08 | P3 (diketahui) | duplikat fase 22 K5 / 22a-3 | - | - | Hunter sendiri menyebutnya (`fase-22-performance.md:98-99,124`) |
| OPT-09 | P3 | bertahan dengan perubahan | P3 | verified (run, lokal) | `scans_owner_shot` dan `scans_original_shot` sudah di daftar buang fase 20c. Hanya `verdicts_not_safe` yang baru |
| OPT-10 | P3 | bertahan | P3 | verified (run) | 2.297.706 B di disk; `sips` q80 memberi 657.475 B |
| OPT-11 | P3 | bertahan | P3 (Umar, Imelda) | verified (read) | `pipeline.js:186-198`: `/analyze` jalan untuk setiap halaman kecuali daftar sudah memutuskan; tidak ada pengecualian host tepercaya |
| OPT-12 | P3 | bertahan | P3 | verified (read) | Trigger `BEFORE INSERT OR UPDATE` pada semua kolom (`init.sql:143-169`). Untung ≈ 4 ms per jam: nilai terendah |

## r2: logika app dan UI (35 butir)

Hasil: bertahan 17, bertahan dengan perubahan 11, ditolak 2, duplikat 3, perlu pertanyaan 2. Severity akhir: P0 0, P1 2, P2 5.

"AX5" = `UICTContentSizeCategoryAccessibilityXXXL`. Batas proyek = "sampai XL" (`ref/R5-konvensi.md:11`) = AX3 di repo ini. Hunter 4 menjalankan default dan AX5 saja, jadi temuan yang hanya muncul di AX5 berada di luar batas tertulis sampai terbukti di AX3.

### Tabel A: logika app

| ID | Sev hunter | Putusan | Sev akhir | Confidence | Bukti kunci |
|---|---|---|---|---|---|
| A-01 | P1 (P0 bacaan ketat) | bertahan dengan perubahan | P1 untuk Guardian Home dan Protected Home; Detail / Profile / Member detail = pertanyaan | verified (run) | Ulang: `hero 'Family protected!': true … says it may be old: false`; 6 dari 8 sel gagal. D-alief-A12 hanya menyebut "daftar dan kartu Shield". Baris `refreshFailed` ada di `f6f5afde`, hilang saat redesign. Bukan P0: isi benar saat dimuat terakhir dan A12 menyimpannya dengan sengaja; yang hilang hanya tanda |
| A-02 | P1 | bertahan dengan perubahan | P2 | verified (run) | Ulang: `server verdict: safe \| Detail badge: blocked`. Teks footer sudah benar ("This site stays safe…", `DetailFooter.swift:30`); badge dan tombol bertentangan. Butuh jawaban hilang setelah commit (timeout 20 s). Buka ulang Detail memperbaikinya |
| A-03 (paruh app) | P2 | bertahan dengan perubahan (menyerap A-10) | P3 | verified (run) | Ulang: Home, Family Activity, daftar keluarga Profile, Member detail semua gagal. Akar nyata (`APIClient.swift:65-73`). Pemicu = request buatan. Yang tersisa untuk pengguna hari ini: teks "Check your connection" untuk error decode atau 500 |
| A-04 | P3 + pertanyaan | bertahan | P3 | verified (run) | 7 dari 8 sel selisih berbeda dari 360 s server. Jam HP + clamp = desain yang diputuskan (D-alief-C09, #227); butuh jam HP salah |
| A-05 | P3 | perlu pertanyaan (Umar, #40) | P3 | verified (run) | 5 dari 6 sel Active. Kode menyebutnya disengaja (`ExtensionStatus.swift:70`). Hanya tercapai sebelum iOS 26.2 dan jam dimundurkan |
| A-06 | P3 | bertahan | P3 | verified (run) state, verified (read) layar | Ulang: `before the first read: isActive false`. Saat cold start tertutup splash; bisa tampil beberapa frame saat pindah Family → Pribadi (`MainTabView.swift:86-95`) |
| A-07 | P3 | bertahan dengan perubahan | P3 | verified (run) | Lebih sempit: `members` kosong hanya kalau daftar belum pernah termuat di sesi Profile itu. Kalimat yang tersisa sudah menyebut "family links" |
| A-08 | P3 | bertahan | P3 | verified (run) | Ulang: `'active in 0s'`, `'active dlm 0 dtk'`; asersi Indonesia yang diperlebar gagal seperti dimaksud (issue 40 dari 40) |
| A-09 | P3 | bertahan (baris r1, backend saja) | P3 | verified (run) oleh r1 | Tidak ada di sisi app |
| A-10 | P3 (laten) | duplikat A-03 paruh app + pertanyaan ke Umar | P3 | verified (run) | 8 dari 8 racun → 0 baris. Butuh perubahan backend / kontrak untuk menyala. Satu perbaikan (decode per baris, atau case `unknown`) menutup keduanya |
| A-11 | P3 | ditolak | - | verified (read) | (a) status `nil` hanya sampai baca lokal; empty state baru tampil setelah daftar jaringan termuat (`ActivityView.swift:12-13`). (b) "Off for N" didokumentasikan dari heartbeat terakhir (`ActivityEmptyState.swift:56`, #183) |
| A-12 | P3 | bertahan | P3 | verified (read) | Satu pembaca `pushesWhileOpen` (`GuardianHomeView.swift:117`). Edge-cases 11 Nov #4 hanya memperbaiki Home |
| A-13 | P3 + pertanyaan | duplikat issue #476 | P3 | verified (read) | Lead di #476: `lockedUntil` opsional di `Verdict`. Sisa: komentar basi `VerdictLock.swift:8` |
| A-14 | P3 | bertahan dengan perubahan | P3 | verified (read) + skrip | "1 people you protect will be disconnected." bisa tampil. "Try again in 1 minutes" tidak (menit mulai 600 s). `keys with plural variations 0` |
| A-15 | P3 | bertahan | P3 | verified (read) | Katalog baris 179, 269 ("Hubungi agar…": kata salah), 6992, 7012 ("belajar mingguan": pilihan kata PM) |
| A-16 | P3 + pertanyaan | ditolak | - | verified (read) | `reset()` menulis bahasa sistem iPhone (`AppSettings.swift:233`), seperti default lain (`:241-253`). Tidak ada pilihan pengguna yang bertahan |
| A-17 | P3 (desain) | duplikat BH-31 | P3 | verified (read) | Hunter sendiri menyebutnya. Baris benar `GuardianHomeModel.swift:88-98` |

### Tabel U: UI

| ID | Sev hunter | Putusan | Sev akhir | Confidence | Bukti kunci |
|---|---|---|---|---|---|
| U-01 | P1 | bertahan | P1 (bukan P0) | verified (read) + rekam | `GuardianHomeView.swift:178-193`: `.loading` jatuh ke `else` terakhir. Pindah Pribadi → Family membuat model baru tanpa splash, jadi tulisan tampil selama seluruh muatan. Cabang Pribadi menjaga hal ini (`:151-153`). Bukan P0: berakhir sendiri dan skeleton bilang "memuat" |
| U-02 | P2 | bertahan dengan perubahan | P2 | rekam + screenshot | Pesan tidak hilang: "Coba lagi" dan separuh kartu terlihat di samping tab bar; judul "Gagal menyimpan" tertutup. Haptic error tetap berbunyi. Kata diperbaiki: "setengah tertutup" |
| U-03 | P2 | bertahan dengan perubahan (gabung U-04) | P3 di AX5; P2 kalau muncul di AX3 | rekam + screenshot | 8 sel, semua dengan baris `OFFX`. Hanya AX5. Satu akar dengan U-04: badge `.lineLimit(1)` + `.fixedSize()` |
| U-04 | P2 | bertahan dengan perubahan (gabung U-03) | P3 di AX5; P2 kalau muncul di AX3 | screenshot (sel dari aturan) | 16 dari 19 sel tanpa baris cek, ditandai aturan lebar. Sampel: 5 dari 6 nyata; `F/pf-fail-me` bukan masalah ini |
| U-05 | P2 | bertahan | P2 | verified (read) + screenshot | `ActivityView.swift:529` `.truncationMode(.tail)`; komentar `:516` salah untuk host panjang. Baru untuk baris Activity (BH-13 = pill Detail, sudah diperbaiki di `main` `8645d7b0`; catatan ronde 4). `F/member-edge-long` tidak menampilkan barisnya |
| U-06 | P2 | bertahan dengan perubahan (lebih luas; menyerap U-08) | P2 | rekam + screenshot | Terlewat hunter: terjadi juga di **ukuran default di iPhone SE**. `E/on-ext`: langkah y 453 sampai 606, consent 464, tombol 569; screenshot tanpa langkah. Setelah gulung terlihat. Sel itu dihitung "pass". Di AX5 tidak tercapai. `D/on-name` positif palsu. PR #484 mengubah `TurnOnExtensionView.swift`: cek ulang setelah merge |
| U-07 | P2 | bertahan dengan perubahan | P3 di AX5; P2 kalau muncul di AX3 | rekam + screenshot | 32 dari 40 sel punya OVERLAP. Detail bisa digulung; halaman gagal / hilang tidak. `D/dt-g-blocked-end`, `D/dt-g-edge-long-end` positif palsu |
| U-08 | P2 | bertahan dengan perubahan (gabung ke U-06) | P3 di AX5 | screenshot; "kerangka sama" likely | 1 sel, SE × AX5 saja. Dua pilihan tetap berbeda ("Izinkan cek…" / "Lanjut tanpa…") |
| U-09 | P3 | bertahan | P3 | rekam; perangkat likely | Direkam di keadaan simulator "scanning not available"; catatan dan "Nanti saja" di luar kotak kamera, jadi iPhone seharusnya sama |
| U-10 | P3 | bertahan | P3 | likely | Frame aksesibilitas bukan area sentuh; 36 = batas atas. QA-A Oktober menemukan 0 di UI lama |
| U-11 | P3 | bertahan | P3 | rekam + screenshot | `UNDERKB safeReason.submit`. Sheet bisa digulung dan `.scrollDismissesKeyboard(.interactively)` dipasang |
| U-12 | P3 | bertahan | P3 | screenshot (sel dari aturan) | 33 sel ditandai nama + konfigurasi. 6 dari 6 sampel benar ("Sem/ua", "Wasp/ada"). Hanya AX5 |
| U-13 | P3 | bertahan | P3 | screenshot | Tidak ada yang terpotong. 320 pt hanya dengan Display Zoom di SE |
| U-14 | P3 | bertahan | P3 | verified (read) | `terms.ts:36,65` "(/privacy)" teks biasa; `support.ts:25,45` memakai link |
| U-15 | P3 | bertahan | P3 | verified (read) | Petunjuk di `join-page.ts:62`; salin hanya saat tombol install ditekan (`:144-145`) |
| U-16 | P3 | perlu pertanyaan (desain / PM) | P3 | likely (pindaian teks) | "Nyalakan sekarang" ada di Figma (490), jadi bukan beda. Baris load-more dan baris QR berbeda. "Berlaku 24 jam" = Figma lama |
| U-17 | P2 | bertahan | P2 | rekam + screenshot | Ukuran default, SE dan iPhone 17, diam: "Reasons detected" tercetak menembus "Is this site dangerous?". Penyebab: pertanyaan duduk 28 pt di dalam gradien 0 → 0,96 pada 30 % pertama (`DetailFooter.swift:100,104-112`) |
| U-18 | P3 | bertahan | P3 | verified (read) | `ConnectModel.swift:52` "…Try again in 1 hour." di atas tombol "60 minutes". "GMT+7" = teks sistem |

## r3: rantai dan produk (12 + 21 butir)

### Bagian 1: rantai

Hasil: bertahan 4, bertahan dengan perubahan 5, duplikat 2, perlu pertanyaan 1, ditolak 0. Severity akhir: P0 0, P1 0, P2 3 (X-01, X-04a, X-08 kalau dikonfirmasi), sisanya P3.

| ID | Sev hunter | Putusan | Sev akhir | Confidence | Bukti kunci |
|---|---|---|---|---|---|
| X-01 | P1 (P0 bacaan ketat) | bertahan dengan perubahan | P2 | verified (read) jalur app; jalur extension "likely tidak" di perangkat | Ulang memberi baris sama (30 PATCH), tetapi `fetchJSON` di skrip adalah stub yang selalu sukses. Di HP dengan akses dipersempit background page tidak punya izin host, dan backend tanpa CORS: PATCH extension kemungkinan gagal. Yang berdiri: handler native mencap `lastSeenAt` apa pun `allSites` (`SafariWebExtensionHandler.swift:18`), dan app mengirimnya walau statusnya `.off(.someSitesOnly)` (`AppEnvironment.swift:315-323`). #380 tidak membahas akses dipersempit |
| X-02 | P2 (laten) | duplikat issue #323 (ditutup, diputuskan 8 Nov) | P3 (laten) | verified (run) | 9 dari 18 sel. #323 menyebut kasus yang sama dan memutuskan `thresholds` opsional di body `/analyze`; belum dibangun. Produksi 30/80 |
| X-03 | P2 | duplikat issue #325 (ditutup, diputuskan 9 Nov) + `domain-lists-expected-diff.json` | P3 (catatan untuk #318 / #448) | verified (run) | #325 memutuskan tiga daftar tetap terpisah, dengan test drift CI setelah #318. 13 host sudah tercatat. Yang baru hanya akibat yang terlihat: `sway.cloud.microsoft` dan `s.id` |
| X-04 | P2 | bertahan dengan perubahan | P2 untuk (a) `/analyze` gagal; P3 untuk (b) verdict aman | verified (run) sampai body `POST /live`; teks island verified (read) | Dua keputusan (#379, #369) menyebut badge / pill saja, bukan island: aturan yang belum dibawa ke permukaan kedua, bukan keputusan yang dilanggar. (b): "Aman" = kata Guardian; hanya "0 %" yang janggal |
| X-05 | P3 (laten) | bertahan | P3 | verified (run) angka extension; Swift verified (read) | 48 dari 160 terulang. Komentar Swift menyebutnya jalan pintas. Butuh `warnAt` ≥ 50; produksi 30 |
| X-06 | P3 | bertahan dengan perubahan | P3 | verified (run, `shoo_f28`) | `rows 15 \| refused 6` terulang. Lebih sempit: `shop_x.web.app` tidak bisa ada; link 2121 karakter = B-06; jadi 4 bentuk nyata. `GET /verdicts` untuk `www.co.id` menjawab 200, bukan 422 |
| X-07 | P3 | bertahan | P3 | verified (run, `shoo_f28`) | `accounts.google.com → not_safe`, `www.office.com → not_safe` (2 dari 6). Tidak terjangkau dari extension (bertanya mulai skor 30). Teks kontrak tidak memutuskan host `host_path`: pertanyaan |
| X-08 | P2 | perlu pertanyaan (Umar; kartu: Alief) | P2 kalau dikonfirmasi | verified (run) nilai extension; verified (read) app | 4 dari 7 terulang. Setiap tempat menampilkan apa yang diminta keputusan (`contracts/api.md:109,151`, #382, BH-25); aturannya tidak punya kasus shared host. Detail juga tidak menampilkan host: pill = domain terdaftar + path (`DetailView.swift:444-451`, perbaikan BH-13 `8645d7b0`), jadi `sites.google.com/view/x` tampil `google.com/view/x`. Host bersama tidak terlihat di layar mana pun; hanya "Salin link" menyalin link penuh (dikoreksi ronde 4) |
| X-09 | P3 | bertahan | P3 | verified (run) | 3 body rusak mengosongkan daftar; daftar kosong yang sah = sesuai desain. Bukan BH-43 |
| X-10 | P3 | bertahan dengan perubahan | P3 | verified (run) | `cells run: 84; FAIL-WRONG: 10` (7 `/analyze` + 3 `/blocklist`). Kalimat soal RDAP dibuang: #379 hanya mencakup `/analyze` yang dilewati atau gagal |
| X-11 | P3 | bertahan dengan perubahan | P3 | verified (run), hitungan dibaca ulang | "7.607 dari 8.637" terulang tetapi daftarnya memuat aturan privat juga. Yang berdiri: 6 suffix `.id` tempat `new_domain` tidak pernah menyala |
| X-12 | P3 | bertahan | P3 | verified (read) | `scan-result.schema.json:53`, `app-group-keys.md:14`, `ScanResult.swift:58` seperti dikutip. Bagian `ScoreThreshold` milik #383 |

### Bagian 2: produk

Hasil: bertahan 6, bertahan dengan perubahan 7, perlu pertanyaan 6, duplikat 1, ditolak 1. Butir produk tidak punya severity (kolom severity diisi "-").

| ID | Sev hunter | Putusan | Sev akhir | Confidence | Bukti kunci |
|---|---|---|---|---|---|
| PR-A-01 | - | perlu pertanyaan (PM Richard; teks: Alief) | - | verified (read) | Halaman privasi menulis "No ads, no analytics, no tracking" (`routes/privacy.ts:39`). Usaha M. Hitungan di bawah 5 disimpan "< 5" |
| PR-A-02 | - | perlu pertanyaan (Umar) | - | verified (read) oleh r1 | Kontrak + `ShooShared` milik Umar: bukan "S + S" untuk Alief sendiri |
| PR-A-03 | - | duplikat issue #476 | - | verified (read) | B-08 dan A-13 juga duplikat #476 |
| PR-C-01 | - | bertahan dengan perubahan | - | verified (read) | Diminta lead di #183 (4 Nov) dan badan PR #264. Perubahan: keputusan label / gabung saklar harus datang dulu. S untuk flag + satu jawaban desainer |
| PR-C-02 | - | bertahan dengan perubahan | - | verified (read) | "14 s" dan "1.427 ms → 1,4 ms" dibuang (keluarga 1 % teratas). Yang berdiri: Family membaca sampai 10 halaman, `me()` dua kali. Aturan berhenti harus menghitung baris anggota saja |
| PR-C-03 | - | perlu pertanyaan (Umar) | - | verified (read) | Bertentangan dengan D-alief-C09 / #227. Lima temuan di bawahnya: A-04 desain, A-05 pertanyaan, A-13 duplikat, B-03 pertanyaan, A-08 bug format |
| PR-C-04 | - | bertahan dengan perubahan | - | verified (run) untuk hitungan | Cakupan: dua Home saja (A12) + hero netral saat memuat. Detail, Profile, Member detail = pertanyaan. "27 literal, 18 dipakai sekali" benar |
| PR-C-05 | - | bertahan dengan perubahan | - | rekam (r2) | Di luar batas proyek (AX3). Ukur AX3 dulu. Yang nyata hari ini: U-06 di SE ukuran default (P2). Keluar dari top 5 |
| PR-C-06 | - | bertahan dengan perubahan | - | verified (run) oleh r1 | Perbaikan query P3 laten. Simpan / buang = pertanyaan PM setelah UQ-03 |
| PR-C-07 | - | perlu pertanyaan (PM, desainer) | - | verified (read) | Default = pilihan produk tanpa sumber tertulis; mengubahnya = migrasi, bukan S |
| PR-C-08 | - | bertahan dengan perubahan | - | verified (read) | Usaha M, bukan S: bahasa per halaman, header CSP, tanpa binding `assets`, halaman punya test. Nilai rendah |
| PR-C-09 | - | perlu pertanyaan (PM, Umar) | - | verified (read) | Klaim "tidak ada yang bisa memulai demo di Release" terlalu kuat: `-settings.demoMode YES` menyalakannya (`DECISIONS.md:389`), hanya dari Xcode atau `devicectl` |
| PR-C-10 | - | bertahan | - | verified (run) oleh r1 | 2.297.706 B; `sips` q80 657.475 B |
| PR-C-11 | - | ditolak | - | verified (read) | Bertentangan dengan #325 ("Do not merge the three lists into one file"). Dasarnya (X-03) duplikat |
| PR-C-12 | - | perlu pertanyaan (Umar, Imelda) | - | verified (read) oleh r1 | Tukar-tambah deteksi / privasi di luar folder Alief; sudah ada draf pertanyaan |
| PR-C-13 | - | bertahan dengan perubahan | - | verified (run) oleh r1 | Angka r1: ≈ 3,3 KB per scan, 500 MB di sekitar 150 ribu scan. README = S, milik Alief. Aturan ukuran mengubah D-dash-17: pertanyaan |
| PR-R-01 | - | bertahan | - | verified (run) | 81 dari 81 dibuktikan ulang |
| PR-R-02 | - | bertahan | - | verified (run) | Pemanggil view dibuang di `bc369191`. A-17 duplikat BH-31 |
| PR-R-03 | - | bertahan | - | verified (run) | 26 dari 26. Tambahan: `onboardingConnectPassed` juga argumen launch di `DeepLinkUITests.swift:16,60` |
| PR-R-04 | - | bertahan | - | verified (run) | Hanya dua `Contents.json` yang menyebutnya; 52 KB masing-masing |
| PR-R-05 | - | bertahan | - | verified (run, lokal) | EXPLAIN untuk batas antrean 24 jam memilih `verdicts_eligible_domain`. Tetap cek UQ-11 + `stats_reset` di produksi |

## Review plan ronde 1 (14 Nov 2026)

Satu reviewer independen membaca plan, matriks, log, dan baris tracker di `9e5403ba`, baca saja. Hasil: **23 cacat**: P0 1, P1 2, P2 11, P3 9. Semua klaim dicek ulang terhadap file dan baris yang dikutip sebelum diperbaiki.

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| 1 | P2 | Baris API di ringkasan matriks menyebut B-04 di dalam 1.642 | Plan, matriks §2, log: B-06 1 sel, B-07 3 sel di dalam 1.642; B-04 4 sel identitas di luar |
| 2 | P2 | 6 sel `h3-norm` (`fallback≠PSL`) tanpa ID dan tanpa penjelasan | Baris baru di plan → "Fail-wrong yang diperiksa dan bukan temuan" (`content.js:18-30`); matriks §5.1, §8, §12: "dijelaskan, bukan temuan"; satu baris catatan untuk Umar di LANGKAH MANUAL |
| 3 | **P0** | Plan hanya meminta `SHOO_TEST_DB_URL`; `SHOO_TEST_ADMIN_DB_URL` yang tidak di-set jatuh ke DB dev (`backend/api/vitest.config.ts:8`) dan `resetDb` menghapus `blocklist_entries` + `ops_jobs` di sana (`backend/api/test/helpers/resetDb.ts:29-32`). (Ronde 3: `SHOO_TEST_DB_URL` yang tidak di-set juga jatuh ke sana lewat `:6`, dan `resetDb` menghapus 10 tabel `public`, `resetDb.ts:21-28`) | Plan (metode, aturan langkah kerja, setiap langkah merah backend, Verifikasi, DoD, Risiko) dan log: kedua variabel wajib + guard `db_guard` (berhenti kalau tidak di-set, kosong, tidak di-export, atau memuat `54322`) |
| 4 | P1 | Bukti U-06 ukuran default (bagian yang membuat P2) tidak ada di repo | Screenshot `qa/img/fase-28/U-06_se-default-extension-steps-hidden.jpg` (SE, EN, ukuran default; data mock) dikutip pertama di plan, matriks, log |
| 5 | P1 | Nilai terekam UI P1 / P2 dan putusan reviewer hanya ada di luar repo | 14 pohon `log/fase-28-repro/h4-tree-*.json.txt` (dicek tanpa email, nomor telepon, token, id perangkat nyata); file ini; rujukan plan diarahkan ke repo |
| 6 | P2 | Nilai confidence yang tidak didefinisikan ("pohon terekam", "screenshot") | Legenda baru "verified (run, rekam saja: tanpa asersi)" + "+ screenshot"; semua baris UI memakainya |
| 7 | P2 | Q7 menanyakan ulang hal yang sudah diputuskan #325 dan memuat empat topik | Butir #325 dibuang; Q7 dipecah: Q7a (X-08 + X-07), Q7b (X-06); X-03 tetap catatan untuk #318 / #448 |
| 8 | P2 | Draf PM / desainer tanpa assignee | Setiap draf: `assignee: umarmuhdhor (lead, teruskan ke PM)` atau "ke desainer / PM"; alasannya ditulis di bawah judul bagian |
| 9 | P2 | 28n "tanpa branch" | Branch `docs/alief-fase-28n-ax3`, hanya `plan/alief/`, PR kecil, reviewer `umarmuhdhor` |
| 10 | P2 | K12 mengecek panjang pada string mentah; `href` setelah encode bisa > 2048 | K12, 28j, tabel test: panjang dicek pada `href`; test merah baru (path non-ASCII yang > 2048 setelah encode → 422) |
| 11 | P2 | K14 ikut memutuskan sebagian Q4 fase 27 | K14 hanya untuk baris tanpa verdict; baris ber-verdict menunggu Q4 fase 27; test penjaga hijau di `main`; ketergantungan ditulis di 28l dan K18 |
| 12 | P2 | Baris QA di PROGRESS sudah diisi sebelum K19 | Sel putusan: "Menunggu K19" |
| 13 | P2 | Teks UQ tanpa `having count(*) >= 5` | Ditambahkan ke UQ-01, UQ-02, UQ-05, UQ-06, UQ-12 di log; di-parse ulang 14 Nov dengan `EXPLAIN` di `shoo_f28_perf`: 14 statement OK (UQ-05 dan UQ-06 diganti ke `count(distinct …)` di ronde 2) |
| 14 | P2 | Test merah 28h lulus di `main` pada ukuran default | Test merah 28h = langkah 1 di atas footer tanpa menggulung (SE, ukuran default, EN + ID); label consent dan kolom nama ON-02 pindah ke 28n (AX3) dan K10 "kalau rusak di AX3" |
| 15 | P3 | Baris skenario rantai tanpa total | 216 / 216 / 140 / 76 |
| 16 | P3 | 4 sel `h3-fail` tanpa kata n/a | "4 n/a = sudah diketahui (BH-41)" |
| 17 | P3 | "#482 menunggu file itu" padahal #482 sudah merge | Kalimat diperbaiki |
| 18 | P3 | Verifikasi menjalankan UI test dengan batas 60 | Dua `xcodebuild`: unit 60, UI 120 |
| 19 | P3 | Branch A-15 `PR-01`; test U-14 di file yang salah | Branch `fix/GD-01-id-copy-connect` (Home Pribadi `HomeChrome.swift:656`, kartu Profile `ProfileCards.swift:95`); test U-14 di `test/settings.test.ts` (test `GET /terms`, `:357`). **Beda dari saran reviewer** (`support.test.ts`): file itu hanya memuat link ke `/terms`, test halamannya ada di `settings.test.ts` |
| 20 | P3 | Q16 dua PRD ID; Q22 dua topik | Q16 PRD `-` (app, cakupan D-alief-A12); Q22 dipecah: Q22a (U-16), Q22b (kata "weekly review", A-15) |
| 21 | P3 | Path lokal dengan nama folder home di log | "`.claude/worktrees/fase-28-hunt` di checkout lokal" |
| 22 | P3 | OPT yang punya branch tidak tercatat di fixbug | Tabel kedua di ronde Fase 28 `fixbug.md`: OPT-02 + OPT-06 (P2), OPT-01, OPT-10 |
| 23 | P3 | Keputusan B-06 menunjuk tempat yang salah | `.max(2048)` sudah ada; perbaikan = `linkParam` fatal saat > 2048, atau refine objek hanya jalan bila `url instanceof URL` |

Jumlah draf pertanyaan setelah ronde ini: 37 (Q1 sampai Q35; Q7 dan Q22 masing-masing dipecah dua). Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.

## Review plan ronde 2 (14 Nov 2026)

Satu reviewer independen membaca ulang plan, matriks, log, file ini, baris tracker, dan header file repro di `9e5403ba`, baca saja. Hasil ronde 1: **22 diperbaiki, 1 sebagian (#3), 0 tidak**. Cacat baru: **14**: P1 4, P2 4, P3 6. Setiap klaim dicek ulang terhadap file dan baris yang dikutip (`backend/api/vitest.config.ts:6,8,30`, `backend/api/test/helpers/resetDb.ts:20-33,40-46`, `DetailFooter.swift:98-113`, `DetailStyle.swift:32`, `GuardianHomeModel.swift:289-305`, `backend/api/test/scans.test.ts:177,217,247`, `docs/mandates/alief.md:35,37,63-64`, root `CLAUDE.md` aturan 4) sebelum diperbaiki. **Diperbaiki: 15 (sisa #3 + 14 baru). Dilewati: 0.**

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| R1-#3 sisa | **P0** (dari ronde 1) | Guard DB dev belum menghentikan run di dua tempat: resep backend log (guard di baris sendiri) dan header run 7 file repro (tanpa guard, `env.sh` di folder sesi) | Lihat N1, N2. `db_guard` sekarang **satu definisi** di [`fase-28.md`](fase-28.md) §Cara menunjuk vitest ke DB terpisah; plan (Metode, Langkah kerja, setiap langkah merah / hijau backend 28j, 28k, 28l, 28m, 28o, Verifikasi, DoD, Risiko) merujuk ke sana; definisi kedua di plan → Verifikasi dibuang |
| N1 | **P1** | Resep backend log menjalankan `cp` + `vitest` di baris terpisah setelah `db_guard` | Satu perintah berantai `cd backend/api && db_guard && cp … && { npx vitest run …; rm …; }`. Aturan pakai ditulis di bawah definisi guard: tidak pernah `cp` atau `vitest` di baris terpisah. Perintah matriks h1 di log juga dirantai |
| N2 | **P1** | Header run `h1-concurrency`, `h1-extra`, `h1-identity`, `h1-matrix`, `h1-truth`, `h2-poison`, `h3-chain` memakai `source <scratchpad>/hunt/env.sh` tanpa guard | Header saja: `db_guard && npx vitest run …` + satu baris rujukan ke log §Cara menunjuk vitest ke DB terpisah. Isi test tidak diubah |
| N3 | **P1** | Test merah 28g (frame "Reasons detected" vs frame pertanyaan) tidak bisa hijau dengan K9: footer overlay, frame tetap bertumpuk | Test baru `ios/ShooApp/Tests/DetailFooterTests.swift`: `DetailFooter` di-render `ImageRenderer` di atas latar hitam; piksel di kolom padding kiri pada y 28 pt (tepi atas pertanyaan) = `DetailStyle.footer` alfa 1,0. Merah di `main` (gradien baru 0,96 pada 30 % tinggi footer), hijau setelah K9. Diubah di K9, tabel test, langkah 28g, Verifikasi (`-only-testing:ShooAppTests/DetailFooterTests`), baris `h4-check` di log, baris U-17 di `fixbug.md` |
| N4 | **P1** | Perbaikan kolom nama ON-02 masuk branch ON-04 (aturan 4) | Sub-fase sendiri **28p** `fix/ON-02-name-field-at-ax` (hanya kalau 28n menemukannya rusak di AX3, setelah 28h merge). Diubah di tabel Branch / Prasyarat / Urutan / Requirement, K10, tabel test 28h, 28h, 28n, Peta dampak, log §Hasil 28n, `fixbug.md`, `PROGRESS.md`, `README.md` (28a–28p) |
| N5 | P2 | Ringkasan matriks: "A-01 6" | "A-01 3, pertanyaan Q16 3 (Detail, Profile, Member detail)", sama dengan matriks §4.2 dan §8 |
| N6 | P2 | Hitungan grade ronde 1 "P1 3, P3 8" | "P1 2, P3 9" di plan → Riwayat dan file ini |
| N7 | P2 | `db_guard` mengecek variabel shell, bukan yang di-export | Guard membaca `printenv "$n"`: variabel tanpa `export` dianggap kosong |
| N8 | P3 | U-09 dilabel PR-03 | PR-01 (Connect lewat Scan QR, mandat `:63`); branch `fix/PR-01-connect-scan-note` di plan dan `fixbug.md`; Requirement plan dan README ditambah PR-01, ON-02 |
| N9 | P2 | UQ-05 dan UQ-06 menghitung kelompok minimum dalam push / device-hari, bukan device | `having count(distinct p.to_device_id) >= 5` (UQ-05) dan `having count(distinct to_device_id) >= 5` (UQ-06). EXPLAIN OK menurut reviewer ronde 2; penulis perbaikan tidak menjalankan DB |
| N10 | P3 | `scans.test.ts:176` basi | `:217` (repeat visit) dan `:247` (skor lebih tinggi) di 28l dan Risiko |
| N11 | P3 | "belum di-parse ulang", "Dua perubahan" basi | "di-parse ulang 14 Nov dengan `EXPLAIN` di `shoo_f28_perf`: 14 statement OK"; "Tiga perubahan" (+ `having`) |
| N12 | P3 | "dicetak '< 5'" padahal `having` membuang baris | "kelompok dengan kurang dari 5 device tidak dicetak (`having`); laporan menulis 'kelompok < 5 disembunyikan'" di plan dan tabel log; UQ-03 (tanpa `group by`) tetap "ditulis '< 5' saat dilaporkan" |
| N13 | P3 | Daftar "Merah" 28i dan 28k memuat test yang hijau di `main` | 28i: merah (a), (d), penjaga (b), (c). 28k: merah (b), penjaga (a) |
| N14 | P3 | PR-C-01 menyebut branch produk sebelum persetujuan | "→ Q35; branch hanya setelah Alief setuju dan Q35 dijawab" |

Tambahan saat memperbaiki (bukan dari reviewer):

- `h4-pages.test.ts.txt` memanggil `resetDb` tetapi tidak punya baris run: header ditambah `cd backend/api && db_guard && npx vitest run test/h4-pages.test.ts` + rujukan yang sama. Isi test tidak diubah.
- `h5-explain-summary.out.txt` merujuk folder sesi untuk plan EXPLAIN lengkap: diganti "not kept in the repo".
- Baris `withoutTriggers` di log: `:40-46` (sebelumnya `:39-45`).

Dicek setelah perbaikan: severity baris plan milik Alief P1 2 / P2 6 / P3 26 = baris `fixbug.md` (34 baris bug + 3 optimasi); 37 draf pertanyaan (Q1 sampai Q35, Q7 dan Q22 dipecah) sama di plan, README, PROGRESS, matriks, file ini; 142 link relatif di plan, matriks, log, file ini, `fixbug.md`, PROGRESS, README ada (`test -e`); tidak ada path folder sesi yang dibutuhkan pembaca; tidak ada kredensial, token, atau email nyata; setiap `vitest` di dokumen dan header repro dirantai di belakang `db_guard` atau prosa (juga `h5-route-bench`, header `:6-8`). Sisa yang tidak diubah saat itu: label matriks Connect dan Protected Home (diperbaiki di ronde 3, D6 dan D7), tanda pisah panjang di baris lama `fixbug.md` / PROGRESS / README di luar fase 28 dan di teks hunter dalam `fase-28-repro/` (ronde 3: semua diganti kecuali satu string data seed).

Jumlah draf pertanyaan setelah ronde ini: tetap 37. Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.

## Review plan ronde 3 (14 Nov 2026)

Satu reviewer independen membaca ulang plan, matriks, log, file ini, baris tracker, dan semua file `fase-28-repro/` di `9e5403ba` (= `origin/main` setelah `git fetch`), baca saja. Hasil ronde 2: **15 dari 15 diperbaiki**, tanpa regresi. Cacat baru: **14**: P1 1, P2 4, P3 9. Setiap klaim dicek ulang terhadap kode di `HEAD` sebelum diperbaiki (`ActivityView.swift:452-455,484-486,525-529`, `MainTabView.swift:121`, `Tests/ActivityModelTests.swift:336-346`, `GuardianHomeView.swift:117`, `AppEnvironment.swift:602,608`, `Tests/PushTests.swift:176-194`, `backend/api/vitest.config.ts:6,8`, `backend/api/test/helpers/resetDb.ts:21-32`, `ConnectView.swift:4,499-512`, `ProtectedShieldView.swift:3`, `docs/mandates/alief.md:40,62-64`, `.github/ISSUE_TEMPLATE/question.yml`, `h5-proto.sql.txt:30`; status git checkout utama untuk dua file BH). **Diperbaiki: 14. Dilewati: 0.**

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| D1 | **P1** | Test merah 28f (UITest "teks baris memuat akhir domain") tidak bisa merah di `main`: baris = satu elemen aksesibilitas dengan label `pageTitle` penuh (`ActivityView.swift:484-486`). Risiko menurunkan U-05 ke P3 kalau test tidak merah | Tabel test baris 28f: unit pemecahan judul (`titleParts` atau sejenis) di `Tests/ActivityModelTests.swift`, di sebelah test `pageTitle` (`:336-346`), bukan file baru; merah di `main` karena `pageTitle` menggabung domain + path dalam satu `Text` yang dipotong di ekor. 28f langkah 1 dan 2, K8, `fixbug.md` U-05, log U-05. Risiko: keputusan turun ke P3 berdasar **screenshot SE ukuran default** dengan domain terdaftar panjang, bukan merah atau tidaknya test |
| D2 | P2 | `log/bughunt-2026-11-12.md` dan `log/states-audit-2026-11-12.md` tidak ada di repo (untracked di checkout utama), jadi dedupe "sudah diketahui: BH-xx" tidak bisa dicek | **Beda dari saran reviewer** (menyalin baris BH ke file ini): file BH tidak disalin. Setiap baris "sudah diketahui" yang menunjuk BH memuat isi BH itu dalam satu kalimat: plan A-17 (BH-31), §Fail-wrong BH-41, BH-06, BH-43, ringkasan matriks h3 (BH-41); matriks §1 h3, §4 A-17, §5 BH-41 dan BH-06, §12. Langkah 28f "Cek BH-13" juga memuat isinya. Plan §Bacaan wajib: kedua file lokal, tidak di-commit |
| D3 | P2 | Urutan menaruh 28h sebelum 28n, padahal U-08 di 28h butuh hasil 28n | Urutan: 28n langsung setelah 28a / 28b dan harus merge sebelum 28h; Prasyarat 28h ditambah hasil 28n |
| D4 | P2 | 28m A-12 "test model per layar" tanpa seam: hanya view modifier `GuardianHomeView.swift:117` yang membaca `pushesWhileOpen` | Kolom keputusan + test: (a) pindahkan pengamatan ke model tiap layar, test model di `ShieldModelTests`, `ActivityModelTests`, `MemberDetailModelTests` dengan pola `PushTests.swift:176-183`, atau (b) UITest per layar dengan hook `-debug` baru; pilihan ditulis di PR. **Koreksi kecil pada saran reviewer:** `PushTests` adalah test unit env, bukan UITest dengan hook `-debug` |
| D5 | P2 | "yang **kosong** jatuh ke 54322" salah (`??` hanya untuk yang tidak di-set), dan cakupan hapus terlalu kecil | Plan Metode, aturan Langkah kerja, komentar Verifikasi, Risiko; log §Cara menunjuk vitest; file ini ronde 1 #3: "tidak di-set"; `SHOO_TEST_DB_URL` (`vitest.config.ts:6`) → 10 tabel `public` (`push_log`, `verdicts`, `scans`, `join_attempts`, `family_codes`, `family_links`, `ops_heartbeat`, `rate_limit_hits`, `storage_tombstones`, `devices`; `resetDb.ts:21-28`); `SHOO_TEST_ADMIN_DB_URL` (`:8`) → `blocklist_entries` + `ops_jobs` (`:29-32`). String kosong yang di-export: koneksi gagal, guard tetap menolak |
| D6 | P3 | Connect dilabel "GD-04 / PR-03" | Matriks §7.1 "Connect (PR-01 / PR-02)"; §7.4 ringkasan, judul §7.7 Pairing, plan ringkasan UI: "Pairing: Connect + deep link (PR-01, PR-02, PR-03)". **Tambahan dari grep:** baris harapan Pairing di matriks §7.6 (`PRD GD-04, PR-03` → `PR-01, PR-02, PR-03`) |
| D7 | P3 | "Protected Home (PR-01)" | Matriks §7.1, §7.4, judul §7.7: "Protected Home (PR-04)". **Tambahan dari grep:** baris harapan Home di matriks §7.6 (`PRD GD-01, PR-01` → `GD-01, PR-04`) |
| D8 | P3 | OPT-10 di branch PR-01, padahal satu-satunya pemakai `ConnectedBackground` = layar PR-02 (`ConnectView.swift:512`) | Branch `fix/PR-02-connected-background-size` di plan dan `fixbug.md` (Area PR-02); Requirement plan dan README: "PR-01/02/03/04". Nama branch lain yang memakai ID ini dicek: `fix/PR-01-connect-scan-note`, `fix/PR-01-rate-limit-copy` (Connect), `fix/PR-03-join-page-polish` (link undangan), `fix/PR-04-shield-stale-notice` benar; `fix/GD-04-member-id-nul-404` tetap (daftar terhubung = GD-04, mandat `:62`) |
| D9 | P3 | 28o "Merah" = test kesetaraan yang hijau di `main`; aturan 28m "setiap butir TDD" padahal H5-01 dan OPT-10 tanpa test | 28o langkah 1 = **Penjaga** (hijau di `main`, tetap hijau), tanpa test merah, bukti di langkah 3. 28m: "setiap butir bug"; H5-01 dan OPT-10 tanpa test merah |
| D10 | P3 | File ini basi: hanya menyebut ronde 1; `h5-route-bench` "mengisi variabel inline"; daftar sisa tidak lengkap | Pembuka file; kalimat cek ronde 2 (`h5-route-bench` header `:6-8` memakai `db_guard`; label Connect / Protected Home diperbaiki di ronde ini) |
| D11 | P3 | Verifikasi tidak menjalankan semua suite tujuan test | Backend + `test/scans-thresholds.test.ts`; app + `ActivityModelTests`, `FormatterTests`, `ProfileModelTests`, `PageCopyTests`, `MemberDetailModelTests`, `PushTests` (A-08, A-15, 28f, A-12) |
| D12 | P3 | Q25 judul `ADM-07` vs PRD `-`; Q31 dua PRD ID di judul | Q25 PRD `ADM-07` (ID dipakai di `backend/README.md:140,234`); Q31 judul "GD-01: …", PR-04 disebut di Context |
| D13 | P3 | Label P4 di `h5-explain-summary.out.txt` memuat error shell (backtick di label hunter) | Label dikembalikan dari `h5-proto.sql.txt:30`, dengan catatan bahwa run hunter mencetak error shell di situ. Angka tidak diubah |
| D14 | P3 | Blok `db_guard` ditempel ke zsh interaktif tanpa `interactivecomments`: komentar inline menjadi kata, error di setiap panggilan | Catatan zsh di atas blok (`setopt interactivecomments` dulu, atau tempel tanpa komentar); komentar inline dipindah ke baris sendiri di atas blok. Pesan guard: "tidak di-set / kosong / tidak di-export / DB dev (54322)" |

**`db_guard` diuji dengan nilai palsu** (URL `postgres://u:p@127.0.0.1:<port>/x`, tanpa DB, tanpa vitest), setiap kasus di subshell sendiri, di bash 5.3 dan zsh. Reviewer menguji blok lama; penulis perbaikan menguji ulang blok baru (fungsi diambil dari log, `env -i`, `bash --norc --noprofile` dan `zsh -f`). Hasil sama di kedua shell dan kedua blok:

| Kasus | Return |
|---|---|
| kedua variabel tidak di-set | 1 |
| salah satu tidak di-set (admin, lalu api) | 1 |
| salah satu di-set tanpa `export` (admin, lalu api) | 1 |
| api di-export sebagai string kosong | 1 |
| salah satu memuat `54322` (api, lalu admin) | 1 |
| keduanya di-export, port 54522 | **0** |
| `db_guard && echo RAN` dengan env salah | pesan ke stderr, `RAN` tidak tercetak |

Tambahan saat memperbaiki (bukan dari reviewer): tanda pisah panjang di teks hunter `fase-28-repro/` diganti ": " (komentar MARK `h2-H2TruthTests` 8, label `h5-explain.sql` 2 dan `h5-explain-summary` 2 dengan teks yang sama, nama test `h1-matrix` 3 dan `h1-identity` 1; tidak ada dokumen yang mengutip teks itu). Satu baris sisa: `h5-seed.sql.txt:101` (dua string data seed, en + id), tidak diubah supaya seed sama dengan yang diukur.

Dicek setelah perbaikan: severity baris plan milik Alief P1 2 / P2 6 / P3 26 = baris bug `fixbug.md` (34) + 3 baris optimasi, setiap ID sekali di kedua tabel, ID bug sama; 37 draf (Q1 sampai Q35, Q7 dan Q22 dipecah), setiap Q sekali, angka 37 sama di plan, README, PROGRESS, file ini, dan matriks (Q1 sampai Q35, Q7 dan Q22 dipecah); 143 link relatif ada (`os.path.exists`); tidak ada path folder sesi yang dibutuhkan pembaca (hanya placeholder `<scratch>` / `<scratchpad>` di teks riwayat); 0 tanda pisah panjang di plan, matriks, log, file ini, dan baris tracker baru; setiap `vitest run` dirantai di belakang `db_guard` atau prosa; tidak ada kredensial, token, atau email nyata (hanya `Bearer shoo_…` buatan di test matriks, `*@toko.example`, `a@b.c`); `git status --short` hanya `plan/alief/`.

Jumlah draf pertanyaan setelah ronde ini: tetap 37. Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.

## Review plan ronde 4 (14 Nov 2026)

Satu reviewer independen membaca ulang plan, matriks, log, file ini, baris tracker, dan semua file `fase-28-repro/` di `9e5403ba` (= `origin/main` setelah `git fetch`), baca saja. Hasil ronde 3: **13 diperbaiki, 1 sebagian** (D1: sisa di tabel repro log, menjadi N3). Cacat baru: **10**: P0 0, P1 1, P2 2, P3 7. Setiap klaim dicek ulang di `HEAD` sebelum diperbaiki (`DetailView.swift:258,444-451`, `DetailHeader.swift:117-119,127`, `git show 8ca9647c:…/DetailHeader.swift` `:124` `.truncationMode(.middle)`, `8645d7b0` leluhur `HEAD`, `ActivityView.swift:484-486`, `backend/api/vitest.config.ts:12-22`, `test/scans.test.ts:62,393`, baris BH-06 dan BH-26 di file BH lokal, log `:93`). **Diperbaiki: 10. Dilewati: 0.**

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| N1 | **P1** | X-08 menulis "Detail masih menampilkan host + path (`DetailView.swift:258`)". Di `HEAD` pill Detail = domain terdaftar + path (`shownLink`, `DetailView.swift:444-451`, `8645d7b0`): `sites.google.com/view/x` tampil `google.com/view/x` | Plan X-08 dan file ini (tabel r3 X-08): kalimat diganti; host bersama tidak terlihat di layar mana pun, hanya "Salin link" menyalin link penuh. Q7a Context ditambah fakta itu; "Until answered" menyebut pill Detail juga. Grep plan, matriks, log, `fixbug.md`, PROGRESS, README untuk "Detail menampilkan host" / pill Detail: tempat lain hanya U-05 dan 28f langkah 2 (N2). **Severity dan langkah tidak berubah:** X-08 tetap putusan r3 (P2 kalau dikonfirmasi, menunggu Q7a); fakta ini memperberat konteks, bukan putusan. Tidak ada langkah kerja yang bergantung pada Detail menampilkan host |
| N2 | P2 | BH-13 ditulis masih bisa terbuka (U-05 "perbaiki bersama"; 28f langkah 2 "Cek BH-13 … kalau masih terbuka") padahal sudah diperbaiki sebelum `HEAD` | Plan §Sudah diketahui: paragraf baru **Sudah diperbaiki di `main`**: BH-13, bukti `8645d7b0` (12 Nov), `DetailHeader.swift:117-119` (`.tail`, dipakai `:127`), `DetailView.swift:444-451`. U-05: "BH-13 (pill Detail) sudah diperbaiki di `main`; baris Activity belum". 28f langkah 2: cek BH-13 dan PR `fix/DT-01-…` dihapus; catatan bahwa K8 boleh memakai pola pill (`.tail` pada teks yang dimulai domain terdaftar) kalau screenshot SE menunjukkan domain tetap utuh. File ini r2 U-05: catatan "sudah diperbaiki". **Hitungan:** "7 sudah diketahui" (PROGRESS) tetap 7: BH-13 bukan temuan fase 28 dan ditulis di luar tabel |
| N3 | P2 | Tabel repro log baris `h4-Fase28MatrixUITests` masih memindah `test046_act_g_edge`, `test114_member_edge_long` ke `UITests/QALayoutUITests.swift` (sisa D1) | "tidak dipindah sebagai UITest (label aksesibilitas = judul penuh); dasar skenario mock untuk screenshot SE 28f; test merah 28f = unit `ActivityRow.titleParts` di `ios/ShooApp/Tests/ActivityModelTests.swift`" |
| N4 | P3 | "DB dev di port 54322 tidak disentuh" tidak mencakup Storage: `vitest.config.ts:12-22` memakai Storage stack dev kecuali `SHOO_TEST_SUPABASE_URL` + `_KEY` di-set; `scans.test.ts` mengunggah objek uji | Plan Metode: klausa Storage (menambah objek, tidak menghapus data dev). Log: paragraf "Di luar cakupan guard: Storage" di §Cara menunjuk vitest; baris "DB yang tidak disentuh" = tabel DB dev + catatan Storage |
| N5 | P3 | 28n tidak menyebut apakah ON-04 diukur sebelum atau sesudah PR #484 | 28n langkah 1: ukur di atas `main` setelah #484 merge; kalau belum, catat SHA dan ukur ulang di 28h langkah 1 |
| N6 | P3 | Q13 dan Q7b menyebut BH-26 / BH-06 tanpa isi (file BH tidak di repo) | Isi satu kalimat ditambahkan, dicek terhadap file BH lokal. **Tambahan dari grep:** baris X-06 (lapor saja) juga menulis "(BH-06)" tanpa isi: ditambah "lihat §Fail-wrong" (isi BH-06 ada di sana) |
| N7 | P3 | Rujukan "pola yang sama dengan Q32 di draf sebelumnya" tidak jelas; Q25 dua tanda kurung | Rujukan Q32 dihapus; Q25 "assignee: `umarmuhdhor` (lead, teruskan ke PM atau pemilik rencana dashboard)" |
| N8 | P3 | Metode dan kedua baris `xcodebuild test` di Verifikasi tidak memakai `-parallel-testing-enabled NO` (log `:93` memakainya) | Ditambahkan di Metode dan kedua perintah |
| N9 | P3 | "Satu sisa: string data seed" = dua string di satu baris; label S08 / S26 di `h5-explain-summary.out.txt` diubah tanpa catatan di file | File ini ronde 3: "Satu baris sisa: `h5-seed.sql.txt:101` (dua string data seed, en + id)". Ringkasan: baris header kedua `[S08 and S26 labels: dash changed to ':' in review round 3; values unchanged]` (tidak ada rujukan nomor baris ke file itu) |
| N10 | P3 | U-12 "P3" padahal K16 dan 28n memperlakukannya seperti U-03 / U-04 / U-07 | Plan U-12 Sev "P3 di AX5; **P2 kalau muncul di AX3**"; `fixbug.md` U-12 Prio "P3 (P2 kalau muncul di AX3)". Hitungan dasar tetap P3 (sama seperti U-03 / U-04 / U-07) |

**Cek tanda pisah panjang (ronde 3).** Reviewer membandingkan ke-16 penggantian dengan salinan asli hunter (`/usr/bin/diff`, bukan `rtk diff` yang salah melaporkan "identical") dan object file `H2TruthTests.o` yang dibangun dari sumber sebelum diganti: semua 16 ada di label `\echo` psql, komentar `// MARK:`, judul `it(...)` / `describe(...)`, atau label ringkasan. Tidak ada yang berada di string data, regex, nilai yang diharapkan, seed, atau asersi; 64 string dimensi `h1-matrix` di JSON hunter masih ada persis di sumber. **Tidak ada satu pun dari 16 penggantian yang mengubah perilaku repro.** `h5-seed.sql.txt:101` tetap (identik dengan seed yang diukur).

**`db_guard`** diuji ulang reviewer dengan nilai palsu di `env -i bash` dan `env -i zsh`: hasil sama dengan tabel ronde 3 (hanya "keduanya di-export, 54522" = 0; guard tidak terdefinisi = 127, `RAN` tidak tercetak).

Dicek setelah perbaikan: severity baris plan milik Alief P1 2 / P2 6 / P3 26 (34 baris) = baris bug `fixbug.md` (34) + 3 baris optimasi (P2 1, P3 2), setiap ID sekali di kedua tabel, ID bug sama; 37 draf (Q1 sampai Q35, Q7 dan Q22 dipecah), setiap Q sekali, angka 37 sama di plan, README, PROGRESS, file ini, dan matriks; 144 link relatif ada (`os.path.exists`); tidak ada path folder sesi; 0 tanda pisah panjang di plan, log, file ini; setiap `npx vitest run` dirantai di belakang `db_guard` (sebutan baru `vitest.config.ts` = prosa); tidak ada kredensial, token, atau email nyata di file yang diubah; `git status --short` hanya `plan/alief/`.

Jumlah draf pertanyaan setelah ronde ini: tetap 37. Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.

## Review plan ronde 5 (14 Nov 2026)

Satu reviewer independen membaca ulang plan, matriks, log, file ini, baris tracker, dan semua file `fase-28-repro/` di `9e5403ba` (= `origin/main` setelah `git fetch`), baca saja; `gh` baca saja (PR #484 masih terbuka). Hasil ronde 4: **10 dari 10 diperbaiki**, tanpa regresi. Cacat baru: **8**: P0 0, P1 1, P2 5, P3 2. Setiap klaim dicek ulang di `HEAD` sebelum diperbaiki: matriks `home-g-verdict-failed` (A FAIL, F FAIL, D / E / B pass), `connect-scan-tab` (A FAIL, F pass), `sheet-safeReason-kb` (A FAIL, E / B pass), `on-ext` (A pass, E pass [a]), konfigurasi §7.3; pohon `h4-tree-A-home-g-verdict-failed` (`home.verdictError` y 817,3 h 64; `Bar Tab` y 791, tombol tab y 795), `h4-tree-A-connect-scan-tab`, `h4-tree-A-sheet-safeReason-kb` (keyboard y 546, tombol y 557), `h4-tree-E-on-ext`; `QALayoutUITests.swift:11-12` (helper = AX3 + EN); `cron/notifications.ts:36-38,44,49-56,135`; `ActivityView.swift:452-455,525-529`; `DetailHeader.swift:117-119`; `DetailModel.swift:152-153,255,268`; `gh issue view 448 / 449 / 450 / 454` (semua terbuka, 12 Nov, assignee `umarmuhdhor`). **Diperbaiki: 8. Dilewati: 0.**

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| R5-01 | **P1** | Test merah 28e ditulis merah di "iPhone 17 dan SE". Di `main` merah hanya di iPhone 17, ID, ukuran default (A); SE dan Pro Max ukuran default lulus (E, B). Helper `launch` memakai AX3 + EN, ukuran dan bahasa yang tidak pernah diukur untuk U-02 | 28e langkah 1: merah = iPhone 17, ID, `UICTContentSizeCategoryL`, dengan sel A, pohon, dan screenshot; method penjaga = SE, EN, ukuran default (E pass; B pass); `XCTSkipUnless` lebar jendela; helper diberi parameter `language`. Tabel test baris 28e dan baris U-02 (pemicu "iPhone 17, ID") ikut. EN di iPhone 17 belum direkam: tidak dipakai sebagai merah |
| R5-02 | P2 | §Verifikasi menjalankan semua UI test di satu `$SIM_ID`; separuh test tidak bisa merah atau hijau untuk alasannya | `SIM_17` + `SIM_SE`; perintah UI dijalankan sekali per simulator (loop), daftar test per perangkat di komentar, test satu perangkat memakai `XCTSkipUnless`, PR menulis perangkat tempat test merah. DoD: hijau di perangkat tempat test itu merah |
| R5-03 | P2 | U-09 dan U-11 tanpa perangkat, bahasa, ukuran | U-09: iPhone 17, ID, ukuran default (A FAIL; tidak ada penjaga ukuran default, F = AX5). U-11: iPhone 17, ID, ukuran default (A FAIL), penjaga SE EN (E pass). Baris temuan U-11 ditambah "ID" |
| R5-04 | P2 | 28k (b) "hook" tidak punya seam di `main` (`weeklySummaries` tidak di-export; opsi hanya `sender`, `now`, `ops`); opsi baru diabaikan, jadi test merah karena alasan yang salah | 28k langkah 1 (b): `sql` dibungkus `Proxy` (apply trap) yang melempar pada statement klaim ringkasan (`summary_sent_on = v.day`); tanpa opsi baru; test menangkap penolakan lalu menegaskan push off terkirim. Merah di `main` karena lemparan di `:44` sebelum loop kirim `:49-56`. Tabel test baris 28k ikut |
| R5-05 | P2 | 28f langkah 2 mengizinkan "pola pill" (`.tail` setelah domain) = perilaku `main` hari ini, bertentangan dengan K8 | Kalimat diganti: kalau screenshot SE menunjukkan domain utuh dengan pola `main`, ikuti Risiko (U-05 turun ke P3 dengan persetujuan Alief, 28f ditutup tanpa kode); kalau terpotong, K8 |
| R5-06 | P2 | BH-06 / BH-41 / BH-43 ditulis "file lokal" padahal ada di issue publik terbuka #449, #454 E, #454 G; Q7b dan Q7a tidak menautkan #450 dan #448 | Plan: Bacaan wajib (catatan + daftar issue), X-06, §Fail-wrong 3 baris, ringkasan matriks, K12, Q7b (`= #449`; terkait #450, jawab bersama atau komentar di #450), Q7a (terkait #448). Matriks `:38,217,221,739`: nomor issue di samping BH |
| R5-07 | P3 | Bacaan wajib menyebut "ronde 1"; Riwayat verifikasi tanpa ronde 4 | "ronde 1 sampai 5"; baris riwayat ronde 4 dan ronde 5 ditambahkan. Pembuka file ini: "ronde 1 sampai ronde 5" |
| R5-08 | P3 | K5 "muat ulang scan" lewat `load()` di dalam `catch` tetap merah: `isSubmittingVerdict` masih true, `load()` menyalin verdict lokal (nil) | K5: muat ulang dengan `repository.scan(id:)` dan pakai verdict-nya langsung, bukan `load()` (`DetailModel.swift:152-153,255`) |

**Sapuan supaya kelas cacat R5-01 / R5-03 / R5-04 tidak kembali** (dari brief penulis perbaikan, bukan dari reviewer):

- **Aturan baru di §Langkah kerja.** Setiap test merah UI menyebut perangkat, bahasa, ukuran teks; konfigurasi itu harus gagal di matriks, penjaga harus lulus; konfigurasi tanpa sel (AX3, SE + ID default, domain terdaftar panjang) disebut terang, direkam dulu dengan nama screenshot di langkahnya, dan hanya menjadi merah kalau rekaman itu rusak. Helper yang memaksa nilai lain dicatat: `QALayoutUITests.launch` (AX3 + EN), `GuardianUITests.launch` (EN, `:14`), `DetailUITests.openDetail` (EN tanpa `language:`).
- **Aturan seam.** Simbol yang belum ada di `main` ditambahkan di langkah merah dengan perilaku `main`; merah karena gagal kompilasi, skip, atau test tidak jalan tidak dihitung. Seam per langkah: 28a `GuardianHomeModel.refreshFailed` + `extensionChecked`; 28b `ShieldModel.refreshFailed`; 28f `ActivityRow.titleParts`; 28k `Proxy` di test (tanpa kode produk); 28m A-03 jenis error, A-12 method model atau hook `-debug`, U-18 `WaitButton.label` (`private struct`, `ConnectView.swift:271`).
- **Test merah UI per langkah setelah sapuan:**

| Langkah | Merah (konfigurasi gagal di `main`) | Penjaga (lulus di `main`) | Bukti |
|---|---|---|---|
| 28a UITest | iPhone 17, ID, default (A FAIL); SE, ID, default: tanpa sel (F = AX5 FAIL), tetap merah karena cabang logika; screenshot SE direkam saat merah | tidak ada (cabang salah di semua ukuran) | `h4-tree-A-home-g-loading`, `U-01_guardian-home-loading-says-protected.jpg` |
| 28e | iPhone 17, ID, default (A FAIL) | SE, EN, default (E pass; B pass). Dikoreksi ronde 6: E lulus dari pohon (pesan berakhir y 312,5 < tab bar y 584); B **merah** oleh asersi `maxY <= tabBar.minY + 1` (881,3 lawan 873), bukan penjaga | `h4-tree-A-home-g-verdict-failed`, `U-02_…jpg` |
| 28g | unit, lebar tetap 375 pt, `.large` (tidak bergantung simulator) | - | `h4-tree-E-dt-g-blocked`, `U-17_…jpg` |
| 28h | SE, EN, default (E [a]); SE, ID, default: tanpa sel, hanya kalau screenshot langkah 1 tertutup | iPhone 17, ID, default (A pass; B pass) | `h4-tree-E-on-ext`, `U-06_se-default-extension-steps-hidden.jpg`, screenshot langkah 1 |
| 28h U-08, 28n branch, 28p | AX3, ID, perangkat dari §Hasil 28n: tanpa sel AX3 (hanya F / D AX5) | sel sama di default (A pass; E pass). Dikoreksi ronde 6: U-08 A dan 28p A / E dicek dari pohon; 28n: rekam dulu di `main` | screenshot `28n_<ID>_<se\|17>-ax3-id.jpg` |
| 28m U-09 | iPhone 17, ID, default (A FAIL) | tidak ada di default (F = AX5) | `h4-tree-A-connect-scan-tab`, `U-09_…jpg` |
| 28m U-11 | iPhone 17, ID, default (A FAIL); keyboard di layar ditegaskan dulu | SE, EN, default (E pass; B pass). Dikoreksi ronde 6: sel E tidak sah (pohon: tombol di bawah keyboard; screenshot tanpa keyboard), SE EN direkam ulang dulu; tanpa penjaga di iPhone 17 / SE | `h4-tree-A-sheet-safeReason-kb`, `U-11_…jpg` |
| 28m A-12 (b) | iPhone 17, ID, default; tanpa sel (baca kode) | - | screenshot direkam saat merah |
| 28m U-13 | viewport 320 px; vitest menghitung lebar baris kode dari CSS (308 > 272 px) | - | `U-13_join-page-320-code-row.png` |

**Masalah baru yang terlihat saat menyapu** (diperbaiki di plan, bukan dari reviewer): (1) U-11 di simulator dengan keyboard perangkat keras tidak menampilkan keyboard, jadi test "tombol di atas keyboard" hijau tanpa arti; test sekarang menegaskan `app.keyboards.firstMatch` dulu (pola `PairingUITests.swift:207`). (2) U-13 "lebar digit" di `join-page.test.ts`: vitest tidak punya mesin tata letak; test sekarang menghitung dari nilai CSS (`join-page.ts:90,111-113`). (3) U-18 `WaitButton` adalah `private struct`: test tidak bisa membacanya tanpa seam. (4) Untuk 28e dan U-11 merah (ID, iPhone 17) dan penjaga (EN, SE) berbeda bahasa karena matriks hanya merekam itu: dua method, masing-masing dengan `XCTSkipUnless`.

Dicek setelah perbaikan: severity baris plan milik Alief P1 2 / P2 6 / P3 26 (34 baris) = baris bug `fixbug.md` (34) + 3 baris optimasi, setiap ID sekali, ID bug sama; 37 draf (Q1 sampai Q35, Q7 dan Q22 dipecah), setiap Q sekali, angka 37 sama di plan, README, PROGRESS, dan file ini; 146 link relatif ada (`os.path.exists`); tidak ada path folder sesi; 0 tanda pisah panjang di plan, matriks, log, file ini, dan baris tracker baru; setiap `npx vitest run` dirantai di belakang `db_guard` (log `:137` = lanjutan `&&` dari `:135`) atau prosa; tidak ada kredensial, token, atau email nyata di file yang diubah; `git status --short` hanya `plan/alief/`.

Jumlah draf pertanyaan setelah ronde ini: tetap 37 (Q7a dan Q7b mendapat tautan ke #448 / #450, bukan draf baru). Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.

## Review plan ronde 6 (14 Nov 2026)

Satu reviewer independen membaca ulang plan, matriks, log, file ini, baris tracker, dan pohon mentah hunter 4 untuk kelima konfigurasi (A, F, D, E, B) di `9e5403ba`, baca saja. Hasil ronde 5: **8 dari 8 diterapkan**, tetapi dua perbaikan membawa kesalahan fakta baru: penjaga diambil dari tanda `pass` matriks tanpa membuka pohonnya (U-11 SE EN dari R5-03, 28e Pro Max EN dari R5-01). Cacat baru: **8**: P0 0, P1 1, P2 3, P3 4. Setiap klaim dicek ulang sebelum diperbaiki: pohon `E/sheet-safeReason-kb` (tombol y 497,5 sampai 553,5; `Keyboard` y 451; input view y 407) dan screenshot-nya (sheet diam, tanpa keyboard); `dump()` mengambil screenshot sebelum pohon (`h4-Fase28MatrixUITests.swift.txt:68-72`); pohon `B/` dan `D/home-g-verdict-failed`; pohon `A/sheet-safeReason-kb` (`Keyboard` tipe 19 y 590, baris saran y 546); `ios/ShooApp/Tests/PairingTests.swift:137-157`; `ConnectView.swift:271-282` (`label(seconds:)` mengembalikan `Text`); `L10n.swift:9` (`string(_: String.LocalizationValue, language:)`); `AppEnvironment.swift:182-222` (`#if DEBUG`); `cron/notifications.ts:136-153` (berhenti sebelum klaim tanpa Guardian jatuh tempo). **Diperbaiki: 8. Dilewati: 0.**

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| R6-01 | **P1** | Penjaga U-11 "SE, EN, ukuran default (sel E pass)" tidak hijau di `main`: pohon E menunjukkan tombol di bawah keyboard, screenshot E tanpa keyboard (dua saat berbeda); pembuat matriks hanya memberi U-11 di konfigurasi A (`h4-gen-matrix.py.txt:53`), walau skrip cek menandai E `UNDERKB` (dikoreksi ronde 7) | Plan §28m U-11: tanpa penjaga di iPhone 17 / SE ukuran default; sel E tidak sah; SE EN direkam ulang dulu (`qa/img/fase-28/U-11_se-default-en-before.jpg`) dan menjadi method merah kedua kalau tertutup; B lulus (594,3 < 609) tetapi tidak dijalankan. Baris temuan U-11, komentar §Verifikasi, `fixbug.md` U-11, matriks `sheet-safeReason-kb` E = `pass [f]` + catatan [f], log blok U-11 |
| R6-02 | P2 | 28e "Pro Max EN default, B, juga pass": di bawah asersi `maxY <= tabBar.minY + 1` B merah 8,3 pt (pesan berakhir y 881,3, tab bar y 873); D (AX5) merah 23,3 pt walau matriks menulis pass | 28e langkah 1: B bukan penjaga, D disebut; matriks `home-g-verdict-failed` D dan B = `pass [g]` + catatan [g]; baris 28e ronde 5 di file ini diberi koreksi; [g] = negatif palsu skrip (aturan memakai tombol, bukan pesan; dikoreksi ronde 7) |
| R6-03 | P2 | Dua test merah tidak dijalankan di §Verifikasi: U-18 tanpa file test, A-12 (b) tanpa kelas UITest | U-18 di `Tests/PairingTests.swift` (sebelah test `signUpLimit`); A-12 (b) di `UITests/ProtectedUITests.swift` + `GuardianUITests.swift`; §Verifikasi: `-only-testing:ShooAppTests/PairingTests` dan `-only-testing:ShooAppUITests/ProtectedUITests` (dihapus kalau A-12 memilih (a)) |
| R6-04 | P2 | 28k (b) tanpa prasyarat fixture: tanpa Guardian jatuh tempo `weeklySummaries` berhenti sebelum klaim, trap tidak melempar, (b) hijau di `main` | Fixture (Senin 08:00 lokal, Guardian `weekly_summary` + `apns_token`, di luar quiet hours, `summary_sent_on` kosong, satu anggota syarat push off) + asersi penghitung trap = 1 dulu |
| R6-05 | P3 | Bukti merah U-11 "keyboard mulai y 546", padahal `app.keyboards.firstMatch` mulai y 590 (546 = baris saran) | U-11: tombol y 557,3 sampai 613,3; keyboard y 590, baris saran y 546; asersi memakai `min(keyboard.minY, SystemInputAssistantView.minY)` |
| R6-06 | P3 | Seam U-18 tidak menyebut keluaran yang bisa dibaca: `label(seconds:)` sudah statis tetapi mengembalikan `Text` | Fungsi statis `internal` di luar `WaitButton` yang mengembalikan `String.LocalizationValue`, dibaca lewat `L10n.string(…, language:)`, EN + ID |
| R6-07 | P3 | Hook `-debug` baru A-12 (b) tanpa tempat | `-debug.pushWhileOpen` di blok `#if DEBUG` `AppEnvironment.swift:182-222` (tidak ikut build Release) |
| R6-08 | P3 | `SIM_17` / `SIM_SE` tidak pernah di-set; `\|\| break` melewatkan SE kalau iPhone 17 gagal | §Verifikasi: kedua UDID dari `xcrun simctl list devices` per nama (pola `Shoo F28 (` supaya tidak cocok dengan `Shoo F28 SE` / `Max`), cek tidak kosong, unit run hanya kalau `SIM_17` ada, loop UI selalu menjalankan kedua perangkat dan mencetak perangkat yang gagal. Bendera `-test-timeouts-enabled YES -maximum-test-execution-time-allowance` (60 unit, 120 UI seperti §Metode) dan `-only-testing:` tetap. Diuji kering dengan `bash -n`, `zsh -n`, dan keluaran `simctl` palsu |

**Sapuan supaya kelas cacat R6-01 / R6-02 tidak kembali** (dari brief penulis perbaikan, bukan dari reviewer): akar keduanya = penjaga diklaim dari tanda `pass` matriks, padahal skrip cek punya positif palsu dan negatif palsu. Aturan §Langkah kerja diganti: penjaga harus lulus menurut koordinat pohon atau screenshot, angka penentu ditulis di sebelahnya; tanpa bukti itu "rekam dulu di `main`"; konfigurasi merah juga dengan angka. Sepuluh pohon penjaga / koreksi disalin byte sama ke `log/fase-28-repro/` (24 pohon sekarang) dan dua screenshot ke `qa/img/fase-28/`, supaya pembaca bisa mengecek tanpa folder sesi.

| Langkah | Merah (angka pohon `main`) | Penjaga (angka pohon `main`) | Hasil sapuan |
|---|---|---|---|
| 28a UITest | A: `home.family.protected` ada di y 308,3 sampai 342 saat memuat | tidak ada | SE ukuran default tanpa sel: rekam dulu (sudah tertulis) |
| 28e | A: pesan y 817,3 sampai 881,3, tab bar y 791 (90,3 pt) | E: pesan berakhir y 312,5 < tab bar y 584 | B dibuang sebagai penjaga (881,3 lawan 873); D merah oleh asersi (814,3 lawan 791) |
| 28h | E: langkah 1 berakhir y 494, consent y 463,5 (30,5 pt) | A: langkah 1 berakhir y 494,7 < consent y 636,7 | B lulus (494 < 718,7), tidak dijalankan |
| 28h U-08 | AX3: tanpa sel, screenshot 28n | A: `consent.allow` y 679,3 sampai 735,3 (satu baris), `consent.decline` y 739,3 sampai 783,3, label utuh di screenshot | SE ukuran default tanpa sel `consent-question`: bukan penjaga sampai direkam |
| 28m U-09 | A: catatan berakhir y 819,7, "Nanti saja" mulai y 802 (17,7 pt) | tidak ada | tidak berubah |
| 28m U-11 | A: tombol y 557,3 sampai 613,3; keyboard y 590, baris saran y 546 | tidak ada | E dibuang (sel tidak sah), SE EN rekam ulang dulu; B lulus (594,3 < 609), tidak dijalankan |
| 28n branch | AX3: tanpa sel, screenshot 28n | rekam dulu di `main` (U-03, U-04, U-07, U-12) | penjaga umum "sel default yang pass di matriks" dibuang; `dt-g-blocked` E / B, `dt-g-edge-long` A / E / B, `dt-verdict-failed` A / B = FAIL U-17, dan cek frame isi lawan footer tidak bisa menjadi penjaga U-07 |
| 28p | AX3: tanpa sel (F AX5: kolom y 625,5 di bawah tombol y 575,5) | A: kolom berakhir y 519,3 < tombol y 750; E: kolom berakhir y 471 < tombol y 577 | dikonfirmasi |

**Masalah baru yang terlihat saat menyapu:** (1) Log U-02 menulis "tab bar di y 795 sampai 849": itu tombol tab, bar mulai y 791; diperbaiki. (2) Penjaga umum 28n akan memakai sel Detail yang sebenarnya FAIL U-17 di ukuran default; sekarang "rekam dulu". (3) `Shoo F28` adalah awalan nama dua simulator lain; pola awk di §Verifikasi memakai `Shoo F28 (`.

Dicek setelah perbaikan: severity tidak berubah, `fixbug.md` ronde Fase 28 = 34 baris bug (P1 2, P2 6, P3 26) + 3 baris optimasi (P2 1, P3 2), setiap ID sekali, sama dengan baris plan milik Alief; 37 draf (37 butir Q unik), angka 37 sama di plan, README, PROGRESS, dan file ini; 162 link relatif ada (`os.path.exists`); path kode baru di plan ada atau berupa rekaman yang akan dibuat (`U-11_se-default-en-before.jpg`); tidak ada path folder sesi (hanya placeholder lama `<scratchpad>` di teks riwayat); setiap `npx vitest run` dirantai di belakang `db_guard` (log `:137` = lanjutan `&&`) atau prosa; 0 kredensial, token, atau email di file yang diubah dan di 10 pohon baru; `git status --short` hanya `plan/alief/`.

Jumlah draf pertanyaan setelah ronde ini: tetap 37. Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.

## Review plan ronde 7 (14 Nov 2026)

Satu reviewer independen membaca ulang plan, matriks, log, file ini, baris tracker, dan pohon `log/fase-28-repro/` di `9e5403ba`, baca saja; skrip cek hunter 4 dijalankan pada salinan pohon. Hasil ronde 6: **8 dari 8 diterapkan**, dua dengan penjelasan salah (bukan penjaga salah): catatan [g] dan kalimat "skrip cek tidak menandainya" untuk U-11 E. 11 dari 11 angka penentu di plan sama dengan pohon. Cacat baru: **6**: P0 0, P1 0, P2 4, P3 2. Setiap klaim dicek ulang sebelum diperbaiki: `h4-gen-matrix.py.txt:33-36` (U-02 = bawah tombol `state.notice.action` lawan atas tombol tab Perisai / Shield), `:53` (U-11 hanya kalau `t=='A'`), `h4-check.py.txt:45-47` (UNDERKB); pohon D (`state.notice.action` berakhir y 689,3, Perisai y 795, `home.verdictError` berakhir y 814,3, `Bar Tab` y 791), B (tombol 871,3, Shield 877, pesan 881,3, `Tab Bar` 873), E `sheet-safeReason-kb` (tombol y 497,5 h 56 di dalam `Keyboard` y 451 h 216); matriks `dt-fail` / `dt-gone` A, E, B pass, `member-fail` / `member-gone` A pass. Label "sel D ukuran default" hanya ada di catatan pengamatan reviewer, tidak di file: D = iPhone 17 · ID · AX5 di plan dan [g]. **Diperbaiki: 6. Dilewati: 0.**

| No | Grade | Cacat | Yang diperbaiki |
|---|---|---|---|
| R7-01 | P2 | Catatan [g] matriks: D dan B "dihitung pass dari mata". Tandanya dari skrip pembuat matriks, yang membandingkan tombol "Coba lagi" dengan tombol tab, bukan seluruh pesan dengan `Tab Bar` (negatif palsu skrip) | Matriks [g]: negatif palsu skrip dengan aturan `h4-gen-matrix.py.txt:33-36` dan angka D (689,3 < 795) / B (871,3 < 877); baris R6-02 di file ini diberi koreksi |
| R7-02 | P2 | Log U-11 dan baris R6-01: "skrip cek tidak menandainya" salah. `h4-check.py` menandai E `UNDERKB safeReason.submit`; pembuat matriks memberi U-11 hanya di A (`:53`) dan tidak membaca hasil cek | Log blok U-11, baris R6-01 di file ini, catatan [f] matriks |
| R7-03 | P2 | 28n langkah 3: asersi merah U-07 tidak ditulis; cek frame isi lawan footer merah sebelum dan sesudah perbaikan (isi memang di belakang footer overlay, 28g) | Asersi U-07 ditulis (Detail: judul di atas tepi atas footer pada posisi awal; halaman gagal / hilang: tombol tidak menimpa judul, penjelasan di layar atau tercapai dengan gulungan); calon penjaga ukuran default `dt-fail` / `dt-gone` A dan E (tidak kena U-17), rekam dulu |
| R7-04 | P2 | §Metode "`xcodebuild` tidak berhenti sendiri" lawan loop dua perangkat yang butuh setiap run keluar | §Metode dan log §Aturan run: bendera batas waktu membatasi tiap test, bukan proses; satu run (F) tidak berhenti dan diakhiri manual. §Verifikasi: kalau tidak keluar setelah `** TEST SUCCEEDED **` / `** TEST FAILED **`, `kill <pid>` dari terminal lain (bukan Ctrl-C), loop lanjut ke perangkat kedua, hasil dibaca dari baris itu |
| R7-05 | P3 | Blok §Verifikasi di zsh interaktif tanpa `interactivecomments`: baris `#` menjadi perintah, komentar sebaris di `bundle-size` membatalkan baris itu; hasil unit tidak dicetak | Baris pertama `[ -n "$ZSH_VERSION" ] && setopt interactivecomments`; komentar `bundle-size` pindah ke barisnya sendiri; `UNIT=gagal; … && UNIT=hijau` dan `echo "Unit: $UNIT"`. Dicek: `bash -n`, `zsh -n`, dan `zsh -f -i` dengan `PATH` kosong di folder kosong: 0 galat parse, 0 file dibuat, `Unit:` dan baris UI tercetak |
| R7-06 | P3 | Baris U-02: "tab bar (y 795 sampai 849)" = tombol tab; "terlihat di … Pro Max ukuran default" tanpa 8,3 pt | Baris U-02: `Bar Tab` mulai y 791, tombol tab y 795 sampai 849; Pro Max ukuran default terbaca tetapi frame berakhir 8,3 pt di bawah tepi atas tab bar (28e) |

Dicek setelah perbaikan: severity tidak berubah; `fixbug.md` ronde Fase 28 = 34 baris (31 baris bug: P1 2, P2 6, P3 23; 3 baris optimasi), setiap ID sekali, severity tiap ID sama dengan baris plan; 37 draf, angka 37 sama di plan, README, PROGRESS, dan file ini; 166 link relatif di plan, matriks, log, file ini, `fixbug.md`, README, PROGRESS ada (`os.path.exists`); tidak ada path folder sesi; setiap `npx vitest run` dirantai di belakang `db_guard` (log `:137` = lanjutan `&&`) atau prosa; 0 kredensial, token, atau email di file yang diubah; `git status --short` hanya `plan/alief/`.

**Aturan berhenti terpenuhi:** ronde 7 = ronde pertama dengan 0 P0 dan 0 P1 di plan.

### Ringkasan tujuh ronde review plan

| Ronde | Cacat | P0 | P1 | P2 | P3 | Diperbaiki |
|---|---|---|---|---|---|---|
| 1 | 23 | 1 | 2 | 11 | 9 | 22 + 1 sebagian (#3 guard DB dev, selesai ronde 2) |
| 2 | 14 | 0 | 4 | 4 | 6 | 14 |
| 3 | 14 | 0 | 1 | 4 | 9 | 13 + 1 sebagian (D1, selesai ronde 4 sebagai N3) |
| 4 | 10 | 0 | 1 | 2 | 7 | 10 |
| 5 | 8 | 0 | 1 | 5 | 2 | 8 (dua membawa fakta baru yang salah, dikoreksi ronde 6) |
| 6 | 8 | 0 | 1 | 3 | 4 | 8 (dua dengan penjelasan salah, dikoreksi ronde 7) |
| 7 | 6 | 0 | 0 | 4 | 2 | 6 (belum dibaca ulang reviewer) |
| **Jumlah** | **83** | **1** | **10** | **33** | **39** | **83** |

Jumlah draf pertanyaan setelah ronde ini: tetap 37. Severity temuan tidak berubah: P0 0, P1 2, P2 6 milik Alief + 1 performa.
