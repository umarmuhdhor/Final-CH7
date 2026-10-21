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
| U6 | EX-03 | Indikator live | Dynamic Island atau pill in-page sesuai hasil S3 | S3 |
| U7 | EX-01 | Izin semua situs | Izin dicabut → app tampil Off | S1 (Alief) |
| L1 | — | Tugas lead | Review PR, ubah kontrak, sinkron `detector.js`, jawab PM | — |

## Tugas

### Minggu 1 · Setup & spike
S1 (deteksi On/Off) dan S2 (buka pengaturan extension) dikerjakan Alief di iPhone-nya sendiri — lihat `alief.md`.
- [ ] **L0** Override signing per developer: bundle ID prefix + App Group + Team ID dari file lokal yang di-gitignore (mis. `ios/Local.xcconfig` + `Local.xcconfig.example`). Prioritas: Alief butuh ini untuk S1/S2. Cek juga apakah App Group butuh akun developer berbayar.
- [ ] Setelah S1 masuk: set `AppGroup.extensionActiveWindow` sesuai usulan Alief.
- [ ] **S3** Dynamic Island dari extension → isi `docs/spikes/dynamic-island.md`. Coba jalur A → B → C, kalau semua gagal: pill in-page. Kabari Alief kalau jalur push dipilih (butuh endpoint tambahan).

### Extension · bisa mulai tanpa device (pakai fixtures + mock)
- [ ] **U1 · EX-02** Pipeline scan. Branch: `feat/EX-02-scan-pipeline`
  - `registrableDomain` pakai Public Suffix List (`a.b.co.id` → `b.co.id`).
  - Ambil sesi lewat `getSession` (cache di background). Belum onboarding → tetap scan lokal, tanpa kirim apa pun.
  - Verdict domain dulu: `safe` → skor 0, berhenti. `not_safe` → blocked 100.
  - Layer 1–2 (`ShooDetector.analyzeLocal`) → update skor → `POST /analyze` (timeout 8 s) → gabung sinyal → update skor.
  - `db_match` → 100, lewati layer lain. Reset skor di setiap perubahan URL; buang hasil scan lama yang datang terlambat.
- [ ] **U2 · EX-04** Popup warning. Branch: `feat/EX-04-popup-warning`
  - Muncul di 30 dan 50, masing-masing maks. sekali per halaman. Langsung ≥80 → tanpa popup.
  - Isi: status, skor, link, "See detail" → buka app (`shoo://scan/{id}`). Bisa ditutup.
  - Shadow DOM supaya CSS halaman tidak bocor. Teks EN + ID (`_locales`).
- [ ] **U3 · EX-05** Tandai bagian berbahaya. Branch: `feat/EX-05-highlight`
  - Teks mencurigakan: stabilo tebal. Form PIN/OTP/kartu/KTP: dicoret + "Don't enter your PIN here", input tetap bisa diketik.
  - Protected: tidak bisa dihapus. Guardian: bisa ditutup.
  - Butuh posisi bukti dari sinyal → kalau Signal belum punya field itu, usulkan perubahan kontrak (opsional, aditif).
- [ ] **U4 · EX-06** Layar blokir. Branch: `feat/EX-06-block-screen`
  - Ganti seluruh halaman, tidak bisa di-bypass (tahan back/scroll/inspect di sisi user biasa).
  - "Shoo! This page is blocked" + skor + alasan.
  - Protected: "Waiting for [guardianName] to check", poll `GET /verdicts?domain=` tiap 5 s → `safe` → buka halaman.
  - Guardian: tombol "Review in Shoo" → Detail.
- [ ] **U5 · EX-07** Kirim hasil. Branch: `feat/EX-07-send-scan`
  - Skor ≥30 → `POST /scans` (ScanResult sesuai schema), sekali per halaman per status.
  - Screenshot area bukti saja, isi field di-blur. Cek dulu apakah `tabs.captureVisibleTab` jalan di Safari iOS; kalau tidak, kirim tanpa screenshot dan catat di PR.
- [ ] **U6 · EX-03** Indikator live sesuai hasil S3. Branch: `feat/EX-03-live-score`
- [ ] **U7 · EX-01** Verifikasi "Allow on every website" + pencabutan izin → app Off (dari hasil S1).
- [ ] **EX-08** (nice to have) Tap bagian yang ditandai → popup alasan singkat.

### Lead · berjalan terus
- [ ] Review & merge PR Imelda dan Alief tiap hari. Pastikan tidak ada yang edit folder tim lain.
- [ ] Ubah kontrak hanya lewat PR `contracts/` sendiri. Perubahan aditif saja kalau bisa.
- [ ] Setiap Imelda merge `detector/`, jalankan `detector/scripts/sync-to-extension.sh`.
- [ ] Tanyakan ke PM pertanyaan terbuka di `docs/README.md` (scope MVP vs Fase 2).
- [ ] Nanti: signing & Apple account per tim (ditunda).
