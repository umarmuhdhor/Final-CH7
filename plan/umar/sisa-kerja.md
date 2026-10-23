# Plan sisa kerja — Umar (lead) + Imelda (Team AI)

> Dibuat 23 Okt 2026, setelah PR #71 (mandat Imelda M3–M7 dicentang).
> Sumber: `docs/mandates/umar.md`, `docs/mandates/imelda.md`, `plan/imelda/TODO.md`, `plan/imelda/log/fase-08.md`, issue terbuka #37, #38, #40, #55, PR #69.
> Kode Imelda M1–M7 sudah merge semua. Yang tersisa: langkah manual (akun, deploy, secret), keputusan lead, data eval, dan tes di iPhone.

## 1. Gambaran

21 item, dibagi 6 gelombang. Satu gelombang bisa mulai kalau syaratnya terpenuhi, bukan menunggu gelombang sebelumnya selesai semua.

| Gelombang | Isi | Syarat mulai | Siapa |
|---|---|---|---|
| G0 | Keputusan lead + perbaikan kecil extension | Tidak ada | Umar |
| G1 | Deploy `/analyze` + `/public-blocklist`, pasang URL | Akun Cloudflare | Umar → Alief |
| G2 | Layer 4 (LLM) dinyalakan | G0 (A7), G1, model dipilih | Imelda |
| G3 | Data scam nyata, kalibrasi ulang, sumber blocklist | G0 (target M6) | Imelda |
| G4 | Tes di iPhone + TestFlight | Build tim berbayar, hasil spike Alief | Umar, Alief, Imelda |
| G5 | CI, PM, antrean blocklist | Tidak ada (bisa paralel) | Umar (+ Alief) |

Jalur kritis: **G1 deploy → URL di app (Alief) → tes end-to-end di iPhone (G4)**. G2 dan G3 hanya menaikkan akurasi, tidak memblokir MVP berjalan (layer 1–3 sudah jalan tanpa LLM).

Aturan yang berlaku di semua langkah:
- Semua pertanyaan/keputusan antar orang lewat **GitHub issue** (template Question / proposal), bukan chat (CLAUDE.md aturan 7).
- Satu branch = satu PRD ID, PR kecil.
- `ios/ShooApp/` milik Alief, `detector/` + `ai/` + `plan/imelda/` milik Imelda. Umar tidak mengedit di sana; cukup buka issue.

---

## 2. G0 · Keputusan lead + perbaikan kecil (Umar, mulai sekarang)

Pertanyaan Imelda di `plan/imelda/TODO.md` masih terbuka. Jawab di issue, lalu Imelda mencentang TODO-nya.

| # | Item | Usulan jawaban | Hasil | Branch / issue |
|---|---|---|---|---|
| U-1 | **Target eval M6** belum tercapai (scam ≥ 50: 66%, ≥ 80: 32%; scam nyata hanya 1) | Target **tidak diturunkan**. M6 tetap `[~]` sampai ada ≥ 20 scam nyata berlisensi; MVP boleh rilis dengan catatan risiko | Issue `AI-M6: target eval vs data scam nyata`, assign Imelda | issue |
| U-2 | **A7** sinyal layer 4 tanpa `evidence` | Boleh (kontrak: `evidence` opsional). Extension sudah melewati sinyal tanpa evidence di stabilo; label tetap tampil | Satu issue "aturan evidence" untuk A7 + C7 + C9 + C10 | issue |
| U-3 | **C7** `asks_*` evidence = nama field | Sudah ditangani: `marks.js` tidak men-stabilo `asks_*`, semua teks lewat `textContent` | sama dengan U-2 | — |
| U-4 | **C9** `new_domain` evidence = umur (angka) | Perbaiki di extension: stabilo hanya untuk sinyal teks (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`), bukan semua layer ≥ 3. Sekarang `phrasesFrom` di `marks.js` akan men-stabilo angka ≥ 3 digit | PR kecil + test | `fix/EX-05-text-evidence-only` |
| U-5 | **C10** `brand_logo_offsite` evidence dari `imageAlts`/title | Abaikan: kalau teks tidak ada di body, tidak ada stabilo; alasan tetap tampil di pill/detail | sama dengan U-2 | — |
| U-6 | **C1** form di dalam iframe tidak tertangkap | MVP: `capture.js` juga membaca form di iframe **same-origin** (`iframe.contentDocument`), tanpa `all_frames` (pipeline/pill tidak boleh jalan per frame). Iframe cross-origin → Fase 2. Test dengan fixture mirip `lphone-login` | Spike dulu, lalu PR | `feat/EX-02-iframe-forms` |
| U-7 | **C8** tambah `accept` di `PageSnapshot.forms[].fields` | Setuju, aditif. PR `contracts/` + `capture.js` mengisi `accept`. Prioritas rendah | PR kontrak | `feat/EX-02-field-accept` |
| U-8 | **C3** verifikasi `bankbsi.co.id`, `jet.co.id`, `bpjsketenagakerjaan.go.id` di `brands.json` | Cek manual di situs resmi, jawab di issue | issue | issue |
| U-9 | **C6** bobot awal layer 3–4 | Sudah lewat (M6 merged, ambang 30/50/80 tidak berubah) → tutup | Imelda mencentang | — |

**Selesai kalau:** semua TODO C1, C3, C6–C10, A7 di `plan/imelda/TODO.md` punya jawaban di issue; PR U-4 merged.

---

## 3. G1 · Deploy + pasang URL (Umar, lalu Alief)

Checklist lengkap ada di `plan/imelda/log/fase-08.md` § Langkah manual. Urutan:

| # | Langkah | Selesai kalau |
|---|---|---|
| D-1 | Login/buat akun Cloudflare. Mulai Free untuk uji; naik ke Workers Paid sebelum pengguna sungguhan (Free = CPU 10 ms per request) | Akun aktif |
| D-2 | `cd ai && npm ci && npx wrangler login` | `wrangler whoami` menampilkan akun |
| D-3 | Cek `namespace_id` di `ai/wrangler.toml` (`1001`, `1002`) belum dipakai Worker lain | Tidak bentrok |
| D-4 | `npm run deploy` → `https://shoo-ai.<akun>.workers.dev` | Deploy sukses |
| D-5 | `node ai/scripts/smoke.mjs <URL> 30` + cek CORS (fase-08) | Semua `ok`, p95 `/analyze` < 8 s |
| D-6 | Catat URL + keluaran smoke test di `plan/imelda/log/fase-08.md` (lewat PR, atau minta Imelda), centang M7 di `docs/mandates/imelda.md` | PR merged |
| D-7 | **`aiBaseURL` ada di `ios/ShooApp/App/AppConfig.swift` (milik Alief), sekarang `nil`.** Buka issue ke Alief: isi URL dari D-4 untuk build release (dan debug kalau mau) | Issue dijawab, PR Alief merged |
| D-8 | Kirim URL ke Imelda dan Alief lewat issue (TODO C4) | Issue ditutup |

Catatan: layer 4 tetap mati sampai G2. Daftar publik tetap kosong sampai G3 (A3).

---

## 4. G2 · Nyalakan layer 4 / LLM (Imelda)

| # | Langkah | Selesai kalau |
|---|---|---|
| L-1 | **A2 + A6** pilih model cepat dari penyedia yang **zero data retention / tanpa training**. Catat model + kebijakan di `plan/imelda/log/DECISIONS.md` | Keputusan tercatat |
| L-2 | **A5** konfirmasi gerbang LLM (form ≥ 1 field dan skor ≥ 15; situs resmi tidak memanggil) | Dikonfirmasi |
| L-3 | Pasang **batas biaya** di dashboard penyedia (`LLM_DAILY_CAP` hanya per isolate) | Spend limit aktif |
| L-4 | `npx wrangler secret put LLM_API_KEY / LLM_MODEL / LLM_BASE_URL` (diketik di prompt, tidak ke file) | Secret terpasang |
| L-5 | Jalankan eval M2 dengan LLM nyata. Bandingkan dengan tanpa LLM | Salah blokir di situs resmi turun, deteksi scam tidak turun → centang M4 |
| L-6 | **C5** issue ke Alief + Umar: data form dikirim ke penyedia LLM → kebijakan privasi + label App Store diperbarui di rilis yang sama | Issue dijawab |

Syarat: U-2 (A7) dijawab, D-4 selesai.

---

## 5. G3 · Data + kalibrasi + sumber blocklist (Imelda)

| # | Langkah | Selesai kalau |
|---|---|---|
| E-1 | **A4/D1** kumpulkan scam nyata berlisensi (laporan publik yang boleh dipakai, atau izin tertulis). Hanya lewat `capture.mjs`, data pribadi disamarkan | ≥ 20 scam nyata di eval set (angka dari U-1) |
| E-2 | Kalibrasi ulang bobot (M6) dengan data baru | Target scam ≥ 50 ≥ 90%, ≥ 80 ≥ 70%, situs resmi < 30, atau laporan angka ke Umar |
| E-3 | **A3** pilih sumber daftar phishing publik yang lisensinya boleh dipakai di app, catat di `ai/README.md`, ganti `emptySource` | `/public-blocklist` mengembalikan daftar nyata; centang M5-A |
| E-4 | Daftar pra-bangun (membangun 200.000 entri ±1 s CPU, tidak muat di Free) | Build daftar di luar request |
| E-5 | Perbarui `plan/imelda/PROGRESS.md` (fase 01–08 masih `[~]`/`[m]` padahal sudah merge) | PROGRESS sama dengan `main` |

---

## 6. G4 · Tes di iPhone + TestFlight

| # | Siapa | Langkah | Syarat |
|---|---|---|---|
| T-1 | Alief | Spike 01S di iPhone (#40): isi angka heartbeat, Off, pencabutan izin, `openExtensionsSettings` | Akses tim Apple (#32, #55) |
| T-2 | Umar | Set `AppGroup.extensionActiveWindow` dari hasil T-1 (PR `ios/ShooShared/`) | T-1 |
| T-3 | Umar | **C17** setujui/tolak `SFSafariExtensionManager` (iOS 26.2+) di #40 | T-1 |
| T-4 | Alief | `ExtensionStatus` baca `extension.allSites == false` → Off | — |
| T-5 | Umar | **U7 · EX-01** tes izin "Allow on every website" + pencabutan → app Off (checklist `docs/spikes/extension-status.md`), centang U7 | T-4, build di iPhone |
| T-6 | Imelda | **D3** uji detector + `/analyze` di Safari iPhone sungguhan | D-7, build |
| T-7 | Umar + Alief | **#55** TestFlight: undang Alief ke tim, kunci APNs (B7), App Store Connect (B8), build pertama | Tim berbayar |
| T-8 | Umar | Uji 5 definisi sukses MVP Umar di iPhone (skor bertahap, server mati, It's safe membuka blokir, input tidak terkirim) | T-5, D-7 |

---

## 7. G5 · Infra, PM, rutin (Umar, paralel)

| # | Langkah | Selesai kalau |
|---|---|---|
| P-1 | Review + merge PR #69 (Alief, docs C2) | Merged |
| P-2 | **C2** pindahkan draf CI Alief ke `.github/workflows/` + 5 secret repo (#38) | CI hijau di PR berikutnya |
| P-3 | Pertanyaan terbuka PM di `docs/README.md` (scope MVP vs Fase 2) | Jawaban tercatat di issue |
| P-4 | Video tutorial ON-04 ≤ 60 s, EN + ID, MP4 H.264 (#37) | Video diterima Alief |
| P-5 | **C6** review antrean blocklist bareng Alief (SQL editor) | Jadwal berkala disepakati |
| P-6 | Hapus branch yang sudah merge (`docs/AI-mandate-ticks`, `feat/AI-M*`) | Tidak ada branch basi |
| Rutin | Review/merge PR harian, `detector/scripts/sync-to-extension.sh` tiap `detector/` merge, kontrak hanya lewat PR `contracts/` | — |

---

## 8. Urutan kerja yang disarankan untuk Umar

1. G0 sekarang: buka 4 issue (U-1, U-2/3/5, U-6, U-8), kerjakan PR U-4.
2. G1 D-1 … D-8 (butuh kamu login Cloudflare).
3. P-1, P-2 sambil menunggu Alief/Imelda.
4. U-6 spike iframe, lalu U-7 kalau sempat.
5. G4 begitu build tim berbayar bisa dipasang di iPhone.

Yang bisa dikerjakan agent tanpa kamu: U-4, U-6, U-7, D-6 (setelah kamu kirim URL + output smoke test), draf semua issue, P-2 (tanpa mengisi secret).
Yang harus kamu sendiri: login Cloudflare + deploy, mengisi secret, tes di iPhone, keputusan U-1 … U-8, menghubungi PM.
