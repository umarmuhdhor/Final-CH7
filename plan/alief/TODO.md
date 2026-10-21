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
| A13 | Target test iOS | Agent menambah target test di `project.yml` lewat PR kecil terpisah dengan diff tertulis (D-alief-02); Alief memberi tahu Umar (C1), tidak perlu menunggu izin |
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
| B4 | Hyperdrive config `shoo-db` ke role `shoo_api`, **cache dimatikan** (D-alief-17). Pakai **Direct connection** Supabase (docs Cloudflare); kalau gagal karena IPv6, pakai **session pooler port 5432** dengan user `shoo_api.<project_ref>` — JANGAN transaction pooler 6543 | `npx wrangler hyperdrive create shoo-db --connection-string="postgres://shoo_api:<pw>@db.<ref>.supabase.co:5432/postgres" --caching-disabled` (diketik di terminal, tidak disimpan di file) | fase 07 deploy | [ ] |
| B5 | Secret Worker: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (hanya untuk Storage), `PUSH_RELAY_SECRET`; var `INVITE_BASE_URL`, `PUSH_RELAY_URL` | `npx wrangler secret put <NAMA>`; secret relay yang sama: `supabase secrets set PUSH_RELAY_SECRET` | fase 07 (`INVITE_BASE_URL`), 09, 11 | [ ] |
| B6 | Signing per developer lewat L0 (sudah di `main` `495c792`): `cp ios/Config/Local.xcconfig.example ios/Config/Local.xcconfig`, isi `DEVELOPMENT_TEAM`, `SHOO_BUNDLE_ID`, `SHOO_APP_GROUP` | Alief di Mac sendiri (gitignored), lalu `(cd ios && xcodegen)` | fase 01S, 11, QA-E2E | [ ] |
| B7 | Kunci APNs `.p8` (Key ID + Team ID): kunci baru di portal dibatasi ke **Sandbox atau Production** (docs Apple), jadi buat kunci Sandbox untuk D7 dan kunci Production untuk TestFlight (atau satu kunci lama yang berlaku di keduanya); `APNS_ENV=production` + kunci Production sebelum QA-E2E | developer.apple.com → Keys → Apple Push Notifications service. Simpan di password manager. Kunci, `APNS_TEAM_ID`, dan `APNS_TOPIC` (= bundle ID build yang diuji) harus dari **tim yang sama** dengan tim yang menandatangani build itu; kalau D7 (build iPhone Alief) dan TestFlight beda tim, ketiganya diganti di LANGKAH MANUAL fase 16 langkah 1. Diset di Edge Function `push` sebagai `APNS_KEY_P8_B64` (base64 satu baris) + `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC` lewat `supabase secrets set --env-file <file sementara di luar repo>` lalu file dihapus (fase 11 langkah 8); tidak pernah sebagai argumen perintah | fase 11 deploy, fase 16 | [ ] |
| B8 | App Store Connect record untuk bundle ID tim pemegang akun berbayar (nilai `SHOO_BUNDLE_ID` build TestFlight) + grup tester internal TestFlight | Umar atau Alief (siapa pemegang akun) | fase 16 | [ ] |
| B9 | Monitor uptime (mis. UptimeRobot Free) ping `https://shoo-api.<akun>.workers.dev/healthz` tiap 5 menit, dan `/healthz/db` (menulis `ops_heartbeat`) tiap 1 hari supaya Supabase tidak pause | Daftar akun, tambah monitor HTTP | setelah fase 07 deploy → **ditunda** (Alief, 21 Okt 2026) | [ ] ditunda: Worker `https://shoo-api.afindo-mi01.workers.dev`; risiko Supabase Free pause setelah ±7 hari tanpa aktivitas DB |

## C. Koordinasi tim (Alief yang mengirim; agent hanya menyiapkan isi pesan)

| # | Ke | Isi pesan singkat | Kapan | Status |
|---|---|---|---|---|
| C1 | Umar | "PR `chore/APP-test-targets` menambah target `ShooAppTests` + `ShooAppUITests` (dengan `GENERATE_INFOPLIST_FILE: YES`, karena folder test tidak punya Info.plist), scheme test, dan `excludes` (`Tests/**`, `UITests/**`, `ci/**`) di target Shoo pada `ios/project.yml` (diff persis di D-alief-24 + D-alief-28). Hanya aditif. Mohon review." | fase 01 | [ ] |
| C2 | Umar | "Draf GitHub Action ada di `backend/ci/backend.yml` dan `ios/ShooApp/ci/ios-app.yml` (langkah pasang di `backend/ci/README.md`). Pindahkan ke `.github/workflows/` dan tambah 5 secret repo: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`. Sampai itu, deploy manual dari Mac saya." | fase 12 | [ ] |
| C3 | Umar | "Info.plist dan entitlements target Shoo di-generate dari `project.yml`, jadi saya tidak bisa menambah key sendiri. Mohon tambahkan di `project.yml` target Shoo: (1) `info.properties.NSCameraUsageDescription` = \"Scan your family's QR code to connect.\" (PR-01), (2) `entitlements.properties.aps-environment: development` + capability Push Notifications (ON-05, GD-06), (3) [selesai lewat L0 `495c792`], (4) `info.properties.UIBackgroundModes: [audio]` supaya video tutorial ON-04 bisa PiP saat user di Settings (PRD ON-04). Keputusan yang saya butuhkan: tim Apple berbayar mana untuk (a) build iPhone saya (spike S1 butuh App Groups, uji push D7 butuh capability Push — Personal Team gratis tidak mendukung Push), dan (b) build TestFlight QA-E2E; kunci APNs `.p8` dibuat di tim yang sama dengan masing-masing build. Butuh sebelum fase 01S (signing), 02 (PiP, ada fallback), 14 (kamera), 11/15 (push)." | **sekarang** (bersama C1) | [ ] |
| C4 | Umar | Usulan kontrak screenshot (D-alief-07): extension mengirim `screenshotBase64` JPEG, sisi terpanjang ≤ 1280 px, quality 0,6, ≤ 150 KB, area bukti saja + input di-blur. Server membuang screenshot yang lebih besar (scan tetap disimpan). | fase 09 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C5 | Umar | Usulan kontrak `inviteUrl` (D-alief-03): `https://<api>/join?code=4821` (halaman yang membuka `shoo://join?code=4821`), karena WhatsApp tidak membuat link `shoo://` bisa diklik. | fase 08 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C6 | Umar + Imelda | Risiko peracunan blocklist (D-alief-06): siapa pun bisa daftar sebagai Guardian tanpa login, kirim scan palsu skor 100 untuk domain sah, lalu Not safe → domain masuk blocklist global. Filter otomatis saja bisa dilewati (Guardian + Protected milik penyerang yang sama). Default fase 10 sampai diputuskan (R2 §5, D-alief-25): (a) hanya verdict atas scan milik **Protected** yang terhubung + allowlist domain resmi/populer → masuk **antrean**, (b) domain baru dikirim di `GET /blocklist` setelah **review manual** Alief/Umar (SQL editor), (c) penghapusan dikirim lewat field baru `removed: [{domain, removedAt}]` (D-alief-18); sampai itu detector full refresh 1×/hari. Pertanyaan: tetap review manual, atau persetujuan otomatis (mis. ≥ 2 keluarga + umur link ≥ 72 jam + umur device ≥ 7 hari)? Butuh keputusan lead karena mengubah makna `GET /blocklist`. | **sebelum fase 10** | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C7 | Imelda | "`GET /blocklist?since=` sudah hidup di `<URL>`. Bentuk sesuai `contracts/api.md`. Token: pakai token device dari App Group (`device.token`). Entri baru dari verdict keluarga baru muncul setelah disetujui manual (D-alief-25, TODO C6/D9)." | akhir fase 07 → **ditunda** (Alief, 21 Okt 2026) | [ ] ditunda: URL `https://shoo-api.afindo-mi01.workers.dev/blocklist`; sementara input Imelda dimock dari `contracts/fixtures/` |
| C8 | Umar | "`GET /verdicts?domain=` sudah hidup di `<URL>` untuk polling EX-06 tiap 5 s. Endpoint ini berlaku untuk pemilik device mana pun, jadi extension Guardian juga bisa polling untuk halaman yang dia blokir sendiri (PRD §5 'User Guardian untuk dirinya → It's safe → halaman terbuka'). Catatan: Not safe dari keluarga masuk `GET /blocklist` global hanya setelah review manual (D-alief-25), verdict per pemilik tetap langsung berlaku. Rate limit token bucket 10 req / 10 s per device; 429 membawa `Retry-After`, mohon extension memperlakukannya sebagai coba lagi (bukan `verdict: null`)." | akhir fase 10 | [ ] |
| C9 | Umar | Teks push dilokalkan sesuai bahasa Guardian (`PATCH /devices/me {language}`); payload = kontrak + `aps.sound: "default"` (aditif) (D-alief-05). | fase 11 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C10 | Umar | `screenshotUrl` hanya diisi di `GET /scans/{id}` (signed URL 1 jam), `null` di daftar `GET /scans` (D-alief-04). `POST /scans` menerima tapi mengabaikan `ownerDeviceId`/`ownerName`. Scan `warning` selalu `verdict: null`. Kode error tambahan: `bad_json`, `already_connected`, `verdict_not_allowed`, `rate_limited`, `too_large`, `invalid_body`, `internal` (R3 §1). | fase 09 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C11 | Umar | Usulan kontrak D-alief-15: field opsional `extensionLastSeenAt` (ISO) di `PATCH /devices/me`, dikirim **extension** maks 1×/jam saat heartbeat + app saat foreground, supaya GD-03 bisa menampilkan "Not connected". Sampai disetujui server mengirim `extensionActive: true` kalau tidak ada data. | **sekarang** (sebelum fase 05/08) | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C12 | Umar | Usulan kontrak D-alief-21: `GET /devices/me` → `{ deviceId, name, avatarId, mode, language, guardian: { deviceId, name, avatarId } \| null }`, supaya Protected tahu guardian-nya dan tahu kalau sudah diputus Guardian (PR-04, PF-01, EX-06 "Waiting for [nama]"). | sebelum fase 13 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C13 | Umar | Konfirmasi: `GET /scans?owner=family` memuat scan Guardian sendiri juga (fixture `activity-family.json` memuat `dev_me`)? Default plan: ya, ikut fixture (D-alief-19). | sebelum fase 05/09 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C14 | Umar | Hasil spike S1/S2 (fase 01S): "Heartbeat pertama muncul <x> s setelah toggle + satu halaman dimuat; Off terdeteksi setelah <y>. Usulan `AppGroup.extensionActiveWindow` = <nilai>. Cabut 'Allow on every website' = <hasil> (untuk U7/EX-01). Link langsung `openExtensionsSettings` (iOS 26.2+) = <hasil>; iOS < 26.2: <n> tap dari `openSettingsURLString`." | akhir fase 01S | [ ] |
| C15 | Umar (→ PM Richard) | "ON-04 butuh video tutorial ≤ 60 s, ramah orang tua (PRD ON-04, dibuat PM). Format MP4 H.264, EN + ID kalau ada narasi. Sampai ada, app memakai placeholder." | fase 02 | [ ] |
| C17 | Umar | Usulan (hasil 01S, D-alief-34): di iOS 26.2+ app memakai `SFSafariExtensionManager.stateOfExtension(withIdentifier:)` (`.isEnabled`) sebagai sumber status tambahan di samping heartbeat `extension.lastSeenAt` (aturan `ios/ShooApp/CLAUDE.md` saat ini hanya heartbeat), dan `SFSafariSettings.openExtensionsSettings` untuk tombol Turn on. Sampai disetujui: status tetap heartbeat saja. | akhir fase 01S | [ ] |
| C18 | Umar | "Mohon aktifkan branch protection di `main` (CODEOWNERS sudah menyarankan) supaya status review PR (`reviewDecision`) terisi." | sebelum PR fase pertama | [ ] |
| C16 | Umar | "Deep link kontrak PR #1 (`shoo://scan/{id}`, `shoo://activity`, `shoo://join`, default Shield) sudah masuk plan: fase 14 (`join` + default) dan fase 15 (`scan`, `activity`). Mohon merge PR #1." (sebelumnya usulan D-alief-32, sekarang dikerjakan Umar) | sebelum fase 15 | [x] diterima kontrak (PR #1/#3/#4, merged 21 Okt) |
| C19 | Umar | "Privasi Apple (SECURITY §3 plan Alief): (1) usulan kontrak `DELETE /devices/me` → hapus semua data device (Guideline 5.1.1(v): app yang membuat akun wajib bisa menghapusnya); (2) `PrivacyInfo.xcprivacy` untuk target extension (UserDefaults App Group `1C8F.1`); (3) `ITSAppUsesNonExemptEncryption: NO` di Info.plist target Shoo lewat `project.yml`; (4) kalau ATS memblokir `http://localhost` di Debug: `NSAllowsLocalNetworking` hanya untuk Debug." | **sekarang** (bersama C3); butir (1) sudah dibangun di backend + diusulkan di PR #11 (aktif di cloud, menunggu keputusan Umar) | [ ] |

## D. Langkah manual yang butuh manusia

| # | Langkah | Kapan | Status |
|---|---|---|---|
| D1 | Pasang/cek tool: Xcode terbaru + simulator iOS 17+, `brew install xcodegen supabase/tap/supabase gitleaks jq`, Docker Desktop jalan, Node 24 (`nvm use 24`), `npm i -g pnpm` | sebelum fase 01/07 | [ ] |
| D2 | Pasang plugin: ECC (`/plugin install ecc@ecc`) + Superpowers, cek `/plugin list` | sebelum fase 01/07 | [ ] |
| D3 | Deploy cloud pertama (blocklist awal): blok LANGKAH MANUAL di log fase 07 | akhir fase 07 | [ ] |
| D4 | Deploy per fase backend (08–12): blok LANGKAH MANUAL di masing-masing log | akhir tiap fase be | [ ] |
| D5 | Uji spike S1/S2 di iPhone Alief (checklist LANGKAH MANUAL log fase 01S) | fase 01S, setelah signing (B6/L0) | [ ] |
| D6 | Dua iPhone (Guardian + Protected) dengan build TestFlight untuk QA-E2E (`APNS_ENV=production` sebelum build) | fase 16 | [ ] |
| D7 | Satu iPhone Alief dengan build Debug (Xcode, sandbox APNs) untuk uji push nyata | fase 11 | [ ] |
| D8 | Deploy ulang backend dari `main` setelah semua PR 07–12 di-merge + uji asap cloud (`curl /healthz`, `/healthz/db`, satu `POST /scans` dua device uji) — syarat G6 (D-alief-30) | setelah PR fase 12 merged | [ ] |
| D9 | Review antrean `blocklist_entries` di SQL editor (R2 §5 butir 4) 1×/hari selama uji/demo; catat jumlah disetujui/ditolak di log fase terakhir yang aktif | sejak fase 10 deploy | [ ] |

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
