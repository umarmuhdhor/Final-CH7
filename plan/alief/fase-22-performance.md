# Fase 22 — Optimisasi performa: CPU Worker + snapshot salinan halaman (BE CPU, EX-07, DT-04, PR-05)

| Field | Nilai |
|---|---|
| Track | c (backend dulu, lalu app) |
| Branch | 22a-0 tanpa branch (pengukuran baseline, hasil ke `log/fase-22.md` lewat PR docs) · 22a-1 `fix/BE-worker-cpu` (kunci HMAC di-cache, import zod, minify + source map, decode base64 native) · 22a-2 `fix/EX-07-replica-inflate` (validasi replica lebih murah + cek kuota sebelum inflate, setelah K4/K12 dijawab dan 19a merge) · 22a-3 `fix/BE-rate-limit-one-trip` (opsional, hanya kalau S3 membuktikan biaya protokol DB besar; migrasi) · 22b `fix/DT-04-snapshot-perf` (app Detail) · 22c `fix/PR-05-favicon-cache` (opsional, K10). Semua dari `origin/main` saat mulai |
| Prasyarat | 22a: tidak ada (berdiri sendiri). Sebaiknya setelah fase 19 merge, karena 19a mengubah `services/replicas.ts`, `db/repo/scans.ts` (`precheckReplica`/`reserveReplica`) dan `test/replicas.test.ts` (konflik dengan 22a-2 dan K12). Fase 20b memindah `services/screenshotLinks.ts` → `services/signedLinks.ts`, membuang kind `screenshot` dan `test/screenshots.test.ts` (`fase-20-screenshot-sunset.md:89,100,135`): 22a-1 O1 dikerjakan di file yang ada di `main` saat mulai (lihat Catatan handoff). 22b: **PR #204** (`fix/DT-04-replica-hardening`) dan **PR #205** (close-out fase 18, berisi catatan "Ditunda" dan angka `wrangler tail` 31 Okt di butir 92) merge dulu — **terpenuhi**: keduanya MERGED 31 Okt 15:40 UTC (`main` b88a962); #204 mengubah `DetailView.swift`, `ReplicaSnapshot.swift`, `ReplicaWebView.swift`, `ReplicaLoader.swift` yang juga disentuh 22b. Simulator "Shoo QA SE" (iPhone SE 3rd gen, iOS 26.5) sudah ada lokal (C19) |
| Urutan | 22a-0 baseline (S1–S4) → jawaban K1–K6 (K12 setelah 19a merge) → 22a-1 (TDD) → merge + deploy CI → ukur ulang → 22a-2 (kalau K4 = a/b atau K12 = a; setelah 19a merge) → ukur ulang → 22a-3 hanya kalau S3 positif → 22b-0 baseline app (S5–S8) → jawaban K7–K9 → 22b → 22c (opsional) |
| Requirement | Fase 18 K2 + log fase 18 butir 92 (target CPU ≤ 8 ms tidak tercapai, `wrangler tail` 31 Okt; masuk `main` lewat PR #205, 31 Okt 15:40 UTC, butir 92 `[~]`), kandidat optimasi dari fase 19 (`fase-19-replica-quota.md:191`: keluarga penuh tetap memakai slot `replicaIp` + CPU inflate, K12), review security 18a L2 (CPU `waitUntil`), review Swift 18b "Ditunda" (PR #205), aturan repo "UI PR = screenshot before/after", `ARCHITECTURE.md` §3 (Free: 10 ms CPU), SECURITY §3 P6, P9, P13 |
| Model + reviewer ECC | Opus 5.5 · 22a: `ecc:performance-optimizer` → `ecc:typescript-reviewer` → `ecc:security-reviewer` (22a-3 juga `ecc:database-reviewer`); 22b/22c: `ecc:swift-reviewer` → `ecc:security-reviewer`. Berurutan, tidak paralel |
| Fase berikutnya | Tidak ada yang menunggu fase 22. Arah sebaliknya: fase 22 memakai query GraphQL fase 21 (C9) untuk baseline S4, dan alert fase 21 `worker_exceeded_cpu` (status `exceededResources` > 0, `fase-21-monitoring.md:134`; fase 21 tidak punya ambang `cpuTimeP99`) sebagai pemicu K6. Angka baseline 22a-0 boleh diusulkan ke fase 21 sebagai `warn` baru, bukan prasyarat |

## Tujuan

**Masalah backend.** Rencana fase 18 (K2, rencana A) memasang target `POST /scans` ≤ 8 ms CPU. `wrangler tail` cloud 31 Okt menunjukkan semua rute jauh di atas batas Free 10 ms, walau tidak ada yang dipotong (`outcome: ok`, nol `exceededCpu`; sumber: `log/fase-18.md:92`, di `main` sejak #205; 22a-0 mencatat ulang angka per rute di `log/fase-22.md`):

| Rute | CPU (tail, 31 Okt) | Kerja yang terlihat di kode |
|---|---|---|
| `POST /scans` | 52–186 ms (terburuk = dengan replica) | auth, `hit` (transaksi), `readJson` ≤ 512 KB + zod, `hitLight`, insert, 2 query push, lalu `waitUntil`: favicon (fetch + R2), push, replica (decode base64 ≤ 400 KB + inflate ≤ 3 MB + R2) |
| `POST /devices` | 20–60 ms | 2× `hit`, zod kecil, `sha256`, insert. Hampir tanpa kerja CPU sendiri |
| `POST /family/*` | 34–61 ms | auth + `hit` + query |
| `GET /scans` | 3–40 ms | auth + query + **satu `importKey` HMAC per item** untuk link favicon |
| `GET /replicas` | 1–60 ms | verify HMAC, 2× `hit`, baca R2 ≤ 300 KB |

Pola "rute yang hampir tidak menghitung apa pun tetap 20–60 ms, sementara request lain 1–3 ms" menunjuk ke biaya tetap per isolate atau per koneksi, bukan ke logika rute. Dugaan utama (semua **belum terverifikasi**, diuji di S1–S4):

1. **Cold start ikut terhitung.** Bundle 1,0 MB tidak di-minify, 789 KB di antaranya zod (lihat Cek kelayakan C1). Di Node, `import` zod saja makan ±31 ms CPU (bench lokal 31 Okt, `process.cpuUsage`). Dokumentasi Cloudflare tidak menyebut apakah global scope dihitung ke CPU request pertama.
2. **Biaya protokol Postgres per request.** Satu klien `postgres()` baru per request (`app.ts:44`, `db/client.ts:9-11`), `hit` = 5 pesan dalam transaksi (`rateLimit.ts:77-92`). JIT dingin membuat parsing protokol mahal di isolate baru.
3. **Kerja per item / per byte yang bisa dihindari.** `importKey` HMAC tiap link (`screenshotLinks.ts:14-15,30`), `atob` + loop `charCodeAt` 300 KB (`images.ts:13-19`), inflate replica 4 KB per langkah dengan `setTimeout(0)` di antaranya (`replicas.ts:23,170-176,188`).

**Masalah app.** Review Swift 18b (PR #205, `log/fase-18.md` "Ditunda") mencatat: snapshot salinan halaman 200 pt (`ReplicaSnapshot.swift:28`) dipakai di kartu 270 pt (`EvidenceCard.swift:148,191-192`) dan layar penuh dengan zoom sampai 5× (`ScreenshotView.swift:140,146-151`) → buram; web view tersembunyi 390 × 3000 pt (`ReplicaSnapshot.swift:21,23,45,93`) diperkirakan ±42 MB backing store di @3x, ditambah gambar ±11 MB dan string HTML ≤ 3 MB; `ReplicaWebView` (representable) dan jalur `scrollToFocus` tidak dipakai; `Task.detached` di `DetailView.swift:359-361` tidak ikut dibatalkan; `Race<T>` perlu dicek untuk mode Swift 6; `ReplicaLoader` menambah byte satu per satu (`ReplicaLoader.swift:55-58`).

**Hasil akhir yang diinginkan.**
- Ada angka baseline yang bisa diulang (lokal + cloud), per rute, sebelum dan sesudah tiap perubahan.
- CPU per rute turun dengan perubahan kecil berisiko rendah dulu, masing-masing dengan test yang membuktikan perilaku sama. Target angka = K1.
- Rencana yang jelas kalau Cloudflare mulai menegakkan batas 10 ms (K6).
- Salinan halaman tajam di kartu dan layar penuh, memori puncak Detail terukur di iPhone SE dan Pro Max, kode mati hilang, pembatalan benar. Screenshot before/after untuk PR UI.

## Bacaan wajib

- `plan/alief/fase-18-page-replica.md` K2 (rencana A/B inflate) dan `plan/alief/log/fase-18.md` bagian Benchmark + butir 92.
- `plan/alief/log/fase-18.md:131` di `main` (catatan "Ditunda" review Swift; #205 sudah merge).
- `git show 8fd9751 --stat -- ios/ShooApp/Features/Detail/` (#204, sudah di `main`).
- `plan/alief/ARCHITECTURE.md` §3 (batas Free), `plan/alief/SECURITY.md` §3 P6, P9, P13.
- `plan/alief/fase-21-monitoring.md` C9 (GraphQL `cpuTimeP50`/`cpuTimeP99`) — dipakai untuk baseline cloud.
- Backend: `backend/api/src/app.ts`, `db/client.ts`, `http/{auth,rateLimit,validate,keyHash,crypto}.ts`, `routes/{scans,devices,replicas}.ts`, `services/{replicas,images,screenshotLinks,favicons}.ts`, `services/push/{apns,jwt,sender}.ts`, `wrangler.jsonc`.
- App: `ios/ShooApp/Features/Detail/{ReplicaSnapshot,ReplicaWebView,ReplicaLoader,DetailView,EvidenceCard,ScreenshotView}.swift`, `Components/SiteIcon.swift`, `Tests/{PageCopyTests,ReplicaViewTests,ReplicaLoaderTests}.swift`, `UITests/DetailUITests.swift`.
- Docs Cloudflare (dibaca 31 Okt 2026): Limits `developers.cloudflare.com/workers/platform/limits/`, CPU profiling lokal `…/workers/observability/dev-tools/cpu-usage/`, profiling produksi `…/workers/observability/profiling-in-production/`.

## Fakta batas CPU Workers Free (docs Cloudflare, 31 Okt 2026)

- Tabel Limits: "CPU time per HTTP request | 10 ms" (Free) vs "5 min (default: 30 seconds)" (Paid). `ARCHITECTURE.md:62` juga mencatat 10 ms per Cron Trigger.
- Menunggu I/O tidak dihitung: "Waiting on network requests (such as fetch() calls, KV reads, or database queries) does not count toward CPU time."
- Penegakan: tiap isolate punya "some built-in flexibility to allow for cases where your Worker infrequently runs over the configured limit", tetapi "If your Worker starts hitting the limit consistently, its execution will be terminated". Error ke klien: 1102 "Worker exceeded resource limits".
- Startup: global scope harus selesai dalam 1 detik (error deploy 10021). Docs **tidak** menyebut apakah waktu startup masuk CPU request (→ spike S2).
- Timer di produksi hanya maju saat I/O (docs `…/workers/runtime-apis/performance/`: "APIs that return timers, including performance.now() and Date.now(), only advance or increment after I/O occurs"): `performance.now()` / `Date.now()` **tidak bisa** mengukur CPU di cloud. Jadi tidak ada "span debug" di kode produksi; pengukuran memakai profiler + `cpuTime` dari tail/GraphQL/flamegraph dashboard.
- Memori: 128 MB per isolate (heap JS + WebAssembly), dari tabel Limits yang sama.

**Risiko kalau penegakan diperketat.** Data 31 Okt: tidak ada rute yang "infrequently" di atas 10 ms; semua rute DB selalu di atasnya. Kalau Cloudflare menegakkan secara konsisten: `POST /devices` dan `POST /family/*` → 1102 → onboarding dan pairing gagal total; `POST /scans` → klien bisa dapat 1102 sebelum atau sesudah 201; kerja `waitUntil` (push ke Guardian, favicon, replica) ikut terpotong. Push dikirim sebelum replica (`routes/scans.ts:171-183`), jadi urutan itu tetap menolong. Cara tahu lebih awal: alert `worker_exceeded_cpu` fase 21 (GraphQL status `exceededResources`) + K6.

## Cek kelayakan (diverifikasi terhadap `origin/main` 2720b13, 31 Okt 2026)

| # | Butir | Bisa? | Temuan dari kode (file:baris) | Tindakan |
|---|---|---|---|---|
| C1 | Ukuran bundle / cold start | Ya | `npx wrangler deploy --dry-run --outdir` lokal: `index.js` **1,0 MB** (tidak di-minify, `wrangler.jsonc` tanpa `minify`), gzip upload 428 KiB. Per paket (komentar modul di bundle): zod 789 KB, `src` 157 KB, postgres 86 KB, hono 59 KB; 64 file locale zod ikut. Semua 6 file memakai `import { z } from "zod"` (`http/validate.ts:2`, `routes/{devices,family,scans,verdicts,blocklist}.ts`). Spike esbuild 31 Okt (skema kecil yang sama): `import { z }` 763 KB, `import * as z` 182 KB, `zod/mini` 38 KB (minified 454 / 90 / 18 KB) | 22a-1: `import * as z from "zod"` (K2) + `minify: true` (K3). Pengaruh ke CPU request = S2 |
| C2 | Kunci HMAC link di-import ulang | Ya | `screenshotLinks.ts:14-15` `hmacKey` memanggil `crypto.subtle.importKey` di **setiap** `signedLink` (`:30`) dan `verifySignedLink` (`:67`). `GET /scans` membuat satu link favicon per item (`routes/scans.ts:219`, ≤ 50 item), `GET /scans/{id}` tiga link (`:234-236`). Pola cache per isolate sudah ada untuk rate key (`keyHash.ts:4-22`). Bench Node: 20 link importKey tiap kali 2,8–8,1 ms vs kunci di-cache 0,2–0,7 ms | 22a-1 O1 |
| C3 | Decode base64 replica/screenshot | Ya | `images.ts:13-19` `atob` lalu loop `charCodeAt` per byte. Bench Node 400 KB: 1,8–5,8 ms vs `Uint8Array.fromBase64` 0,03 ms. Ketersediaan `Uint8Array.fromBase64`: **ada** di workerd lokal 1.20261019.1 dengan `compatibility_date` 2026-10-01 (`wrangler.jsonc:5`), uji `workerd serve` 31 Okt (scratchpad): `typeof` = `function`, `"QR=="` → `[65]` sama dengan `atob` (mode `loose` menerima bit sisa), `"QQ=a"` → `SyntaxError`. Runtime cloud belum dicek (test `typeof` di 22a-1 + fallback tetap). `@cloudflare/workers-types` dan `lib` ES2022 (`tsconfig.json:6`) belum punya tipenya → deklarasi lokal kecil | 22a-1 O4 dengan deteksi fitur + fallback ke kode lama |
| C4 | Inflate replica | Ya, dengan pilihan | `replicas.ts:125-135` decode lalu `inflatedSize` (`:144-186`): `DecompressionStream` diberi 4 KB per tulis (`INFLATE_SLICE`, `:23`) dan `setTimeout(0)` tiap slice (`:175,188`) → ±75 putaran untuk 300 KB. Log fase 18: inflate di Node 9–15 ms terburuk. Jalan di `waitUntil` setelah push (`routes/scans.ts:178-182`), jadi masuk `cpuTime` invocation yang sama (indikasi: `POST /scans` terburuk 186 ms = dengan replica). Uji `workerd serve` lokal 31 Okt dengan bom nol 289 670 byte (±298 MB): yield `setTimeout(0)` → `consumed` = 4 096 (slice 4 KB) / 16 384 (slice 16 KB); yield microtask (`await Promise.resolve()`) atau tanpa yield → `consumed` = 289 670, **seluruh bom di-inflate** sebelum reader sempat menghitung. Jadi yield `setTimeout` wajib; biayanya jam dinding (timer), bukan CPU | K4 → 22a-2 |
| C5 | Rate limit = transaksi 5 pesan | Ya, migrasi | `hit` (`rateLimit.ts:77-92`): BEGIN, advisory lock, count, insert, COMMIT. `POST /scans` 1× `hit` + 1× `hitLight` (`routes/scans.ts:114,118`) + di `waitUntil` favicon `hit`+`hitLight` (`services/favicons.ts:42-43`) + replica `hit` (`replicas.ts:73`); `POST /devices` 2× `hit` (`routes/devices.ts:82,85`); `GET /replicas` 2× `hit` (`routes/replicas.ts:43-44`); fase 21 menambah satu `hit` `"all"` di `/ops/status` setelah token cocok (token salah = 404 tanpa query, `fase-21-monitoring.md` K6). Biaya CPU postgres.js per pesan **belum terverifikasi** | S3 dulu; 22a-3 hanya kalau positif (K5) |
| C6 | Klien DB per request | Tetap | `app.ts:44` + `db/client.ts:9-11`: `postgres()` baru per request, `max: 5`, `fetch_types: false`. Docs Hyperdrive minta klien per request (komentar `app.ts:32-34`). Auth SCRAM postgres.js pakai WebCrypto PBKDF2 native (`node_modules/postgres/cf/polyfills.js` `pbkdf2Sync` → `subtle.deriveBits`); 4096 iterasi ±0,8 ms di Node. Apakah Hyperdrive meminta SCRAM dari Worker **belum terverifikasi** | Tidak diubah; S3 mengukur porsi koneksi |
| C7 | Validasi body 512 KB | Ya, murah | `validate.ts:37-62` baca stream + `TextDecoder`, `:26-34` `JSON.parse`, zod `scanBody` (`routes/scans.ts:47-72`). Bench Node body 381 KB: decode + parse 0,2–0,3 ms, zod 0,2–2,4 ms (panas/dingin) | Tidak ada perubahan; diawasi di profil S1 |
| C8 | Push APNs (ES256) | Sudah di-cache | `apns.ts:35-57` kunci per isolate, `:77-89` JWT single-flight, umur 50 menit (`:31`). Di cloud saat ini `APNS_TOPIC` kosong (`wrangler.jsonc:32`) → `LogSender` (`sender.ts:35-45`), jadi ES256 belum jalan sama sekali | Tidak ada perubahan; catat di S1 setelah topic diisi |
| C9 | Favicon di `waitUntil` | Murah CPU | `faviconFetch.ts:50` batas 64 KB, `:77-89` ≤ 2 redirect, lookup DoH = I/O. CPU utama = kueri DB (`favicons.ts:37-67`) | Tidak ada perubahan |
| C10 | Ukur CPU di produksi | Ya, Free belum pasti | Workers & Pages → Worker → Observability → Flamegraph → Profile type CPU, durasi 1 000–50 000 ms (default 10 000), unduh pprof (docs "profiling in production"). Docs **tidak** menyebut apakah tersedia di Free → LANGKAH MANUAL 3 memastikan; kalau tidak ada, S4 hanya GraphQL + tail. Source map dianjurkan ("frames reference the minified bundle"); wrangler mengunggahnya **default sejak 4.150.0**, repo memakai `^4.151.3` (`package.json`). `wrangler.jsonc:11` observability aktif, `invocation_logs: false` (URL tidak tercatat, D-alief-40) | 22a-1 `upload_source_maps: true` eksplisit (tidak bergantung versi wrangler, K3) |
| C11 | App: resolusi snapshot | Ya | `ReplicaSnapshot.swift:28` `imageWidth = 200` pt (→ 600 px @3x) dipakai `snapshotWidth` (`:69`); kartu menggambar 270 pt (`EvidenceCard.swift:148,192`) → upscale 1,35×; layar penuh `scaledToFit` selebar layar (`ScreenshotView.swift:146-150`, `DetailView.swift:59-61`), 375–440 pt, zoom ≤ 5× (`ScreenshotView.swift:140`) → upscale ≥ 1,9× | K7 |
| C12 | App: memori web view tersembunyi | Ya, ukur dulu | Frame 390 pt lebar (`ReplicaSnapshot.swift:21,45`), tinggi sampai 3000 pt (`:23,93`) di luar layar. Estimasi 42 MB = 1170 × 9000 px × 4 B, **belum terverifikasi**: tile WebKit hidup di proses `WebContent`/GPU, bukan proses app, jadi tidak masuk batas jetsam app tetapi menambah tekanan memori sistem. Proses WebContent mati → `onFailure` → placeholder (`ReplicaWebView.swift:118-120`) | S6/S7 → K8 |
| C13 | App: kode mati | Ya | `struct ReplicaWebView` (`ReplicaWebView.swift:167-188`) tanpa pemakai (grep 31 Okt: hanya definisi). `scrollsToFocusOnFinish` (`:48`) selalu `false` di satu-satunya pemanggil (`ReplicaSnapshot.swift:42`), jadi `scrollToFocus` (`:155-163`) tidak pernah jalan. `focusOffset` (`:82-85`) hanya dipakai test (`ReplicaViewTests.swift:160-161`). `ReplicaWebController` tetap dipakai | K9 |
| C14 | App: `Task.detached` | Ya | `DetailView.swift:359-361` `Task.detached { (ReplicaHTML.locked(html), ReplicaMeta.read(from: html)) }.value`: pembatalan task Detail tidak diteruskan, dua pindai 3 MB tetap jalan sampai habis. Setelahnya `render` cepat keluar (`Race.begin` cek `Task.isCancelled`, `ReplicaSnapshot.swift:159-161`), jadi kerugiannya CPU, bukan state salah | 22b: fungsi `nonisolated async` (pembatalan terstruktur) |
| C15 | App: `Race<T>` + Swift 6 | Ya, cek dulu | Proyek di mode Swift 5 (`ios/CLAUDE.md`). `Race` adalah `@MainActor final class` (`ReplicaSnapshot.swift:149-184`) → otomatis Sendable; yang perlu dicek: `T` (UIImage, Bool) melewati `CheckedContinuation` dan closure `start` `@escaping` tanpa `@Sendable`. Peringatan nyata **belum terverifikasi** | 22b: build dengan `SWIFT_STRICT_CONCURRENCY=complete` di baris perintah (tanpa ubah `project.yml`), perbaiki hanya peringatan di file Detail |
| C16 | App: `ReplicaLoader` per byte | Ya, ukur dulu | `ReplicaLoader.swift:52-58` `for try await byte in bytes { buffer.append(byte) }` sampai 3 MB, lalu `Data(buffer)` (`:62`) dan `String(data:)` (`:63`) → dua salinan tambahan (puncak ±9 MB untuk 3 MB). Test batas sudah ada (`ReplicaLoaderTests.swift:90,96,104`) | S8 → 22b kalau lambat |
| C17 | App: favicon Activity | Ya, opsional | `SiteIcon.swift:90` `.task(id: url)`; link favicon ditandatangani ulang tiap `GET /scans` (`exp` = sekarang + 3600, `screenshotLinks.ts:29-32`) → URL berubah tiap reload list → semua ikon diunduh ulang; sesi tanpa cache (`ScreenshotView.swift:36-44` `urlCache = nil`). Decode sudah di-downsample 144 px (`SiteIcon.swift:45`) | K10 → 22c |
| C18 | App: waktu launch | Tidak diklaim | Tidak ada pengukuran launch di repo (grep `XCTApplicationLaunchMetric` 0 hasil) | Di luar fase ini; hanya dicatat di handoff |
| C19 | Simulator SE + Pro Max | Ya, sudah ada | `xcrun simctl list` 31 Okt: dua "Shoo QA SE" (`iPhone-SE-3rd-generation`, iOS 26.5): `483B28B6-913A-4C3A-8A4C-0C7219022682` dan `516DCC10-B989-4F69-8906-D3FFB9FDF4FC` (fase 23 LANGKAH MANUAL 1 menghapus yang kedua); iPhone 17 Pro Max iOS 26.5 `4FBB910B-DA84-4552-B174-28396BD496DB` (sama dengan fase 20). `sim.sh` memilih runtime terbaru ≤ SDK 27.1 = iPhone 18 Pro Max iOS 27.0. `-destination name=` ambigu | Pakai `id=`: `SE_ID=483B28B6-913A-4C3A-8A4C-0C7219022682`, `PM_ID=4FBB910B-DA84-4552-B174-28396BD496DB` |
| C20 | Kuota penuh tetap bayar `replicaIp` + inflate | Ya, setelah 19a | Urutan `attachReplica` (`replicas.ts:59-86`): kill-switch → `precheckReplica` (reuse + ada keluarga, `db/repo/scans.ts:190-198`) → `hit(replicaIp)` (`:73`) → `decodeReplica` (decode + inflate ≤ 3 MB, `:79`) → baru `reserveReplica` memeriksa kuota owner/global (`:83-86`). Device atau global yang sudah penuh tetap menghabiskan satu slot IP + CPU inflate, lalu dibuang `quota`/`global_*`. Fase 19 menambah kuota keluarga di `reserveReplica` dengan pola sama dan mencatatnya sebagai kandidat fase 22 (`fase-19-replica-quota.md:191`). Byte replica bisa dihitung tepat dari panjang base64 tanpa decode (`len / 4 × 3 − jumlah '='`) | K12 → 22a-2 |

Kesimpulan: semua butir bisa dikerjakan di folder Alief (`backend/`, `ios/ShooApp/`, `plan/alief/`). Tidak ada perubahan kontrak. Satu usulan ke Umar: langkah CI ukuran bundle di `.github/workflows/backend.yml` (K11), digabung ke issue CI backend fase 21 K7 (pertanyaan 4). K4 (b) mengubah janji validasi replica fase 18 → dikabarkan di issue #176.

## Peta dampak (semua sisi)

| Sisi | File | Ubah | Sub-fase | Isi |
|---|---|---|---|---|
| Backend | `services/screenshotLinks.ts` | Ganti | 22a-1 | Cache `Promise<CryptoKey>` per `(secret, usage)` per isolate, gagal import tidak di-cache (pola `keyHash.ts:11-22`) |
| Backend | `http/validate.ts`, `routes/{devices,family,scans,verdicts,blocklist}.ts` | Ganti | 22a-1 | `import * as z from "zod"` (K2); tidak ada perubahan skema |
| Backend | `wrangler.jsonc` | Ganti | 22a-1 | `"minify": true`, `"upload_source_maps": true` (K3). `keep_names` tetap default |
| Backend | `services/images.ts` | Ganti | 22a-1 | `decodeBase64`: validasi regex + panjang tetap (`:9-10`), lalu `Uint8Array.fromBase64` kalau ada, else kode lama |
| Backend | `services/replicas.ts` | Ganti | 22a-2 | Sesuai K4; K12: cek kuota awal sebelum `hit(replicaIp)` dan decode |
| Backend | `db/repo/scans.ts` `precheckReplica` | Ganti (kalau K12 = a) | 22a-2 | Hitungan owner/keluarga/global ikut query pre-check yang sudah ada, tanpa lock; `reserveReplica` tetap penentu |
| Backend | `http/rateLimit.ts` | Ganti | 22a-3 | `hit` → satu `select rate_hit(...)` (K5) |
| DB | `backend/db/supabase/migrations/<ts>_rate_hit.sql`, `supabase/tests/rate_hit.test.sql` | Baru | 22a-3 | Fungsi `rate_hit(bucket, key_hash, max, window)` (advisory xact lock + count + insert dalam satu panggilan, `security invoker`, `grant execute` ke `shoo_api`); add-only |
| Backend test | `test/links-cache.test.ts` (baru), `test/images.test.ts`, `test/replicas.test.ts`, `test/rateLimit.test.ts`, `test/bundle.test.ts` (baru, opsional) | Baru/ubah | 22a | Lihat Output |
| Backend tooling | `backend/ci/bundle-size.mjs` (baru) | Baru | 22a-1 | Jalankan dry-run, cetak ukuran + paket terbesar, gagal di atas ambang (K11) |
| App | `Features/Detail/ReplicaSnapshot.swift` | Ganti | 22b | `imageWidth`/`windowHeight` sesuai K7; opsional tiling (K8) |
| App | `Features/Detail/ReplicaWebView.swift` | Hapus sebagian | 22b | Hapus `ReplicaWebView`, `scrollsToFocusOnFinish`, `scrollToFocus`, `focusOffset` (K9); `ReplicaWebController`, `LockedWebView`, `ReplicaRules` tetap |
| App | `Features/Detail/DetailView.swift` | Ganti | 22b | `Task.detached` → `nonisolated static func prepare(_:) async` |
| App | `Features/Detail/ReplicaLoader.swift` | Ganti (kalau S8 lambat) | 22b | Baca per potongan, satu salinan |
| App | `Components/SiteIcon.swift` | Ganti | 22c | Cache memori (K10) |
| App test | `Tests/PageCopyTests.swift`, `Tests/ReplicaViewTests.swift`, `Tests/ReplicaLoaderTests.swift`, `Tests/DetailPerfTests.swift` (baru, XCTest) | Ubah/baru | 22b | Lihat Output |
| Extension / kontrak | — | Tidak ada | — | Bentuk JSON tidak berubah. K4 (b) hanya mengubah sisi validasi server → kabar di #176 |
| CI | `.github/workflows/backend.yml` | **Usulan** (file Umar) | — | Issue K11 (= pertanyaan 4 issue CI backend fase 21 K7): langkah `node backend/ci/bundle-size.mjs` setelah "Worker build check" (`backend.yml:44-47`). Sampai dijawab: skrip dijalankan manual dan angkanya ditulis di PR |
| Privasi | — | Netral | — | Source map berisi kode kita saja (tanpa secret, gitleaks tetap jalan). Flamegraph hanya nama fungsi, tanpa isi request. Cache favicon (22c) memori saja, dibersihkan saat hapus/putus (P13) |
| Biaya Free | — | Turun | — | CPU lebih kecil; 22c mengurangi request `GET /favicons` (100k request/hari Free) |
| Dokumen | `plan/alief/log/fase-22.md`, `backend/README.md` (bagian "Performa"), `plan/alief/ARCHITECTURE.md` §3 (angka CPU nyata) | Baru/ubah | semua | Angka before/after, perintah ukur |

## Keputusan

**K1 — Target CPU (butuh Alief).** (a) p50 ≤ 10 ms per rute DB setelah 22a, p99 tanpa `exceededCpu`; `POST /scans` dengan replica tidak punya target angka, hanya "tidak naik". (b) ≤ 8 ms semua rute (target fase 18). (c) Hanya "tidak ada `exceededCpu`". Rekomendasi **(a)**, dengan catatan: kalau S2 membuktikan cold start masuk `cpuTime` dan dominan, target p50 dihitung dari request hangat saja. (b) tidak realistis selama tiap request membuka koneksi Postgres baru.

**K2 — Zod (butuh Alief).** (a) `import * as z from "zod"` (diff mekanis 6 baris, API sama, 763 → 182 KB di spike). (b) `zod/mini` (38 KB, API fungsional: `z.string().check(z.maxLength())`, tulis ulang semua skema). (c) Buang zod. Rekomendasi **(a)** sekarang; (b) hanya kalau S2 menunjukkan ukuran bundle masih dominan setelah (a).

**K3 — Minify + source map (butuh Alief).** (a) `minify: true` + `upload_source_maps: true`. (b) Tidak. Rekomendasi **(a)**: bundle lebih kecil, flamegraph produksi tetap terbaca (source map sudah default sejak wrangler 4.150.0, C10; ditulis eksplisit supaya tidak bergantung versi). `errorInfo` hanya memakai `err.name` (`http/logError.ts:5-8`), dan kelas error memakai nama eksplisit (`keyHash.ts:35-37`) atau `ApiError`; `keep_names` default wrangler tetap aktif, jadi log tidak berubah (dibuktikan `test/log-hygiene.test.ts`).

**K4 — Validasi replica (butuh Alief; kabar ke Umar di #176).** (a) Tetap inflate penuh ≤ 3 MB, tapi lebih murah: `fromBase64` (O4), slice 16 KB (maks ±16 MB output per langkah pada rasio ±1000:1, di bawah 128 MB memori Worker), yield `setTimeout(0)` **tetap** (C4: yield microtask meloloskan seluruh bom di workerd) sehingga putaran turun ±75 → ±19 untuk 300 KB. (b) Rencana B fase 18 K2: cek magic + panjang + inflate 64 KB pertama saja; batas 3 MB hanya di app (`ReplicaLoader.swift:25,57`, sudah ada). (c) Tetap. Rekomendasi **(a) dulu**, ukur; (b) hanya kalau `POST /scans` dengan replica masih > 50 ms p99 setelah (a). Risiko (b): objek R2 bisa berupa bom 300 KB → ratusan MB; satu-satunya pembaca adalah app (browser dapat 404 lewat `Sec-Fetch-*`, log fase 18), yang berhenti di 3 MB.

**K5 — Rate limit satu round trip (butuh Alief, setelah S3).** (a) Fungsi SQL `rate_hit()` (atomik dalam satu statement, advisory lock tetap). (b) Tetap transaksi. Rekomendasi: putuskan dari S3. Kalau porsi postgres.js < 20 % CPU request, **(b)**. Migrasi add-only; kode lama tetap jalan sampai deploy.

**K6 — Free vs Paid (butuh Alief).** (a) Tetap Free; pemicu pindah = `exceededResources` > 0 di GraphQL (alert fase 21) atau 1102 di laporan tester. (b) Pindah ke Workers Paid sekarang. Rekomendasi **(a)**: 81/81 request ok pada 31 Okt; fase 22 menurunkan risikonya. Langkah darurat kalau 1102 muncul: kill-switch `REPLICAS_ENABLED=false` (`wrangler.jsonc`) menghentikan inflate seketika; sisanya butuh Paid.

**K7 — Resolusi snapshot (butuh Alief, setelah S6).** Angka memori gambar (RGBA 4 B/px):

| Pilihan | Lebar gambar | Tinggi jendela | @3x (Pro Max) | @2x (SE) | Kartu 270 pt | Layar penuh 1× |
|---|---|---|---|---|---|---|
| Sekarang | 200 pt | 3000 pt | 600 × 4615 px ≈ 11 MB | 400 × 3077 ≈ 5 MB | buram (1,35×) | buram (≥ 1,9×) |
| (a) | 390 pt (= `renderWidth`) | 1800 pt | 1170 × 5400 ≈ 25 MB | 780 × 3600 ≈ 11 MB | tajam | tajam (1,13× di 440 pt) |
| (b) | 300 pt | 3000 pt | 900 × 6923 ≈ 25 MB | 600 × 4615 ≈ 11 MB | tajam | sedikit lunak |
| (c) | 390 pt | 3000 pt | 1170 × 9000 ≈ 42 MB | 780 × 6000 ≈ 19 MB | tajam | tajam |

Rekomendasi **(a)**: tajam di kedua tempat, memori sama dengan (b). Konsekuensi: halaman yang lebih panjang dari `leadIn` 600 pt + 1200 pt di bawah fokus terpotong; mark di luar jendela sudah dibuang (`ReplicaSnapshot.swift:108-113`). Gerbang: puncak footprint app saat membuka Detail ≤ baseline + 60 MB di simulator SE (S6).

**K8 — Web view tersembunyi (butuh Alief, setelah S7).** (a) Tetap satu frame setinggi jendela. (b) Tiling: frame tetap 844 pt, ambil snapshot per 844 pt sambil menggeser `contentOffset`, gabung dengan `UIGraphicsImageRenderer` → backing store WebContent kecil, gambar akhir sama. Rekomendasi: **(a)** kalau S7 menunjukkan footprint WebContent < 100 MB di SE; **(b)** kalau lebih atau ada `webViewWebContentProcessDidTerminate` saat uji.

**K9 — Kode mati `ReplicaWebView` (butuh Alief).** (a) Hapus `ReplicaWebView`, `scrollsToFocusOnFinish`, `scrollToFocus`, `focusOffset` dan test `focusOffsetStaysInsideThePage`. (b) Biarkan untuk "live view" masa depan. Rekomendasi **(a)**: K12 fase 18 sengaja memilih tanpa web view hidup di layar; git menyimpan versi lama.

**K10 — Cache favicon Activity (butuh Alief).** (a) `NSCache` di memori, kunci = id scan dari path `/favicons/<id>` (bukan URL bertanda tangan), ≤ 100 entri, dikosongkan saat hapus data (`DELETE /devices/me`), putus keluarga, ganti mode, dan memory warning (P13). (b) Tidak ada cache. Rekomendasi **(a)** sebagai 22c terpisah; bukan pemblokir.

**K11 — Gerbang ukuran bundle di CI (butuh Umar).** (a) Langkah CI baru (file Umar). (b) Test vitest yang membaca hasil dry-run. (c) Manual di PR. Rekomendasi **(a)** lewat issue; sambil menunggu, **(c)**. Tidak membuat issue baru: pertanyaan ini adalah butir 4 issue CI backend fase 21 K7 (`B9: CI backend — …`). Kalau issue itu sudah ada saat 22a-1, tambah komentar berisi angka `bundle-size.mjs`; kalau belum, buat issue gabungan itu dengan teks fase 21 K7.

**K12 — Cek kuota sebelum slot IP + inflate (butuh Alief, setelah 19a merge; kandidat dari fase 19).** (a) `precheckReplica` ikut menghitung pemakaian 24 jam owner, keluarga (akar keluarga fase 19 C1/K5.2 `coalesce(family_links.guardian_id, owner_id)`, urutan alasan fase 19 K4) dan global, plus byte replica dari panjang base64 (`len / 4 × 3 − jumlah '='`, tanpa decode; hanya kalau string lolos regex + panjang `images.ts:9-10`, selain itu cek byte dilewati dan `decodeReplica` tetap membuang `invalid`/`too_large` seperti sekarang); kalau salah satu sudah penuh → `dropped` dengan alasan yang sama (`quota`, `family_quota`, `family_bytes`, `reserve`, `global_quota`, `global_bytes`) **sebelum** `hit(replicaIp)` dan `decodeReplica`. Tanpa lock (sama seperti pre-check hari ini, `db/repo/scans.ts:187-188`); `reserveReplica` di bawah `(6, 0)` tetap penentu akhir, jadi balapan paling buruk = satu inflate sia-sia seperti sekarang. (b) Tetap: kuota hanya di `reserveReplica`. Rekomendasi **(a)**: satu agregat tambahan di query yang sudah berjalan vs inflate 3 MB + satu baris `rate_limit_hits`; penyerang yang kuotanya habis tidak lagi membakar CPU atau slot IP-nya. Event `replica_dropped` tidak berubah bentuk (antarmuka fase 19 K5.1 / fase 21 tetap). Test: owner/keluarga/global penuh → `DecompressionStream` tidak dipanggil (spy, pola test urutan fase 18) dan `rate_limit_hits` bucket `replicas_ip` tidak bertambah.

## Output

**22a-0 (tanpa kode produksi).** `plan/alief/log/fase-22.md`: tabel baseline per rute (lokal profiler, cloud tail, GraphQL p50/p99, flamegraph), hasil S1–S4. Skrip bantu ukur di `plan/alief/qa/cpu-bench.sh` (curl berurutan per rute ke `wrangler dev` atau cloud, memakai token device uji yang dibuat skrip sendiri, tidak mencetak token). Pola `replica-e2e.sh`: Guardian + Protected dipasangkan (`/family/code` + `/family/join`) supaya replica tidak dibuang `no_family` sebelum inflate; domain baru tiap scan replica (`bca-verifikasi-…-$RANDOM.site`) supaya tidak jatuh ke reuse 24 jam; `trap` menghapus semua device uji (`DELETE /devices/me`) di akhir. Batas yang harus dihormati: `createDevice` 10/jam/IP (`rateLimit.ts:12`) → `POST /devices` paling banyak 8 per run (2 dipakai keluarga), `replicaIp` 300/hari, owner 50 replica/24 jam (`replicas.ts:30`), `createScan` 120/jam.

**22a-1 `fix/BE-worker-cpu`.**
- O1 `services/screenshotLinks.ts`: `hmacKey` di-cache per `secret` + `usage` (Map kecil, ≤ 2 entri per secret; secret berganti → entri baru; import gagal → dihapus).
- O2 import zod (K2), O3 `wrangler.jsonc` (K3), O4 `services/images.ts` `decodeBase64` native dengan fallback.
- `backend/ci/bundle-size.mjs`: ukuran `index.js`, gzip, 5 paket terbesar; ambang awal = hasil setelah O2+O3 + 10 %.
- Test (merah dulu): `test/links-cache.test.ts` — (1) vektor emas: secret, scanId, viewer, `now` tetap → `sig` persis sama dengan implementasi lama (nilai dicatat dari `main` sebelum perubahan); (2) link lama tetap lolos `verifySignedLink`; (3) ganti secret → link dengan secret lama ditolak (cache tidak basi); (4) `importKey` dipanggil sekali untuk 50 link (spy `crypto.subtle.importKey`). `test/images.test.ts` — vektor `decodeBase64` (kosong, padding 0/1/2, karakter salah, panjang bukan kelipatan 4, tepat `maxBytes`, `maxBytes` + 1) identik di jalur native dan fallback (fallback dipaksa dengan menyembunyikan `Uint8Array.fromBase64`); satu test `typeof Uint8Array.fromBase64` mencatat apakah workerd lokal punya fitur itu. Seluruh suite lama (347 test) hijau tanpa diubah.

**22a-2 `fix/EX-07-replica-inflate` (sesuai K4 + K12).** `services/replicas.ts` `INFLATE_SLICE` 16 384, yield `setTimeout(0)` tetap. Test di `test/replicas.test.ts`: bom zero-gzip tetap `too_large` dengan `consumed` = 16 384 (satu slice; yield microtask menghasilkan 289 670 di workerd, C4); tepat 3 145 728 byte lolos, +1 byte `too_large`; gzip terpotong, trailer salah, byte setelah member → `invalid`; byte yang disimpan R2 identik dengan input. Kalau K4 = (b): test bom berubah menjadi "disimpan, tetapi hanya 64 KB pertama diperiksa", ditambah test app `overThreeMegabytesStops` tetap hijau. K12 (a): test kuota awal di K12 (owner, keluarga, global penuh → tanpa inflate, tanpa baris `replicas_ip`); test kuota lama tetap hijau.

**22a-3 `fix/BE-rate-limit-one-trip` (hanya kalau K5 = a).** Migrasi `rate_hit` dengan `revoke all on function rate_hit(...) from anon, authenticated, public, service_role` lalu `grant execute ... to shoo_api` (pola `20261021150000_blocklist_times.sql:28`, `20261022130000_security_review.sql:8-11`). pgTAP: batas tepat `max`, jendela geser, `retry` ≥ 1, `shoo_api` boleh execute, `anon`/`authenticated`/`service_role` tidak (`function_privs_are`). Di file lama `test/rateLimit.test.ts` ditambah satu test baru: `Promise.all` 2× `max` panggilan paralel → tepat `max` lolos (pgTAP satu sesi tidak bisa menguji paralel); test yang sudah ada di file itu tetap hijau tanpa diubah.

**22b `fix/DT-04-snapshot-perf`.**
- `ReplicaSnapshot.swift`: `imageWidth`/`windowHeight` sesuai K7, tiling kalau K8 = (b).
- `ReplicaWebView.swift`: hapus kode mati (K9).
- `DetailView.swift`: `nonisolated static func prepare(_ html: String) async -> (String?, ReplicaMeta?)` menggantikan `Task.detached` (di mode Swift 5, fungsi `nonisolated async` jalan di executor global, SE-0338; saat proyek pindah ke Swift 6.2 dengan `NonisolatedNonsendingByDefault`, tandai `@concurrent`).
- `ReplicaLoader.swift` (kalau S8 > 100 ms di SE): satu buffer, tanpa `Data` perantara.
- Test: `PageCopyTests` — lebar gambar = `imageWidth` baru, tinggi = `min(windowHeight, content)` × skala (ubah `:230-231`); mark tetap di tempat yang sama relatif ke elemen (test `shifted` lama). `ReplicaViewTests` — navigasi tetap ditolak (`:127`). `ReplicaLoaderTests` — semua test batas dan non-UTF-8 tetap hijau. `DetailPerfTests.swift` (XCTest, hanya jalan dengan `TEST_RUNNER_SHOO_PERF=1` di lingkungan `xcodebuild`; awalan `TEST_RUNNER_` dibuang, jadi test membaca `ProcessInfo.processInfo.environment["SHOO_PERF"] == "1"` dan `throw XCTSkip` kalau tidak ada; pola sama dengan fase 23 K3 (b)): `measure(metrics: [XCTMemoryMetric(), XCTClockMetric(), XCTCPUMetric()])` untuk `ReplicaSnapshot.render` dengan HTML fixture 3 MB, dan untuk `URLSessionReplicaLoader.html(at:)` dengan stub 3 MB. `DetailUITests.testPageCopyShowsWithItsLine` tetap hijau (tidak ada web view hidup di layar).
- Screenshot before/after: Detail fixture `blocked92` dengan `-debug.replicaFixture YES`, kartu + layar penuh 1× + zoom 2,5× (double-tap), di "Shoo QA SE" (`$SE_ID`) dan iPhone 17 Pro Max (`$PM_ID`, C19) → `plan/alief/qa/img/fase-22/`.

**22c `fix/PR-05-favicon-cache` (opsional, K10).** `SiteIcon.swift` cache; test: dua URL bertanda tangan berbeda untuk scan yang sama → satu unduhan (stub `FaviconLoading` menghitung panggilan); setelah `clear()` → unduh lagi.

## Langkah kerja

### 22a-0 — baseline (tanpa perubahan kode produksi)

1. **S1 profil lokal.** `supabase start` (`backend/db`), `pnpm -C backend/api dev`, tekan `d` di terminal wrangler → DevTools → Profiler → Start. Jalankan `bash plan/alief/qa/replica-e2e.sh --bench` (sudah ada) dan `plan/alief/qa/cpu-bench.sh` (baru, aturan di Output 22a-0: 20× `GET /healthz`, 8× `POST /devices` (batas 10/jam/IP), 20× `GET /scans`, 20× `POST /scans` tanpa replica, 20× dengan replica terburuk dari `replica-input.mjs` oleh Protected yang punya keluarga, domain baru tiap kali). Lokal boleh lebih banyak `POST /devices` setelah mengosongkan `rate_limit_hits` (`docker exec -i supabase_db_shoo psql -U postgres -c "delete from rate_limit_hits"`), tidak pernah di cloud. Stop, simpan `.cpuprofile` di scratchpad (bukan repo: bisa memuat string body). Catat 10 fungsi teratas per rute di `log/fase-22.md`. Catatan: `cpu_time_ms` workerd lokal selalu 0 (log fase 18), jadi angka lokal = proporsi, bukan ms cloud.
2. **S2 cold vs warm (cloud, LANGKAH MANUAL 2).** Setelah ≥ 10 menit tanpa trafik: 10× `GET /healthz` berurutan (tanpa DB, `routes/health.ts:7`) dengan `wrangler tail --format json` terbuka; bandingkan `cpuTime` request pertama vs sisanya. Ulangi setelah 22a-1 deploy. Selisih besar yang turun setelah O2+O3 = cold start memang terhitung.
3. **S3 porsi DB.** Dari profil S1: total waktu di modul `postgres` (`connection.js`, `bytes.js`, `result.js`) per request `POST /devices`. Kalau ≥ 20 % → K5 (a) layak. Juga cek di flamegraph produksi (LANGKAH MANUAL 3) apakah ada `SASLContinue`/`pbkdf2Sync` (= Hyperdrive meminta SCRAM).
4. **S4 baseline cloud.** GraphQL `workersInvocationsAdaptive` 24 jam: `cpuTimeP50`, `cpuTimeP99`, status (query di fase 21 C9) → tabel di log. Flamegraph CPU produksi 10 s selama `cpu-bench.sh --cloud` (LANGKAH MANUAL 3).
5. Tulis hasil + rekomendasi final K1/K4/K5 di `log/fase-22.md`, minta jawaban Alief.

### 22a-1 — `fix/BE-worker-cpu`

6. Catat vektor emas link dari `main` (satu skrip kecil di test memakai `signedLink` lama, nilai ditempel ke test). Tulis `test/links-cache.test.ts` + test `decodeBase64` → jalankan, test spy importKey **merah**.
7. O1 cache kunci → hijau. O4 `fromBase64` + fallback → hijau.
8. O2 ganti 6 import zod. `pnpm -C backend/api run typecheck` + seluruh suite → hijau tanpa ubah test.
9. O3 `wrangler.jsonc` minify + source map. `npx wrangler deploy --dry-run --outdir` → catat ukuran sebelum/sesudah. `node backend/ci/bundle-size.mjs`.
10. Profil lokal ulang (S1) → tabel before/after di log. Review berurutan (`ecc:performance-optimizer` → `ecc:typescript-reviewer` → `ecc:security-reviewer`). PR (reviewer @umarmuhdhor), merge, deploy lewat CI.
11. LANGKAH MANUAL 2 + 4 ulang (S2, S4) → before/after cloud di log.
12. K11 ke Umar lewat issue CI backend fase 21 K7 (komentar angka bundle, atau buat issue gabungan kalau belum ada).

### 22a-2 — `fix/EX-07-replica-inflate` (kalau K4 = a atau b, atau K12 = a)

13. Test bom + batas (lihat Output) diperketat dulu (merah untuk `consumed` baru) → ubah `INFLATE_SLICE` (yield `setTimeout` tetap) → hijau. Kalau K12 = (a): test kuota awal merah → hitungan di `precheckReplica` + drop sebelum `hit(replicaIp)` → hijau. `bash plan/alief/qa/replica-e2e.sh` lokal lulus. Kalau (b): komentar di #176 sebelum merge.
14. Review, PR, merge, `replica-e2e.sh --cloud --bench` (LANGKAH MANUAL 4).

### 22a-3 — `fix/BE-rate-limit-one-trip` (kalau K5 = a)

15. pgTAP `rate_hit.test.sql` merah → migrasi → `supabase test db` hijau → `rateLimit.ts` `hit` memanggil fungsi → `test/rateLimit.test.ts` hijau tanpa diubah. Review `ecc:database-reviewer` termasuk. Deploy lewat CI (migrasi dulu, lalu Worker, `.github/workflows/backend.yml:74-84`).

### 22b — `fix/DT-04-snapshot-perf` (setelah #204 + #205 merge)

16. **S5 strict concurrency.** `source plan/alief/ref/sim.sh` lalu `xcodebuild build -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" SWIFT_STRICT_CONCURRENCY=complete 2>&1 | grep -E "Features/Detail/.*warning"` → daftar peringatan nyata untuk `Race` dan Detail (C15) di log.
17. **S6 memori app.** Build `main`, buka Detail fixture (`-UITestMock YES -debug.detail 6f1c2a4e-3b8d-4c1a-9e2f-0a1b2c3d4e03 -debug.replicaFixture YES`) di SE dan Pro Max; Instruments → Allocations + VM Tracker (proses app), atau log sementara `os_proc_available_memory()` sebelum/sesudah `render` (hanya Debug, tidak di-commit). Catat puncak footprint. Fixture replica 3 MB untuk kasus terburuk: perpanjang `FixtureReplicaLoader` hanya di test perf.
18. **S7 memori WebContent.** Selama render, `footprint <pid>` untuk proses `com.apple.WebKit.WebContent` simulator (proses macOS), atau Instruments "All Processes". Catat puncak.
19. **S8 loader.** `DetailPerfTests` untuk `ReplicaLoader` 3 MB → CPU + waktu di simulator SE; kalau ada iPhone fisik, sekali di device (Debug).
20. Screenshot **before** (SE + Pro Max, kartu, layar penuh 1×, zoom 2,5×) dari `main`.
21. Jawaban K7–K9. Ubah test `PageCopyTests` ke ukuran baru (merah) → ubah `ReplicaSnapshot` → hijau. Hapus kode mati (K9) → `ReplicaViewTests` hijau. `prepare` `nonisolated async` → test pembatalan: Detail ditutup saat `prepare` jalan → tidak ada `render` (hitung panggilan lewat test double). Loader (kalau S8) → `ReplicaLoaderTests` hijau.
22. Ulang S5–S8 → tabel after. Screenshot **after**. Review berurutan (`ecc:swift-reviewer` → `ecc:security-reviewer`), PR dengan before/after + tabel memori.

### 22c — `fix/PR-05-favicon-cache` (opsional)

23. Test hitungan unduhan (merah) → cache + hook pengosongan → hijau. Screenshot Activity before/after (tampilan sama; bukti tidak ada regresi). PR.

## LANGKAH MANUAL

- [ ] 1. (Alief, lokal) Tidak perlu membuat simulator: pakai "Shoo QA SE" `483B28B6-913A-4C3A-8A4C-0C7219022682` dan iPhone 17 Pro Max `4FBB910B-DA84-4552-B174-28396BD496DB` (C19). Cek dulu masih ada: `xcrun simctl list devices | grep -E "483B28B6|4FBB910B"`.
- [ ] 2. (Alief, cloud) S2: diam ≥ 10 menit, lalu `npx wrangler tail shoo-api --format json` di satu terminal dan 10× `curl -s https://shoo-api.afindo-mi01.workers.dev/healthz` di terminal lain. Salin hanya `cpuTime`, `wallTime`, `outcome` ke log (jangan URL/header). Ulangi setelah deploy 22a-1.
- [ ] 3. (Alief, dashboard) Flamegraph produksi: Workers & Pages → `shoo-api` → Observability → Flamegraph → CPU, durasi 10 000 ms, Latest → Capture, sambil `bash plan/alief/qa/cpu-bench.sh --cloud`. Download pprof ke folder lokal di luar repo; simpan screenshot flamegraph (hanya nama fungsi) di `plan/alief/qa/img/fase-22/`. Setelah 22a-1 (source map aktif) ulangi.
- [ ] 4. (Alief, cloud) Setelah tiap deploy 22a: `SHOO_API=https://shoo-api.afindo-mi01.workers.dev bash plan/alief/qa/replica-e2e.sh --cloud --bench` dengan `wrangler tail` terbuka → tanpa 1102/`exceededCpu`; GraphQL p50/p99 24 jam setelah deploy ke log.
- [ ] 5. (Alief, GitHub) K11 di issue CI backend fase 21 K7 (judul `B9: CI backend — workflow ops-watch, environment ops, langkah backend.yml`, pertanyaan 4): komentar dengan angka `bundle-size.mjs`, atau buat issue itu (template question, label `question`, assign @umarmuhdhor) kalau belum ada. Sampai dijawab: angka `bundle-size.mjs` ditulis manual di deskripsi PR backend.
- [ ] 6. (Alief, GitHub) Kalau K4 = (b): komentar di #176 (rencana B fase 18 K2 dipakai, batas 3 MB hanya di app) + catat di `log/DECISIONS.md`.
- [ ] 7. (Alief, device, opsional) Kalau ada iPhone fisik dengan RAM kecil: buka Detail dengan replica terburuk 5×, cek tidak ada jetsam (Xcode → Devices → Device Logs `JetsamEvent`).

## Verifikasi

```bash
# backend
(cd backend/db && supabase start && supabase test db)
pnpm -C backend/api run typecheck
pnpm -C backend/api test
pnpm -C backend/api exec vitest run links-cache images replicas scans favicons screenshots rateLimit log-hygiene   # `screenshots` hilang setelah fase 20b, filter lain tetap
(cd backend/api && npx wrangler deploy --dry-run --outdir "${TMPDIR:-/tmp}/shoo-worker" && ls -la "${TMPDIR:-/tmp}/shoo-worker")
node backend/ci/bundle-size.mjs
bash plan/alief/qa/replica-e2e.sh            # wrangler dev lokal
bash plan/alief/qa/cpu-bench.sh              # profil S1 (DevTools terbuka)

# app
source plan/alief/ref/sim.sh
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:ShooAppTests/PageCopyTests -only-testing:ShooAppTests/ReplicaViewTests -only-testing:ShooAppTests/ReplicaLoaderTests -only-testing:ShooAppTests/ReplicaHTMLTests -only-testing:ShooAppTests/DetailModelTests
xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" -only-testing:ShooAppUITests/DetailUITests
SE_ID=483B28B6-913A-4C3A-8A4C-0C7219022682; PM_ID=4FBB910B-DA84-4552-B174-28396BD496DB   # C19
TEST_RUNNER_SHOO_PERF=1 xcodebuild test -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SE_ID" -only-testing:ShooAppTests/DetailPerfTests
xcodebuild build -project ios/Shoo.xcodeproj -scheme Shoo -destination "platform=iOS Simulator,id=$SIM_ID" SWIFT_STRICT_CONCURRENCY=complete 2>&1 | grep -c "Features/Detail/.*warning"   # 0 setelah 22b
```

## Kriteria selesai (DoD)

- [ ] `log/fase-22.md` berisi baseline dan after per rute: profil lokal (10 fungsi teratas), `cpuTime` tail cold/warm (S2), GraphQL p50/p99 24 jam, screenshot flamegraph.
- [ ] Bundle `index.js` turun dari 1,0 MB (angka pasti dicatat); zod tidak lagi membawa 64 file locale.
- [ ] Link favicon/replica (dan screenshot selama fase 20b belum merge) identik byte-per-byte dengan vektor emas `main`; `importKey` sekali per isolate per secret (test spy).
- [ ] `decodeBase64` lolos vektor yang sama di jalur native dan fallback.
- [ ] Semua test backend lama hijau tanpa diubah (kecuali yang memang diganti di 22a-2/22a-3 dan disebut di PR).
- [ ] Target K1 tercapai di GraphQL 24 jam setelah deploy, dan nol `exceededResources` / 1102.
- [ ] K12 (a): owner/keluarga/global penuh → `replica_dropped` dengan alasan yang sama tanpa `DecompressionStream` dan tanpa baris `replicas_ip` baru (test), atau K12 ditolak dan alasannya dicatat di `log/fase-22.md`.
- [ ] 22b: gambar salinan sesuai K7 (test ukuran), puncak footprint app saat Detail ≤ baseline + 60 MB di SE simulator, footprint WebContent tercatat, nol peringatan strict concurrency di `Features/Detail/`, kode mati K9 hilang (grep `ReplicaWebView(` = 0), pembatalan `prepare` dibuktikan test.
- [ ] Screenshot before/after SE + Pro Max (kartu, layar penuh 1×, zoom 2,5×) di PR 22b.
- [ ] K11 tercatat di issue CI backend fase 21 K7 (pertanyaan 4) dan nomornya ditulis di log + PR.

## Risiko & rollback

| Risiko | Dampak | Mitigasi | Rollback |
|---|---|---|---|
| Cache kunci HMAC memakai secret lama setelah rotasi | Link ditolak/diterima salah | Kunci cache = nilai secret; test rotasi | Revert PR 22a-1 (deploy CI) |
| `minify` mengubah nama error di log | Log kurang jelas | `keep_names` default, `test/log-hygiene.test.ts` | Hapus `minify` dari `wrangler.jsonc` |
| `import * as z` mengubah perilaku zod | 422 berbeda | API sama; seluruh suite tanpa ubah test | Revert 6 baris |
| `Uint8Array.fromBase64` beda dengan `atob` di tepi | Replica/screenshot dibuang atau diterima salah | Validasi regex + panjang lama tetap di depan; vektor identik; fallback | Hapus jalur native |
| Slice inflate lebih besar → memori puncak naik | OOM Worker (128 MB) | 16 KB × ±1000 = ±16 MB; yield `setTimeout` tetap (microtask meloloskan seluruh bom, C4); test bom `consumed` = 16 384 | `INFLATE_SLICE` kembali 4096; kill-switch `REPLICAS_ENABLED=false` |
| K4 (b): bom tersimpan di R2 | App berhenti di 3 MB, objek tetap makan kuota byte | Kuota byte global fase 18/19 + retensi | Kembali ke (a) |
| `rate_hit` salah hitung paralel | Rate limit bocor | pgTAP paralel; advisory lock sama | Migrasi add-only: revert kode Worker saja, fungsi dibiarkan |
| Gambar lebih tajam = memori naik | Jetsam di iPhone lama | Gerbang +60 MB SE; tiling K8 (b) | Revert konstanta `imageWidth`/`windowHeight` |
| Jendela 1800 pt memotong halaman panjang | Bukti di bawah jendela hilang | Jendela tetap berpusat di `focusY` dengan `leadIn`; mark di luar sudah dibuang hari ini | Naikkan `windowHeight` |
| Cloudflare menegakkan 10 ms sebelum fase 22 selesai | 1102 di onboarding/pairing/scan | Alert fase 21; K6 | Workers Paid (keputusan Alief) |

## Catatan handoff

- Pengukuran CPU **tidak boleh** memakai `performance.now()` di produksi (timer hanya maju saat I/O). Jangan menambah "span debug" ke kode Worker; pakai profiler lokal, `wrangler tail`, GraphQL, flamegraph.
- Bench Node 31 Okt (scratchpad, bukan workerd): import zod ±31 ms CPU; body 381 KB → decode + `JSON.parse` 0,2–0,3 ms, zod 0,2–2,4 ms; `atob` + loop 1,8–5,8 ms vs `fromBase64` 0,03 ms; 20 link HMAC 2,8–8,1 ms vs 0,2–0,7 ms dengan kunci di-cache; PBKDF2 4096 0,8 ms. Angka ini indikasi; angka penentu dari cloud.
- `APNS_TOPIC` masih kosong di `wrangler.jsonc:32`: setelah diisi (TODO B7), ES256 jalan sekali per isolate per 50 menit; ukur ulang S2 saat itu.
- Usulan TODO baru untuk `TODO.md` (tidak diubah di fase ini): "E-perf: CPU Worker per rute di bawah K1" dan "launch time app (XCTApplicationLaunchMetric)" — launch time sengaja tidak masuk fase 22 karena belum ada bukti masalah.
- Fase 19 dan 22a-2 sama-sama menyentuh `services/replicas.ts` dan `test/replicas.test.ts`: kerjakan 22a-2 setelah 19a merge.
- 22b memakai baris dari `main` 31 Okt. Setelah #204 merge (dicek dengan `git show origin/fix/DT-04-replica-hardening:<file>` 31 Okt): `DetailView.swift` `loadPageCopy` 346 → 348, `Task.detached` 359 → 361, `fullScreenCover` 59 → 63; `ReplicaSnapshot.swift` `Race` 150 → 152 (`imageWidth`/`windowHeight` tetap 28/23); `ReplicaWebView.swift` `scrollToFocus` 155 → 156, `struct ReplicaWebView` 167 → 168; `ReplicaLoader.swift` tetap 55/62.
- Fase 20b vs 22a-1 O1: kalau 20b (rename `services/screenshotLinks.ts` → `services/signedLinks.ts`, kind `screenshot` dihapus) sudah merge saat 22a-1 mulai, cache kunci ditulis di `signedLinks.ts` dan vektor emas hanya `favicon` + `replica`. Kalau 22a-1 lebih dulu, 20b memindah file beserta cache dan `test/links-cache.test.ts` (import diubah, vektor `screenshot` dihapus bersama kind-nya). Fase 20d vs 22b/22c (app): 20d memindah `ZoomedScreenshot` → `Features/Detail/ZoomedPage.swift` dan `configuration()` → `Support/EvidenceSession.swift`, dan mengganti nama helper di `ReplicaLoader.swift:26,33` + `SiteIcon.swift` (`fase-20-screenshot-sunset.md:107,112`). Kalau 20d merge lebih dulu, rujukan C11/C17 `ScreenshotView.swift:36-44,140,146-151` dibaca di file baru itu; kalau 22b/22c lebih dulu, 20d rebase. Jangan kerjakan 22b dan 20d paralel di file yang sama.

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 14 temuan (0 kritis, 0 tinggi, 6 sedang, 8 rendah); diperbaiki: K4 (a) tidak lagi membuang `setTimeout(0)` (uji `workerd serve` lokal: yield microtask meloloskan seluruh bom 289 670 byte, `setTimeout` berhenti di 16 384) + test/risiko ikut; kandidat fase 19 (keluarga/global penuh tetap memakai slot `replicaIp` + CPU inflate) masuk C20 + K12 baru (cek kuota di `precheckReplica` sebelum slot IP dan decode, `reserveReplica` tetap penentu) beserta Peta, Urutan, Output, Langkah 13, DoD; "Fase berikutnya" disamakan dengan fase 21 (alert `exceededResources` > 0, tanpa ambang `cpuTimeP99`); simulator "Shoo QA SE"/17 Pro Max lewat UDID (bukan membuat simulator baru, `name=` ambigu); urutan dengan fase 20b (rename `signedLinks.ts`, kind `screenshot` hilang); `cpu-bench.sh` menghormati `createDevice` 10/jam/IP, memakai keluarga + domain baru agar inflate benar-benar terukur, dan menghapus device uji; rendah: sumber angka `wrangler tail` (#205, belum di `main`), kutipan timer + 128 MB, `fromBase64` terverifikasi di workerd lokal, source map default wrangler ≥ 4.150.0 + Flamegraph di Free belum pasti, `rateLimit.test.ts` file lama + `revoke`/`grant` fungsi, `SHOO_PERF` + `XCTSkip`, pergeseran baris setelah #204, `/ops/status` di C5; dicatat tanpa diubah: tidak ada. Tidak ada fase lain yang merujuk nomor baris file ini.
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang; 1 temuan rendah (rumus byte K12 hanya sah untuk base64 yang lolos regex), diperbaiki; 0 kritis/tinggi/sedang. Belum terverifikasi: ukuran bundle 1,0 MB/zod 789 KB (dry-run tidak bisa tanpa `node_modules` di worktree), startup masuk `cpuTime` (S2), porsi CPU postgres.js (S3), SCRAM lewat Hyperdrive, Flamegraph di Free, `fromBase64` di runtime cloud, memori WebContent (S7), peringatan strict concurrency (S5).
- Cek lintas fase (1 Nov 2026): #204 dan #205 MERGED 31 Okt 15:40 UTC → prasyarat 22b terpenuhi, sumber angka CPU (`log/fase-18.md:92`) dan catatan "Ditunda" (`:131`) kini di `main` (Prasyarat, Requirement, Tujuan, Bacaan wajib); K11 tidak lagi issue sendiri tetapi pertanyaan 4 issue CI backend fase 21 K7 (Langkah 12, LANGKAH MANUAL 5, Peta, DoD); K12 merujuk akar keluarga fase 19 C1/K5.2 (bukan K4, yang mengatur urutan alasan); urutan file app dengan fase 20d (`ScreenshotView.swift` dipecah, helper `ReplicaLoader`/`SiteIcon` diganti nama) di Catatan handoff. Baris `:168` (dirujuk fase 23) tetap.
