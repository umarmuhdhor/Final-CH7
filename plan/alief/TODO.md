# TODO — yang dibutuhkan dari Alief (dan diteruskan ke Umar/Imelda)

Daftar ini berisi hal yang tidak bisa diputuskan atau dikerjakan agent sendiri: keputusan, akses akun, secret, langkah manual, dan pesan ke tim. Centang item yang sudah selesai, dan tulis jawabannya di kolom "Jawaban/Status".

Urutan: **A** keputusan (sudah dijawab lewat grilling 21 Okt 2026), **B** akun & secret (memblokir deploy dan push), **C** koordinasi tim (Alief yang mengirim pesan, agent tidak), **D** langkah manual, **E** opsional.

## A. Keputusan (hasil grilling, 21 Okt 2026)

| # | Pertanyaan | Jawaban |
|---|---|---|
| A1 | Bahasa plan | Indonesia. Kode, komentar, commit, judul PR: Inggris |
| A2 | Lokasi plan | `plan/alief/`, di-commit lewat PR sendiri `docs/alief-plan` |
| A3 | Stack backend | API di **Cloudflare Workers** (Hono + postgres.js via Hyperdrive). DB + Storage di **Supabase** (D-alief-01) |
| A4 | Jadwal | Tanpa slot jam. Fase berurutan per track |
| A5 | Struktur kerja | Dua track paralel (app, be) di worktree terpisah, lalu track c |
| A6 | Branch/PR | Aturan repo: satu branch per ID PRD, PR ke `main`, reviewer Umar, agent tidak merge sendiri, PR boleh ditumpuk |
| A7 | Format QA | Format laporan QA Catalyst, Markdown di `plan/alief/qa/`; ekspor .docx hanya kalau diminta |
| A8 | Skill | Siklus ECC 9 langkah ala IBM + Superpowers di plan/TDD/verifikasi/finish (PROMPT.md) |
| A9 | Model | Opus 5.5 untuk backend, keamanan, track c. Sonnet 5.5 untuk layar fixture dan QA |
| A10 | Pemilik akun | Umar: Team ID Apple + capability Xcode. Alief: kunci APNs `.p8`, Supabase, Cloudflare |
| A11 | Screenshot | Supabase Storage dengan batas ketat + adapter `ScreenshotStore`. Pindah ke R2 kalau Storage > 700 MB atau egress > 3,5 GB/bulan |
| A12 | Auto-pause Supabase | Monitor uptime eksternal ping `/healthz` |
| A13 | Target test iOS | Agent menambah target test di `project.yml` lewat PR kecil terpisah; Alief memberi tahu Umar (C1) |
| A14 | Desain | Belum ada Figma. Wireframe PRD §7 + `apple-design`, re-skin nanti |
| A15 | Cloud | Agent bebas di lokal. Semua aksi cloud = LANGKAH MANUAL |
| A16 | Lingkungan | Lokal + satu stack cloud (`shoo-demo` + Worker `shoo-api`) |
| A17 | Distribusi iOS | Simulator untuk dev + QA-A. TestFlight untuk QA-E2E + demo |
| A18 | Deploy | Manual dari Mac Alief. Draf GitHub Action ditulis, Umar yang memasang (C2) |

## B. Akses dan secret

Jangan tempel nilai secret di chat atau di file repo. Agent hanya perlu tahu bahwa langkahnya sudah selesai.

| # | Yang dibutuhkan | Cara | Dibutuhkan di | Status |
|---|---|---|---|---|
| B1 | Proyek Supabase `shoo-demo`, region `ap-southeast-1` (Singapore), plan Free | Dashboard Supabase → New project. Simpan password DB di password manager | fase 07 deploy | [ ] |
| B2 | `supabase login` + `supabase link --project-ref <ref>` di Mac Alief | CLI, login lewat browser | fase 07 | [ ] |
| B3 | `npx wrangler login` (akun Cloudflare Alief, plan Free) | Login lewat browser | fase 07 | [ ] |
| B4 | Hyperdrive config `shoo-db` ke role `shoo_api` (connection string pooler Supabase, port 5432 session atau 6543 transaction) | `npx wrangler hyperdrive create shoo-db --connection-string=...` (diketik di terminal, tidak disimpan di file) | fase 07 deploy | [ ] |
| B5 | Secret Worker: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (hanya untuk Storage), `INVITE_BASE_URL` | `npx wrangler secret put <NAMA>` | fase 09 deploy | [ ] |
| B6 | Apple Developer Team ID diisi di `project.yml` | Umar (lihat C3) | QA-E2E, TestFlight | [ ] |
| B7 | Kunci APNs `.p8` (Key ID + Team ID), environment sandbox dulu | developer.apple.com → Keys → Apple Push Notifications service. Simpan di password manager. `wrangler secret put APNS_KEY_P8` (isi file ditempel di prompt), `APNS_KEY_ID`, `APNS_TEAM_ID` | fase 11 deploy | [ ] |
| B8 | App Store Connect record `com.shoo.app` + grup tester internal TestFlight | Umar atau Alief (siapa pemegang akun) | fase 16 | [ ] |
| B9 | Monitor uptime (mis. UptimeRobot Free) ping `https://shoo-api.<akun>.workers.dev/healthz` tiap 5 menit, dan `/healthz/db` tiap 1 hari (supaya Supabase tidak pause) | Daftar akun, tambah monitor HTTP | setelah fase 07 deploy | [ ] |

## C. Koordinasi tim (Alief yang mengirim; agent hanya menyiapkan isi pesan)

| # | Ke | Isi pesan singkat | Kapan | Status |
|---|---|---|---|---|
| C1 | Umar | "PR `chore/APP-test-targets` menambah target `ShooAppTests` + `ShooAppUITests` dan exclude `ci/` di target Shoo pada `ios/project.yml`. Hanya aditif, tidak mengubah target lain. Mohon review." | fase 01 | [ ] |
| C2 | Umar | "Draf GitHub Action ada di `backend/ci/backend.yml` dan `ios/ShooApp/ci/ios-app.yml` (langkah pasang di `backend/ci/README.md`). Pindahkan ke `.github/workflows/` dan tambah 5 secret repo: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`. Sampai itu, deploy manual dari Mac saya." | fase 12 | [ ] |
| C3 | Umar | "Butuh Team ID Apple di `project.yml` + capability **Push Notifications** (target Shoo) untuk ON-05/GD-06. Saya isi `aps-environment` di `ShooApp/Shoo.entitlements`." | fase 02 / 11 | [ ] |
| C4 | Umar | Usulan kontrak screenshot (D-alief-07): extension mengirim `screenshotBase64` JPEG, sisi terpanjang ≤ 1280 px, quality 0,6, ≤ 150 KB, area bukti saja + input di-blur. Server membuang screenshot yang lebih besar (scan tetap disimpan). | fase 09 | [ ] |
| C5 | Umar | Usulan kontrak `inviteUrl` (D-alief-03): `https://<api>/join?code=4821` (halaman yang membuka `shoo://join?code=4821`), karena WhatsApp tidak membuat link `shoo://` bisa diklik. | fase 08 | [ ] |
| C6 | Umar + Imelda | Risiko peracunan blocklist (D-alief-06): satu Guardian bisa memasukkan domain apa pun ke blocklist global lewat Not safe. Usulan: blocklist hanya memuat domain dengan verdict `not_safe` dari scan berstatus `blocked`, ditambah allowlist domain resmi brand. Butuh keputusan lead karena mengubah makna `GET /blocklist`. | fase 10 | [ ] |
| C7 | Imelda | "`GET /blocklist?since=` sudah hidup di `<URL>`. Bentuk sesuai `contracts/api.md`. Token: pakai token device dari App Group (`device.token`)." | akhir fase 07 | [ ] |
| C8 | Umar | "`GET /verdicts?domain=` sudah hidup di `<URL>` untuk polling EX-06 tiap 5 s." | akhir fase 10 | [ ] |
| C9 | Umar | Teks push dilokalkan sesuai bahasa Guardian (`PATCH /devices/me {language}`), bentuk payload tetap (D-alief-05). | fase 11 | [ ] |
| C10 | Umar | `screenshotUrl` hanya diisi di `GET /scans/{id}` (signed URL 1 jam), `null` di daftar `GET /scans` (D-alief-04). | fase 09 | [ ] |

## D. Langkah manual yang butuh manusia

| # | Langkah | Kapan | Status |
|---|---|---|---|
| D1 | Pasang/cek tool: Xcode terbaru + simulator iOS 17+, `brew install xcodegen supabase/tap/supabase`, Docker Desktop jalan, Node 24 (`nvm use 24`), `npm i -g pnpm` | sebelum fase 01/07 | [ ] |
| D2 | Pasang plugin: ECC (`/plugin install ecc@ecc`) + Superpowers, cek `/plugin list` | sebelum fase 01/07 | [ ] |
| D3 | Deploy cloud pertama (blocklist awal): blok LANGKAH MANUAL di log fase 07 | akhir fase 07 | [ ] |
| D4 | Deploy per fase backend (08–12): blok LANGKAH MANUAL di masing-masing log | akhir tiap fase be | [ ] |
| D5 | Spike #2 dan #3 Umar selesai → buka fase 17 (ON-04) | menunggu Umar | [ ] |
| D6 | Dua iPhone (Guardian + Protected) dengan build TestFlight untuk QA-E2E | fase 16 | [ ] |

## E. Opsional

| # | Hal | Manfaat |
|---|---|---|
| E1 | Pindah screenshot ke Cloudflare R2 (adapter `ScreenshotStore`) | Kalau Storage > 700 MB atau egress > 3,5 GB/bulan |
| E2 | GitHub Action deploy otomatis aktif (C2) | Tidak perlu deploy manual |
| E3 | Realtime verdict (Supabase Realtime / WebSocket) menggantikan polling 5 s | Unblock lebih cepat; butuh usulan kontrak |
| E4 | Deferred deep link setelah install (PR-03 P1) | Kode terisi otomatis setelah install dari App Store |
| E5 | Ekspor laporan QA ke .docx untuk Google Drive | Format sama dengan QA Catalyst |

## Referensi

- Keputusan lengkap: [`log/DECISIONS.md`](log/DECISIONS.md)
- Arsitektur: [`ARCHITECTURE.md`](ARCHITECTURE.md) · Keamanan: [`SECURITY.md`](SECURITY.md)
