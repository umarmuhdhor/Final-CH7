# Fase 18 — audit kode setelah sistem baru (R2 + replica), 29 Okt 2026

Pertanyaan Alief: apa lagi di kode yang perlu disesuaikan karena replica pindah ke Cloudflare R2 dan extension #178 tidak lagi mengirim screenshot, termasuk kode usang. Diperiksa terhadap `main` a57c531: grep backend + app + extension, skrip ekspor tak terpakai (backend), env var vs `env.ts`, build `xcodebuild build-for-testing` (Xcode SDK iOS 27.1, simulator iOS 27.0). Keputusan: D-alief-C27.

## Temuan

| # | Tingkat | Temuan | Bukti | Tindakan | Status |
|---|---|---|---|---|---|
| A1 | SEDANG | Favicon masih di Supabase Storage, padahal tampilan terbanyak (Activity: sampai 50 ikon per halaman, `viewFavicon` 600/menit). Tiap ikon = satu fetch eksternal Worker → Supabase + egress 5 GB/bulan. Kuota `fetchFaviconAll` 200/hari dihitung dari 1 GB Supabase | `routes/favicons.ts:32`, `services/favicons.ts:32`, `http/rateLimit.ts:28-30` | Pindah ke R2 dengan pola path baru (mis. `-icon.<ext>`), karena favicon lama memakai pola `-favicon.` yang sama (`scans.ts:119`) dan akan salah store; `ORIGINAL_FAVICON` mencakup dua pola sampai favicon lama habis (15 hari); `fetchFaviconAll` → ±1000/hari (64 KB × 1000 × 16 hari ≈ 1 GB R2) | Menunggu keputusan Alief: 18a atau 18c (D-alief-C27) |
| A2 | TINGGI (keamanan, 18c) | Worker memegang `SUPABASE_SERVICE_ROLE_KEY` (melewati RLS seluruh proyek) hanya untuk Storage | `services/screenshots.ts:85-88`; DB lewat Hyperdrive role `shoo_api` | Setelah A1 + 18c: cabut `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY`, hapus `SupabaseStorageStore`, migrasi bucket `screenshots`, `storage.test.sql`, cabang Supabase di tombstone/retensi | Rencana 18c (Catatan handoff) |
| A3 | RENDAH | Anggaran retensi `MAX_BATCHES = 10` / `storageCalls` ada karena 50 fetch eksternal per Cron | `cron/retention.ts:7-13,122` | Setelah 18c: satu anggaran R2 (1000 subrequest layanan), dibatasi CPU 10 ms | Rencana 18c |
| A4 | RENDAH | Komentar/dokumen masih berhitung dengan Supabase 1 GB atau "pindah ke R2 nanti" | `services/scans.ts:13-15`, `http/rateLimit.ts:28-29`, TODO E1, ARCHITECTURE §2/§3 | Komentar kode di 18a langkah 10; TODO E1 + ARCHITECTURE diperbarui sekarang | Plan: selesai; kode: 18a |
| B1 | TINGGI (sudah diketahui) | Target test ShooApp gagal compile di `main` | build lokal: `ios/ShooApp/Tests/TestDoubles.swift:88: error: type 'CountingScansRepository' does not conform to protocol 'ShooRepository'` | PR #175 (prasyarat 18f/18b, K19) | Menunggu merge #175 |
| B2 | OK | Target app compile **tanpa warning** dengan SDK iOS 27.1 (tidak ada API usang yang ditandai compiler); grep tanpa `NavigationView`, `onChange(of:perform:)` lama, `UIScreen.main`, `PreviewProvider` | build log | — | — |
| B3 | RENDAH | Satu `.foregroundColor` pada `Text` (soft-deprecated sejak iOS 17; `Text.foregroundStyle` mengembalikan `Text` di iOS 17+, target app 17.0) | `Features/Shield/GuardianHomeView.swift:379` | Ganti ke `.foregroundStyle(valueColor)` di PR app berikutnya yang menyentuh file itu | Belum |
| B4 | OK | Backend tanpa kode mati: setiap ekspor dipakai; semua key `env.ts` dipakai; tidak ada var di `wrangler.jsonc`/`.dev.vars.example` di luar `env.ts`. 54 ekspor hanya dipakai di file-nya sendiri (kata `export` tidak perlu, kosmetik, tidak diubah) | skrip ekspor + env | — | — |
| B5 | RENDAH | `backend/ci/README.md:1` masih berjudul "TODO C2", padahal C2 selesai (workflow hidup sejak #48/#70) | file | Ganti judul di 18a langkah 10 | 18a |
| B6 | RENDAH | Dokumen API backend dan kontrak masih menyebut `screenshotBase64` sebagai bukti utama | `backend/API.md:17,428-480,552`, `contracts/api.md:47,55` | `backend/API.md`: tandai deprecated di 18a, hapus di 18c; `contracts/` oleh Umar (#177/18c) | 18a / 18c |
| B7 | OK | Extension bersih setelah #178: `capture.js` hilang, tanpa izin `tabs`/`activeTab`, semua file di `Resources/` direferensikan | `manifest.json`, grep | — | — |
| B8 | RENDAH | Branch remote usang: `fix/EX-07-blur-coverage`, `fix/EX-07-screenshot` (usang), `feat/EX-07-page-replica` (sudah merge) | `git branch -r` | Info untuk Umar di C26 (f) | Draf C26 |
| B9 | SEDANG (tooling) | `ref/sim.sh` memilih nama simulator; `-destination name=…` memakai OS:latest = SDK 27.1, runtime 27.1 tidak terpasang → "Unable to find a device matching the provided destination specifier"; dua device bernama sama | build gagal sebelum perbaikan | `sim.sh` sekarang mengekspor `SIM_ID` (iPhone di runtime terbaru ≤ SDK); Verifikasi fase 18 memakai `id=$SIM_ID`; `SIM` tetap untuk perintah lama | Selesai |
| B10 | RENDAH | 9 worktree lokal untuk branch yang sudah merge; `default-indonesian` belum punya PR | `git worktree list`, `gh pr list` | TODO D12 (Alief, tidak dihapus agent) | Belum |
| B11 | Info | TODO yang masih terbuka di kode, sudah dilacak: kontak tim (`routes/privacy.ts:11`, `AppConfig.swift:29`, TODO E), video tutorial (`TutorialVideoPlayer.swift:10`, C15) | grep | — | Dilacak |

## Tidak diubah (bukan akibat Supabase)

Link lewat Worker + HMAC + cek DB tiap request (D-alief-B08), batas tampilan per viewer screenshot/favicon, penjaga unduh favicon situs (64 KB, 30/hari per device), batas body 16 KB / 256 KB, kuota screenshot 300 sampai 18c.
