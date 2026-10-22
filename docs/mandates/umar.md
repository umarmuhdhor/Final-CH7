# Mandat — Umar (Lead · Safari Extension)

> Untuk: Umar (@umarmuhdhor) dan Claude-nya
> Cara pakai: di Claude Code, ketik `/mandate umar`. Claude membaca file ini, memilih tugas berikutnya yang belum dicentang, lalu mulai kerja.

## Peran
Kamu memegang **semua yang terjadi di Safari**: mengambil isi halaman, memanggil detector, menghitung skor, dan menampilkan popup / highlight / layar blokir. Kamu juga pemilik **kontrak** antar tim dan target iOS.

| Boleh diedit | Jangan disentuh (milik tim lain) |
|---|---|
| `contracts/`, `ios/project.yml`, `ios/ShooShared/`, `ios/ShooExtension/` (kecuali `Resources/detector.js`), `ios/ShooLiveActivity/`, `docs/` | `ios/ShooApp/`, `backend/` (Alief) · `detector/`, `ai/`, `Resources/detector.js` (Imelda) |

Wajib dibaca: PRD bagian 5, 8.5, 9, 10 · `contracts/*` · `ios/ShooExtension/CLAUDE.md` · `ios/ShooLiveActivity/CLAUDE.md` · `docs/spikes/`.

## Definisi sukses MVP
1. Semua **P0 EX-01 … EX-07** lolos kriteria "Selesai kalau" di PRD 8.5.
2. Skor naik bertahap per layer (1–2 di HP, lalu 3–4 dari `/analyze`), reset di setiap pindah halaman.
3. Server mati → halaman tetap terbuka, layer 1–2 tetap jalan.
4. Guardian tekan **It's safe** → layar blokir di HP orang tua terbuka sendiri.
5. Tidak ada nilai input yang diketik user yang pernah dikirim ke mana pun.

## Ringkasan

| # | PRD ID | Tugas | Selesai kalau | Bergantung pada |
|---|---|---|---|---|
| L0 | — | Override signing per developer | Alief & Imelda bisa build ke iPhone sendiri tanpa ubah `project.yml` | — |
| S3 | EX-03 | Spike: Dynamic Island | `dynamic-island.md` terisi, jalur dipilih | iPhone asli + Dynamic Island |
| U1 | EX-02 | Pipeline scan | PSL, layer 1–2 → `/analyze` → skor naik bertahap, reset per URL | Mock `/analyze` dari fixtures |
| U2 | EX-04 | Popup warning 30 / 50 | Sekali per halaman, tidak muncul kalau langsung ≥80 | U1 |
| U3 | EX-05 | Highlight + coret form | Stabilo teks, form sensitif dicoret, Guardian bisa tutup | U1, `session.mode` |
| U4 | EX-06 | Layar blokir | Tidak bisa di-bypass, auto-buka kalau verdict `safe` | U1, Alief B4 (mock dulu) |
| U5 | EX-07 | Kirim hasil | Skor ≥30 → `POST /scans` + screenshot area bukti, input di-blur | U1, Alief B3 (mock dulu) |
| U6 | EX-03 | Indikator live | Pill in-page (hasil S3: extension tidak bisa memakai Dynamic Island) | S3 ✅ |
| U7 | EX-01 | Izin semua situs | Izin dicabut → app tampil Off | S1 (Alief) |
| L1 | — | Tugas lead | Review PR, ubah kontrak, sinkron `detector.js`, jawab PM | — |

## Tugas

### Minggu 1 · Setup & spike
S1 (deteksi On/Off) dan S2 (buka pengaturan extension) dikerjakan Alief di iPhone-nya sendiri — lihat `alief.md`.
- [x] **L0** Override signing per developer: `ios/Config/Shoo.xcconfig` (default) + `Local.xcconfig` (gitignored, dari `.example`) → `DEVELOPMENT_TEAM`, `SHOO_BUNDLE_ID`, `SHOO_APP_GROUP`. `AppGroup.id` dibaca dari Info.plist `ShooAppGroup`.
- [x] Pastikan akun Apple tiap tim bisa memakai App Groups (akun gratis / Personal Team kemungkinan tidak bisa). Satu tim berbayar (Umar) untuk semua build, lihat #32. Alief perlu diundang ke tim.
- [ ] Setelah S1 masuk: set `AppGroup.extensionActiveWindow` sesuai usulan Alief.
- [x] **S3** Dynamic Island dari extension → isi `docs/spikes/dynamic-island.md`. Coba jalur A → B → C, kalau semua gagal: pill in-page. Kabari Alief kalau jalur push dipilih (butuh endpoint tambahan). Hasil (#41): A dan B gagal, C belum dites → **pill in-page** untuk U6. Jalur push tidak dipilih.

### Extension · bisa mulai tanpa device (pakai fixtures + mock)
- [x] **U1 · EX-02** Pipeline scan. Branch: `feat/EX-02-scan-pipeline`
  - `registrableDomain` pakai Public Suffix List (`a.b.co.id` → `b.co.id`).
  - Ambil sesi lewat `getSession` (cache di background). Belum onboarding → tetap scan lokal, tanpa kirim apa pun.
  - Verdict domain dulu: `safe` → skor 0, berhenti. `not_safe` → blocked 100.
  - Layer 1–2 (`ShooDetector.analyzeLocal`) → update skor → `POST /analyze` (timeout 8 s) → gabung sinyal → update skor.
  - `db_match` → 100, lewati layer lain. Reset skor di setiap perubahan URL; buang hasil scan lama yang datang terlambat.
- [x] **U2 · EX-04** Popup warning. Branch: `feat/EX-04-popup-warning`
  - Muncul di 30 dan 50, masing-masing maks. sekali per halaman. Langsung ≥80 → tanpa popup.
  - Isi: status, skor, link, "See detail" → buka app (`shoo://scan/{id}`). Bisa ditutup.
  - Shadow DOM supaya CSS halaman tidak bocor. Teks EN + ID (`_locales`).
- [x] **U3 · EX-05** Tandai bagian berbahaya. Branch: `feat/EX-05-highlight`
  - Teks mencurigakan: stabilo tebal. Form PIN/OTP/kartu/KTP: dicoret + "Don't enter your PIN here", input tetap bisa diketik.
  - Protected: tidak bisa dihapus. Guardian: bisa ditutup.
  - Butuh posisi bukti dari sinyal → kalau Signal belum punya field itu, usulkan perubahan kontrak (opsional, aditif).
- [x] **U4 · EX-06** Layar blokir. Branch: `feat/EX-06-block-screen`
  - Ganti seluruh halaman, tidak bisa di-bypass (tahan back/scroll/inspect di sisi user biasa).
  - "Shoo! This page is blocked" + skor + alasan.
  - Protected: "Waiting for [guardianName] to check", poll `GET /verdicts?domain=` tiap 5 s → `safe` → buka halaman.
  - Guardian: tombol "Review in Shoo" → Detail.
- [x] **U5 · EX-07** Kirim hasil. Branch: `feat/EX-07-send-scan`
  - Skor ≥30 → `POST /scans` (ScanResult sesuai schema), sekali per halaman per status.
  - Screenshot area bukti saja, isi field di-blur. Cek dulu apakah `tabs.captureVisibleTab` jalan di Safari iOS; kalau tidak, kirim tanpa screenshot dan catat di PR.
- [x] **U6 · EX-03** Indikator live sesuai hasil S3. Branch: `feat/EX-03-live-score`. Pill in-page, merged sebagai #43.
- [ ] **U7 · EX-01** Verifikasi "Allow on every website" + pencabutan izin → app Off (dari hasil S1). Branch: `feat/EX-01-all-sites-permission`
  - [x] Heartbeat membawa `allSites` (`browser.permissions.contains(<all_urls>)`) → App Group `extension.allSites`. Dikirim juga saat izin berubah dan tiap alarm 1 jam.
  - [ ] Alief: `ExtensionStatus` baca `extension.allSites == false` → Off.
  - [ ] Tes di iPhone (checklist di `docs/spikes/extension-status.md`).
- [ ] **EX-08** (nice to have) Tap bagian yang ditandai → popup alasan singkat.

### Lead · berjalan terus
- [ ] Review & merge PR Imelda dan Alief tiap hari. Pastikan tidak ada yang edit folder tim lain.
- [ ] Ubah kontrak hanya lewat PR `contracts/` sendiri. Perubahan aditif saja kalau bisa.
- [ ] Setiap Imelda merge `detector/`, jalankan `detector/scripts/sync-to-extension.sh`.
- [ ] Tanyakan ke PM pertanyaan terbuka di `docs/README.md` (scope MVP vs Fase 2).
- [ ] Teruskan ke PM: video tutorial ON-04 ≤ 60 detik, ramah orang tua, MP4 H.264, EN + ID (permintaan Alief C15).

### Dari review plan Alief (PR #2, 21 Okt) — semua usulan disetujui
- [x] Review PR #2 (approve) · `plan/<nama>/` masuk tabel kepemilikan `CLAUDE.md`.
- [x] Merge PR kontrak #1, #3, #4, #5, #6 (di-merge lead, 21 Okt).
- [x] Review PR `chore/APP-test-targets` dari Alief (pengecualian `project.yml` sekali saja, diff persis D-alief-24). Merged sebagai PR #8.
- [x] **C3** Tambah di `project.yml` target Shoo: `NSCameraUsageDescription` (PR-01), entitlement `aps-environment` + Push (ON-05, GD-06), `UIBackgroundModes: [audio]` (PiP video ON-04). Merged sebagai PR #27.
- [x] **C3** Pilih tim Apple berbayar untuk build iPhone + TestFlight (Push & App Groups tidak ada di Personal Team gratis). Tim Umar, ditutup di #32. Sisa: undang Alief, B7 kunci APNs, B8 App Store Connect.
- [ ] **C11** Extension mengirim `PATCH /devices/me { extensionLastSeenAt }` maks 1×/jam bersama heartbeat (setelah PR #4 merge).
- [ ] **C6** Review manual antrean blocklist berkala (bareng Alief, lewat SQL editor) setelah fase 10 backend.
- [x] Desain cara detector mendapat `/blocklist` di HP → [`docs/design/blocklist.md`](../design/blocklist.md) (PR ke Imelda).
- [x] **Layer 1 di extension:** `lists.js` di background (unduh, `storage.local`, refresh) + helper `ShooLists.match` untuk content script. Branch: `feat/EX-02-blocklist`.
- [ ] **C2** Pindahkan draf CI Alief ke `.github/workflows/` + 5 secret repo (fase 12).
- [ ] **C18** Putuskan branch protection di `main` (kalau aktif, lead juga wajib lewat PR).
- [ ] **C17** Setujui `SFSafariExtensionManager` (iOS 26.2+) kalau spike S1 Alief membuktikannya di device.
