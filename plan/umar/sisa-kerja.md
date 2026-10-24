# Plan sisa kerja — Umar (lead) + Imelda (Team AI)

> Dibuat 23 Okt 2026, setelah PR #71 (mandat Imelda M3–M7 dicentang).
> Sumber: `docs/mandates/umar.md`, `docs/mandates/imelda.md`, `plan/imelda/TODO.md`, `plan/imelda/log/fase-08.md`, issue terbuka #37, #38, #40, #55, PR #69.
> Kode Imelda M1–M7 sudah merge semua. Yang tersisa: langkah manual (akun, deploy, secret), keputusan lead, data eval, dan tes di iPhone.

## 0. Status per 24 Okt 2026

| Item | Status | Sisa / siapa |
|---|---|---|
| U-2 … U-6, U-8, U-9 | Selesai: #74, #75, #76 ditutup; U-4 = PR #78, U-6 = PR #79 merged | — |
| Worker AI produksi | Cek read-only 24 Okt: versi live `516e25b0` dari deploy 23 Okt 09:07 UTC, **sebelum** #101/#105/#106 merge. Binding hanya `ANALYZE_LIMITER` + `BLOCKLIST_LIMITER`, tanpa `BLOCKLIST_KV`; layer 4 masih batas 4 s. Smoke 5 run: semua `ok`, p95 `/analyze` 146 ms, 0 panggilan LLM (halaman smoke `.invalid` tidak lolos gerbang). `/public-blocklist` → `{"domains":[],"nextSince":null}` | Umar `npm run deploy` (bawa #101, #105, #106), lalu curl + smoke |
| U-7 (C8) | Selesai: #87, #88, #89 merged; Worker AI di-deploy ulang 23 Okt, cek live: form KTP + `capture=user` → `asks_selfie_ktp`, `capture=environment` → hanya `asks_ktp` | — |
| U-1 (#73) | Diputuskan 23 Okt, #73 ditutup: target tetap, M6 tetap `[~]` sampai 50 scam nyata berlisensi; MVP boleh rilis dengan catatan risiko | E-1 |
| D-1 … D-6 | Selesai. Smoke ulang 23 Okt sore ke `https://shoo-ai.uumaarrrrr22.workers.dev`: semua `ok`, p95 `/analyze` 28 ms (10 run) | — |
| D-7, D-8 (#82) | Selesai: PR #92 merged, #82 ditutup. Hanya build Release yang memanggil AI; build Debug tetap layer 1–2 | T-6 pakai build Release/TestFlight |
| G2 (L-1, L-4, L-5) | Selesai dengan risiko. L-1: `deepseek-v4-flash` lewat `https://bandelbanget.xyz/v1` (D-imelda-36); proxy pihak ketiga tanpa kebijakan retensi yang bisa diverifikasi, jadi syarat zero data retention belum terpenuhi. L-4: secret terpasang, layer 4 live di Worker sejak PR #95. L-5: eval (D-imelda-37) scam ≥ 50 31 → 38/50, ≥ 80 13 → 21/50, salah blokir tetap 1/53; M4 dicentang (#96). Timeout: PR #105 merged (D-imelda-39), batas layer 4 dari tenggat server 6,5 s, maks 6 s; eval ulang: timeout 47% → 29% (21 → 13 dari 45), scam ≥ 50 38 → 39/50, salah blokir tetap 1/53. Belum live (lihat baris Worker AI produksi) | PR #107 terbuka: D-imelda-05 + D-imelda-39 jadi Berlaku, centang A2/A5/A6 (A6 dengan risiko). Umar merge #107. Tinjau ulang kalau ada penyedia dengan ZDR tertulis |
| L-2 (A5) | Dikonfirmasi Umar (PR #107). Gerbang aktif di produksi (`ai/src/layer4/reality.js`: bukan situs resmi, form ≥ 1 field, `GATE_MIN_SCORE = 15`). PR #107 (DECISIONS + centang A5) dan PR #108 (komentar kode "in force") terbuka | Umar merge #107, #108 |
| L-6 (C5) | Issue #97 ke Alief dibuka, C5 dicentang (PR #98) | Alief: kebijakan privasi + label App Store menyebut penyedia, di rilis yang sama dengan layer 4 |
| E-1, E-2 | Belum mulai | Data scam nyata berlisensi; tidak bisa dibuat agent |
| E-3, E-4 | Kode selesai. PR #101 merged: sumber **Phishing.Database** (MIT mencakup data; asal upstream belum dijawab maintainer), daftar pra-bangun lewat GitHub Action `public-blocklist.yml` ke Workers KV. Perbaikan review: maks 190.000 domain, build ditolak kalau domain baru > 25%, action dikunci ke SHA. PR #106 merged: namespace KV `shoo-public-blocklist` di-bind di `ai/wrangler.toml`. PR #104 merged: `lists.js` extension membuang domain terlama saat penuh (200.000). Workflow jalan sekali (jadwal, 23 Okt 21:29 UTC) → `skipped`; repo belum punya secret maupun variable Actions | Umar: token Cloudflare (Workers KV Storage: Edit), secret `BLOCKLIST_CF_API_TOKEN` + `BLOCKLIST_CF_ACCOUNT_ID`, variable `BLOCKLIST_KV_NAMESPACE_ID`, jalankan workflow pertama kali, deploy Worker. Setelah build pertama, Worker butuh ≤ 5 menit untuk menampilkan domain |
| E-5 | Selesai (PR #84, #85) | — |
| G4 (T-1 … T-8) | Belum mulai. T-7 (#55): checklist portal Apple siap (Prompt 19), signing + bundle ID + App Group cocok di ketiga target. Upload pertama terblokir: app belum punya AppIcon (#102 terbuka, Alief, belum ada balasan) | Umar: undang Alief ke tim (membuka spike #40), kunci APNs, record App Store Connect. Alief: AppIcon (#102) |
| P-1 | Selesai: #69 dan #90 merged | — |
| P-2 (#38) | Selesai 23 Okt, #38 ditutup: 3 secret `production` terpasang (`SUPABASE_DB_URL` = Session pooler `aws-0-ap-southeast-1`, bukan host langsung yang hanya IPv6). Run 39913374469 attempt 7 hijau: migrasi "Remote database is up to date", `shoo-api` ter-deploy; live `/healthz` 200, `/healthz/db` 200 | Rotasi password DB + token Cloudflare (nilainya sempat dibagikan di chat), lalu perbarui secret dan Hyperdrive `shoo-db` |
| P-3, P-4 (#37) | Draf pesan ke PM siap (Prompt 23), ditunda Umar | Umar kirim kalau sudah siap, lalu PM |
| P-5 (C6) | PR #100 merged (runbook `plan/umar/blocklist-review.md`). Issue #99 ke Alief (jadwal + query) masih terbuka, belum ada balasan | Alief jawab #99 |
| P-6 | 28 branch remote milik Umar/Imelda yang sudah merge dihapus 23 Okt malam. Sisa remote: 22 branch Alief yang sudah merge, plus `fix/QA-E2E-00-setup` (tanpa PR, isi belum masuk `main`) | Izin Alief untuk menghapus branch-nya. Branch lokal hasil squash butuh `git branch -D` (izin Umar); `spike/EX-03-dynamic-island` hanya ada di lokal, simpan |

Langkah manual Umar yang tersisa (agent tidak boleh deploy atau menulis secret):
1. Merge #107, #108.
2. Cloudflare: token KV (Workers KV Storage: Edit). GitHub Actions: secret `BLOCKLIST_CF_API_TOKEN` + `BLOCKLIST_CF_ACCOUNT_ID`, variable `BLOCKLIST_KV_NAMESPACE_ID`. Jalankan `public-blocklist.yml` pertama kali.
3. `cd ai && npm run deploy`, lalu `curl …/public-blocklist` dan `node ai/scripts/smoke.mjs https://shoo-ai.uumaarrrrr22.workers.dev 10`.
4. Undang Alief ke tim Apple (#55), kunci APNs, record App Store Connect.

QA 23 Okt sore, `main` + PR #87–#90 digabung di worktree sementara:
- Extension `node --test ios/ShooExtension/Tests/*.test.mjs`: 145/145 lulus.
- Detector `node --test detector/test/*.test.mjs`: 38/38 lulus. `sync-to-extension.sh` tidak mengubah `detector.js` (tidak ada drift).
- AI `cd ai && node --test`: 267/267 lulus.
- Backend: CI PR #90 hijau (pgTAP, typecheck, vitest, dry-run, gitleaks). Lokal gagal hanya karena Docker mati (Supabase lokal tidak jalan).
- iOS `xcodebuild test` scheme `Shoo` di simulator iPhone 17 (perintah sama dengan `.github/workflows/ios-app.yml`): `TEST SUCCEEDED`, 51 test unit (8 dilewati) + 6 UI test, 0 gagal.

## 1. Gambaran

21 item, dibagi 6 gelombang. Satu gelombang bisa mulai kalau syaratnya terpenuhi, bukan menunggu gelombang sebelumnya selesai semua.

| Gelombang | Isi | Syarat mulai | Siapa |
|---|---|---|---|
| G0 | Keputusan lead + perbaikan kecil extension | Tidak ada | Umar |
| G1 | Deploy `/analyze` + `/public-blocklist`, pasang URL | Akun Cloudflare | Umar → Alief |
| G2 | Layer 4 (LLM) dinyalakan | G0 (A7), G1, model dipilih | Imelda - Umar |
| G3 | Data scam nyata, kalibrasi ulang, sumber blocklist | G0 (target M6) | Imelda - Umar |
| G4 | Tes di iPhone + TestFlight | Build tim berbayar, hasil spike Alief | Umar, Alief, Imelda - Umar |
| G5 | CI, PM, antrean blocklist | Tidak ada (bisa paralel) | Umar (+ Alief) |

Jalur kritis: **G1 deploy → URL di app (Alief) → tes end-to-end di iPhone (G4)**. G2 dan G3 hanya menaikkan akurasi, tidak memblokir MVP berjalan (layer 1–3 sudah jalan tanpa LLM).

Aturan yang berlaku di semua langkah:
- Semua pertanyaan/keputusan antar orang lewat **GitHub issue** (template Question / proposal), bukan chat (CLAUDE.md aturan 7).
- Satu branch = satu PRD ID, PR kecil.
- `ios/ShooApp/` milik Alief. Umar tidak mengedit di sana; cukup buka issue.
- `detector/` + `ai/` + `plan/imelda/` diambil alih Umar sejak 23 Okt 2026 (dulu milik Imelda). `ios/ShooExtension/Resources/detector.js` tetap hanya diubah lewat `detector/scripts/sync-to-extension.sh`.

---

## 2. G0 · Keputusan lead + perbaikan kecil (Umar, mulai sekarang)

Pertanyaan Imelda di `plan/imelda/TODO.md` masih terbuka. Jawab di issue, lalu Imelda mencentang TODO-nya.

| # | Item | Usulan jawaban | Hasil | Branch / issue |
|---|---|---|---|---|
| U-1 | **Target eval M6** belum tercapai (scam ≥ 50: 66%, ≥ 80: 32%; scam nyata hanya 1) | Target **tidak diturunkan**. M6 tetap `[~]` sampai eval bisa dinilai: 50 scam nyata berlisensi (`MIN_PER_CLASS` di `ai/eval/lib.mjs`), atau angka lebih kecil kalau disepakati di #73; MVP boleh rilis dengan catatan risiko | Issue dibuka, assign Imelda | #73 |
| U-2 | **A7** sinyal layer 4 tanpa `evidence` | Boleh (kontrak: `evidence` opsional). Extension sudah melewati sinyal tanpa evidence di stabilo; label tetap tampil | Satu issue "aturan evidence" untuk A7 + C7 + C9 + C10 | #74 |
| U-3 | **C7** `asks_*` evidence = nama field | Sudah ditangani: `marks.js` tidak men-stabilo `asks_*`, semua teks lewat `textContent` | sama dengan U-2 | #74 |
| U-4 | **C9** `new_domain` evidence = umur (angka) | Perbaiki di extension: stabilo hanya untuk sinyal teks (`urgent_language`, `brand_logo_offsite`, `unreasonable_request`), bukan semua layer ≥ 3. Sekarang `phrasesFrom` di `marks.js` akan men-stabilo angka ≥ 3 digit | PR kecil + test | `fix/EX-05-text-evidence-only` (#74) |
| U-5 | **C10** `brand_logo_offsite` evidence dari `imageAlts`/title | Abaikan: kalau teks tidak ada di body, tidak ada stabilo; alasan tetap tampil di pill/detail | sama dengan U-2 | #74 |
| U-6 | **C1** form di dalam iframe tidak tertangkap | MVP: `takeSnapshot` di `content.js` juga membaca form di iframe **same-origin** (`iframe.contentDocument`), tanpa `all_frames` (pipeline/pill tidak boleh jalan per frame). Iframe cross-origin → Fase 2. Test dengan fixture mirip `lphone-login` | Spike dulu, lalu PR | `feat/EX-02-iframe-forms` (#75) |
| U-7 | **C8** tambah `accept` di `PageSnapshot.forms[].fields` | Setuju, aditif. PR `contracts/` + `content.js` mengisi `accept`. Prioritas rendah | PR kontrak | `feat/EX-02-field-accept` |
| U-8 | **C3** verifikasi `bankbsi.co.id`, `jet.co.id`, `bpjsketenagakerjaan.go.id` di `brands.json` | Cek manual di situs resmi, jawab di issue | issue | #76 |
| U-9 | **C6** bobot awal layer 3–4 | Sudah lewat (M6 merged, ambang 30/50/80 tidak berubah) → tutup | Imelda mencentang | — |

**Selesai kalau:** semua TODO C1, C3, C6–C10, A7 di `plan/imelda/TODO.md` punya jawaban di issue; PR U-4 merged.

---

## 3. G1 · Deploy + pasang URL (Umar, lalu Alief)

Checklist lengkap ada di `plan/imelda/log/fase-08.md` § Langkah manual. Urutan:

| # | Langkah | Selesai kalau |
|---|---|---|
| [x] D-1 | Login/buat akun Cloudflare. Mulai Free untuk uji; naik ke Workers Paid sebelum pengguna sungguhan (Free = CPU 10 ms per request) | Akun aktif |
| [x] D-2 | `cd ai && npm ci && npx wrangler login` | `wrangler whoami` menampilkan akun |
| [x] D-3 | Cek `namespace_id` di `ai/wrangler.toml` (`1001`, `1002`) belum dipakai Worker lain | Tidak bentrok |
| [x] D-4 | `npm run deploy` → `https://shoo-ai.<akun>.workers.dev` | Deploy sukses: `https://shoo-ai.uumaarrrrr22.workers.dev` (23 Okt 2026) |
| [x] D-5 | `node ai/scripts/smoke.mjs <URL> 30` + cek CORS (fase-08) | Semua `ok`, p95 `/analyze` 171 ms |
| [x] D-6 | Catat URL + keluaran smoke test di `plan/imelda/log/fase-08.md` (lewat PR, atau minta Imelda), centang M7 di `docs/mandates/imelda.md` | Dicatat di branch `docs/AI-M7-deploy-record` |
| D-7 | **`aiBaseURL` ada di `ios/ShooApp/App/AppConfig.swift` (milik Alief), sekarang `nil`.** Buka issue ke Alief: isi URL dari D-4 untuk build release (dan debug kalau mau) | Issue dijawab, PR Alief merged. Issue #82 dibuka 23 Okt 2026 |
| D-8 | Kirim URL ke Imelda dan Alief lewat issue (TODO C4) | Issue ditutup. Alief: #82 (sama dengan D-7) |

Catatan: layer 4 tetap mati sampai G2. Daftar publik tetap kosong sampai G3 (A3).

---

## 4. G2 · Nyalakan layer 4 / LLM (Imelda - Umar)

| # | Langkah | Selesai kalau |
|---|---|---|
| L-1 | **A2 + A6** pilih model cepat dari penyedia yang **zero data retention / tanpa training**. Catat model + kebijakan di `plan/imelda/log/DECISIONS.md` | Keputusan tercatat |
| L-2 | **A5** konfirmasi gerbang LLM (form ≥ 1 field dan skor ≥ 15; situs resmi tidak memanggil) | Dikonfirmasi |
| L-4 | `npx wrangler secret put LLM_API_KEY / LLM_MODEL / LLM_BASE_URL` (diketik di prompt, tidak ke file) | Secret terpasang |
| L-5 | Jalankan eval M2 dengan LLM nyata. Bandingkan dengan tanpa LLM | Salah blokir di situs resmi turun, deteksi scam tidak turun → centang M4 |
| L-6 | **C5** issue ke Alief + Umar: data form dikirim ke penyedia LLM → kebijakan privasi + label App Store diperbarui di rilis yang sama | Issue dijawab |

Syarat: U-2 (A7) dijawab, D-4 selesai.

---

## 5. G3 · Data + kalibrasi + sumber blocklist (Imelda - Umar)

| # | Langkah | Selesai kalau |
|---|---|---|
| E-1 | **A4/D1** kumpulkan scam nyata berlisensi (laporan publik yang boleh dipakai, atau izin tertulis). Hanya lewat `capture.mjs`, data pribadi disamarkan | ≥ 50 scam nyata di eval set (`MIN_PER_CLASS`), atau angka yang disepakati di #73 |
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
| T-6 | Imelda - Umar | **D3** uji detector + `/analyze` di Safari iPhone sungguhan | D-7, build |
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

1. G0 sekarang: 4 issue sudah dibuka (#73 U-1, #74 U-2/3/5, #75 U-6, #76 U-8). Tunggu jawaban Imelda, kerjakan PR U-4.
2. G1 D-1 … D-8 (butuh kamu login Cloudflare).
3. P-1, P-2 sambil menunggu Alief/Imelda.
4. U-6 spike iframe, lalu U-7 kalau sempat.
5. G4 begitu build tim berbayar bisa dipasang di iPhone.

Yang bisa dikerjakan agent tanpa kamu: U-4, U-6, U-7, D-6 (setelah kamu kirim URL + output smoke test), draf semua issue, P-2 (tanpa mengisi secret).
Yang harus kamu sendiri: login Cloudflare + deploy, mengisi secret, tes di iPhone, keputusan U-1 … U-8, menghubungi PM.
