# Fase 25 — Verdict realtime menggantikan polling (TODO E3)

| Field | Nilai |
|---|---|
| Track | c (ukur dulu, lalu backend; bagian extension = kode Umar lewat issue) |
| Branch | 25-0 tanpa branch (baseline, hasil ke `log/fase-25.md`) · 25a-be `feat/EX-06-verdict-latency-log` (backend: log latensi tanpa id) · 25a-ext **milik Umar** (polling adaptif di `blocked-page.js`, lewat issue Q1) · 25b `spike/EX-06-verdict-live` (backend: Durable Object + WebSocket di belakang flag `LIVE_VERDICTS=off`, tidak di-merge sebelum go/no-go) · 25c `feat/EX-06-verdict-live` (backend produksi, setelah go dan jawaban Umar Q2–Q4) |
| Prasyarat | 25-0/25a-be: tidak ada. 25b: jawaban issue Umar Q2 (boleh tidaknya WebSocket dibuka dari `blocked.html`). 25c: spike lolos (DoD 25b) + kontrak baru di `contracts/api.md` di-merge Umar + extension Umar memakai endpoint baru |
| Urutan | 25-0 baseline (M1–M5) → issue Umar (Q1–Q5) → 25a-be → 25a-ext (Umar) → ukur ulang → 25b spike (lokal + 1 device) → go/no-go (K8) → 25c → ukur ulang → flag `on` |
| Requirement | TODO E3 (`TODO.md:103`), EX-06 (buka blokir otomatis), GD-07 (verdict), ARCHITECTURE §3 (batas Free) + §4 butir 4 (target ≤ 10 s, `ARCHITECTURE.md:78`), SECURITY §1 (`SECURITY.md:16`: tidak ada kunci Supabase di extension), §3 P6, P13 |
| Model + reviewer ECC | Opus 5.5 · 25a-be: `ecc:typescript-reviewer` · 25b/25c: `ecc:security-reviewer` → `ecc:typescript-reviewer` → `ecc:performance-optimizer` (satu per satu, tidak paralel) |
| Fase berikutnya | Tidak ada yang menunggu fase 25. Fase 21 (monitoring) membaca GraphQL + `/ops/status`, bukan log (alert dari log belum terverifikasi, fase 21 C7), jadi `verdict_seen` dibaca manual lewat `wrangler tail` (LANGKAH MANUAL 7). Sinyal kuota otomatis yang sudah ada: `worker_requests_high` ≥ 80 000/hari (`fase-21-monitoring.md:134`); query Hyperdrive dan pemakaian DO **tidak** dipantau fase 21 → M3 manual (LANGKAH MANUAL 6). Usulan setelah 25c: tambah dataset GraphQL DO ke skrip 21b (PR terpisah, bukan bagian fase ini) |

## Tujuan

**Masalah.** Layar blokir menunggu keputusan Guardian dengan polling tetap 5 s:

- `blocked-page.js:6` `POLL_MS = 5000`, `:124-146` loop `poll()` → `send({ type: "verdict", fresh: true })` (`:129`) → background `verdicts.lookup` (`background.js:89`, handler `:187-188`) → `GET /verdicts?domain=` dengan `Authorization: Bearer` (`verdicts.js:40-41`, header di `background.js:51`). `fresh` melewati cache 60 s (`verdicts.js:5,34`).
- Polling jalan untuk **dua mode** (`blocked-page.js:29` `poll: mode !== null`), berhenti hanya saat `safe` (`:134-136`) atau `not_safe` (`:138-143`). Tidak ada batas waktu, tidak ada backoff selain `Retry-After` saat 429 (`:34-36`).
- Kembali ke tab → poll langsung (`:149-151`). Ini sudah bagus dan dipertahankan.
- Chrome punya salinan yang sama (`chrome/extension/blocked-page.js:7`), juga milik Lead.
- Kontrak mewajibkan angka 5 s dan sudah membuka pintu usulan: "Realtime instead of polling: propose via PR." (`contracts/api.md:83`).

**Biaya per request** `GET /verdicts` di backend: `findByTokenHash` (`http/auth.ts:17`) + `hitLight` satu statement (`routes/verdicts.ts:58`, `http/rateLimit.ts:55`) + `findVerdict` (`db/repo/verdicts.ts:140-146`) = **3 query Hyperdrive** (+ `touchLastSeen` tiap > 5 menit, `auth.ts:42`). Rate limit 30 / 10 s per device (`rateLimit.ts:41`). Satu layar blokir terbuka = **12 request/menit = 36 query/menit**. Batas Free: 100 000 request Worker/hari dan 100 000 query Hyperdrive/hari (`ARCHITECTURE.md:62-63`) → ±2 800 menit layar blokir terbuka per hari menghabiskan kuota query, di luar trafik lain. Hyperdrive yang habis lebih dulu (3 query/GET → ±33 000 GET/hari, jauh sebelum 100 000 request Worker); lewat kuota = query gagal dengan error sampai reset 00:00 UTC (developers.cloudflare.com/hyperdrive/platform/pricing, dibaca 31 Okt 2026). Tiap `GET` juga menulis satu baris `rate_limit_hits` (`rateLimit.ts:66`), dibersihkan retensi ≤ 1 juta baris/run (`cron/retention.ts:38-40,130-135`).

**Latensi sekarang.** Tap Aman → `POST /verdicts` commit → poll berikutnya (rata 0–5 s) + RTT + `location.replace`. Perkiraan teoritis: p50 ±2,5 s + RTT, p95 ±4,75 s + RTT (belum diukur; M1 di 25-0).

**App tidak polling verdict.** Grep `ios/ShooApp`: tidak ada loop verdict. `DetailModel.waitForCopy()` (`DetailModel.swift:154`) hanya mengulang `GET /scans/{id}` 2× (`copyRetryDelays` 3 s, 12 s, `:48`) untuk `pageReplicaUrl`; Shield/Activity hanya `.refreshable` (tarik manual, mis. `ProtectedShieldView.swift:50`). Jadi fase ini **tidak mengubah app**.

**Hasil akhir.**
1. Guardian tap Aman/Bahaya → layar blokir Protected berubah **p95 ≤ 1,5 s** (target ~1 s) selama tab terlihat.
2. Request per layar blokir terbuka turun dari 12/menit ke **≤ 2/menit** (realtime aktif) atau mengikuti jadwal adaptif (fallback).
3. Tidak ada identifier baru, token tidak pernah di URL, tidak ada kunci pihak ketiga di extension, semua dalam batas Free.
4. Gagal apa pun di jalur realtime → kembali ke polling, tidak pernah "terbuka tanpa verdict".

## Bacaan wajib

- Extension (Lead, baca saja): `ios/ShooExtension/Resources/{blocked-page.js, verdicts.js, background.js, manifest.json, block.js}`, `ios/ShooExtension/Tests/verdicts.test.mjs`, `ios/ShooExtension/SafariWebExtensionHandler.swift`, `ios/ShooExtension/CLAUDE.md`
- Kontrak: `contracts/api.md:77-85` (Verdicts), `:14-15` (429 + `Retry-After`), `contracts/app-group-keys.md`
- Backend: `src/routes/verdicts.ts`, `src/db/repo/verdicts.ts`, `src/http/{auth,rateLimit}.ts`, `src/services/screenshotLinks.ts` (pola HMAC link, `:17-18`), `src/services/push/apns.ts`, `wrangler.jsonc`, `vitest.config.ts`, `test/verdicts.test.ts`, `backend/API.md` "Verdicts"
- Plan: `ARCHITECTURE.md` §3–§4, `SECURITY.md` §1 + §3, fase 10 (verdict), fase 21 (monitoring), fase 22 (biaya per request)
- Dokumen eksternal (dikutip di Cek kelayakan): Cloudflare DO pricing, DO WebSockets, Workers limits, Hyperdrive supported features, Supabase Realtime limits/pricing, Apple background push, WWDC21 10027

## Cek kelayakan

Kode diverifikasi terhadap `main` 2720b13 (31 Okt 2026). Fakta Free tier dibaca 31 Okt 2026 dari dokumen resmi (URL di kolom temuan).

| # | Butir | Bisa? | Temuan (kode `file:baris` / dokumen) | Tindakan |
|---|---|---|---|---|
| C1 | Background page extension bisa memegang koneksi lama | **Tidak andal** | `manifest.json:17-21` `"persistent": false`. WWDC21 10027: di iOS background page wajib non-persistent dan di-unload saat tidak ada pesan. Forum Apple (thread 790310): unload sering di iOS 17.4+. Tidak ada angka resmi berapa detik | WebSocket/long-poll **tidak** ditaruh di `background.js` |
| C2 | Halaman blokir (`blocked.html`) bisa membuka WebSocket | Belum terverifikasi | `blocked.html` = halaman extension (`web_accessible_resources`, `manifest.json:29-32`), `host_permissions: <all_urls>` (`:35`), manifest tanpa `content_security_policy` (default MV3 tidak membatasi `connect-src`). Saat tab tersembunyi, iOS membekukan/menutup koneksi (bukti tidak langsung: gist 2052006 ±1 menit). Pemulihan saat kembali sudah ada (`blocked-page.js:149-151`). **Aturan Lead:** "Every network call goes through `background.js`" (`ShooExtension/CLAUDE.md:21`) dan tidak ada balasan `runtime.onMessage` yang membawa token **atau base URL** (`:24`; `profile` hanya onboarded/mode/guardianName, `background.js:170-176`). Socket di `blocked-page.js` butuh URL `wss://` + tiket di halaman → melanggar dua aturan itu kecuali Umar membuat pengecualian | Spike S2 di device oleh Umar (Q2), dan Q2 sekaligus meminta pengecualian aturan `:21`/`:24` (hanya tiket 60 s + URL `wss://…/verdicts/live`, tidak pernah token). Realtime hanya dikejar saat tab terlihat; itu memang satu-satunya saat Protected menatap layar |
| C3 | Token tidak di URL | Ya, dengan tiket | API `WebSocket` browser tidak bisa set header `Authorization`. `EventSource` juga tidak. Satu-satunya header yang bisa diisi = `Sec-WebSocket-Protocol` | Tiket HMAC 60 s di subprotocol (K4). Nilai subprotocol harus token HTTP (RFC 6455 §4.1): tiket = `<payload base64url>.<sig base64url>` tanpa `=`. `invocation_logs: false` (`wrangler.jsonc:11`) jadi header tidak tercatat |
| C4 | (1) Durable Objects + WebSocket Hibernation di Free | Ya | developers.cloudflare.com/durable-objects/platform/pricing: DO tersedia di Workers Free, **hanya kelas SQLite**; 100 000 request/hari, 13 000 GB-s durasi/hari, 5 jt baris dibaca, 100 000 baris ditulis/hari, 5 GB. WebSocket connect = 1 request; pesan masuk ditagih 20:1; pesan keluar + ping protokol gratis; objek idle yang layak hibernasi tidak ditagih durasi; `setWebSocketAutoResponse` tanpa biaya wall-clock. Lewat kuota harian = operasi jenis itu gagal dengan error sampai reset 00:00 UTC. `.../platform/limits`: maks 32 768 WebSocket per DO (Hibernation API, `.../api/state`). `.../best-practices/websockets`: klien tetap terhubung saat DO hibernasi; alarm, request masuk, dan `setTimeout` mencegah hibernasi (jadi nonce dibersihkan malas, bukan alarm, K4). `wrangler.jsonc` belum punya `durable_objects` (`:12` hyperdrive, `:45` r2 saja). `vitest.config.ts` memakai `@cloudflare/vitest-plugin` (`package.json:17`) → DO bisa diuji lokal, **tetapi** known issue resmi (`.../workers/testing/vitest-integration/known-issues`): WebSocket ke DO tidak didukung dengan isolasi storage per file; jalan keluarnya `--max-workers=1 --no-isolate` (Langkah 25b, Verifikasi). `placement: smart` (`wrangler.jsonc:51`) hanya berlaku untuk handler `fetch` Worker, bukan lokasi DO; lokasi DO tidak dijelaskan docs → latensi diukur di S1/S2 | **Dipilih** untuk spike 25b (K1, K3) |
| C5 | (2) Supabase Realtime | Tidak (melanggar aturan) | supabase.com/docs/guides/realtime/limits: Free 200 koneksi bersamaan, 100 pesan/s, 100 channel/koneksi; pricing: 2 juta pesan. Butuh `supabase-js` + kunci anon di extension → melanggar `SECURITY.md:16`. Auth Shoo = bearer token sendiri (`auth.ts:9-17`), bukan Supabase Auth → RLS/private channel butuh JWT Supabase yang dicetak Worker (sistem auth kedua). Proyek Free pause setelah 7 hari tanpa aktivitas (`ARCHITECTURE.md:65`) | Ditolak |
| C6 | (3) SSE dari Worker | Tidak cukup sendiri | developers.cloudflare.com/workers/platform/limits: Free CPU 10 ms/request, "no hard limit on duration" selama klien terhubung; menunggu jaringan tidak dihitung CPU. Tetapi Worker butuh pemicu: Hyperdrive **tidak** mendukung `LISTEN`/`NOTIFY` (developers.cloudflare.com/hyperdrive/reference/supported-databases-and-features). Tanpa pemicu = polling DB di dalam Worker (lebih banyak query). `EventSource` tidak bisa set `Authorization` | Ditolak; kalau perlu stream tetap butuh DO (sama dengan C4) |
| C7 | (4) Silent push APNs + App Group | Tidak | Push sekarang `apns-push-type: alert`, prioritas 10 (`apns.ts:111-118`). App tidak punya `remote-notification` (`project.yml:48` hanya `audio`; file Lead). Background push: prioritas 5, "low priority", sistem "doesn't guarantee their delivery", bisa di-throttle, notifikasi ditahan dibuang kalau app di-force-quit (Apple "Pushing background updates to your app", JSON docs dibaca 31 Okt 2026). Native handler hanya menjawab `heartbeat`/`getSession` (`SafariWebExtensionHandler.swift:16-29`); app tidak bisa mendorong pesan ke JS extension di iOS: `SFSafariApplication` dan `dispatchMessage(withName:toExtensionWithIdentifier:…)` hanya macOS 10.12+/10.12.4+ (metadata platform docs Apple, 31 Okt 2026) → extension tetap harus polling native. Menulis domain ke App Group menambah riwayat browsing di plist bersama | Ditolak |
| C8 | (5a) Polling adaptif | Ya | Hanya `blocked-page.js` (Umar). Rate limit 30/10 s per device (`rateLimit.ts:41`) cukup untuk 2 s: 5 request/10 s per tab, jadi ±5 layar blokir sekaligus (ditambah lookup `content.js`) sebelum 429; 429 tetap ditangani `Retry-After` (`blocked-page.js:34-36`). Kontrak menyebut "every 5 s" (`api.md:83`) → ubah teks kontrak | 25a-ext lewat issue Q1 |
| C9 | (5b) `ETag` / `If-None-Match` | Tidak bernilai | Body `{verdict:null}` ±16 byte; 304 tetap 1 request Worker + 3 query (auth + rate limit harus jalan). `fetchJSON` melempar error untuk `!response.ok` (`background.js:53-58`) → 304 dianggap gagal tanpa perubahan extension | Ditolak (K9) |
| C10 | (5c) Long-poll | Hanya dengan DO | Tanpa `LISTEN`/`NOTIFY` (C6), long-poll di Worker = query DB tiap detik. Long-poll ke DO bisa, tetapi request yang ditahan tanpa hibernasi ditagih durasi: 128 MB × 25 s = 3,2 GB-s per tahan → ±4 000 tahan/hari dari 13 000 GB-s | Cadangan kalau S2 gagal (WebSocket tidak bisa dari halaman extension) |
| C11 | Tidak ada identifier baru | Ya | DO dinamai dari `deviceId` yang sudah ada (`idFromName`). Tiket = `deviceId` + `exp` + nonce acak sekali pakai. Event hanya `{type, domain}` ke socket milik owner | K5, K6 |
| C12 | Notify setelah verdict | Ya | `decideVerdict` satu transaksi (`db/repo/verdicts.ts:30-68`), route menunggu hasil (`routes/verdicts.ts:36-49`). Notify ke DO sesudah commit, di `waitUntil`, gagal = diabaikan (log nama error saja) | 25b langkah 4 |
| C13 | Owner verdict = kunci yang benar | Ya | Verdict per `(owner_id, domain)` (`verdicts.ts:79-84`); `GET` membaca `owner = principal` (`:140-146`). Guardian yang menandai scan miliknya sendiri → owner = Guardian → DO Guardian. Dua mode tercakup | DO per owner |

## Peta dampak (semua sisi)

| Sisi | File / tempat | Perubahan | Sub-fase |
|---|---|---|---|
| Backend | `src/routes/verdicts.ts` | `GET`: log `verdict_seen` (K7). `POST`: notify DO di `waitUntil` setelah commit (flag) | 25a-be, 25b |
| Backend | `src/routes/verdictsLive.ts` (baru), `src/live/VerdictHub.ts` (baru, kelas DO), `src/services/liveTickets.ts` (baru), `src/index.ts` (export kelas DO), `src/app.ts:65-77` (`app.route` baru), `src/env.ts` + `test/env.d.ts` (`VERDICT_HUB`, `LIVE_VERDICTS`, `LIVE_TICKET_SECRET`), `src/http/rateLimit.ts` (`limits.liveTicket`) | `POST /verdicts/live-ticket`, `GET /verdicts/live` (upgrade WS), tiket HMAC | 25b |
| Backend | `src/routes/devices.ts` (hapus device `:181-197` / ganti mode = salin lalu hapus device lama `:153-173`, mode tidak pernah berubah di tempat) | Notify DO `close` supaya socket device yang dihapus langsung putus (P13) | 25b |
| Backend config | `wrangler.jsonc` | `durable_objects.bindings: [{ name: "VERDICT_HUB", class_name: "VerdictHub" }]`, `migrations: [{ tag: "v1", new_sqlite_classes: ["VerdictHub"] }]`, `vars.LIVE_VERDICTS: "off"` | 25b |
| Secret | `LIVE_TICKET_SECRET` (baru, ≥ 32 byte) | `wrangler secret put` = LANGKAH MANUAL; `.dev.vars` lokal + baris kosong di `.dev.vars.example`; nilai test di `vitest.config.ts` `miniflare.bindings` (pola `SCREENSHOT_URL_SECRET`, `:35`). Kosong/< 32 byte dengan flag `on` → `live-ticket` 404 (gagal tertutup) | 25b/25c |
| DB / migrasi | – | **Tidak ada.** Nonce tiket disimpan di storage SQLite DO, bukan Postgres | – |
| Test | `test/verdicts.test.ts`, `test/live/verdicts-live.test.ts` (baru, project vitest terpisah tanpa isolasi, C4), `vitest.config.ts`, `package.json` (script `test` menjalankan kedua project), `test/log-hygiene.test.ts` | Merah dulu (Langkah kerja) | 25a-be, 25b |
| App | – | **Tidak ada** (app tidak polling verdict) | – |
| Extension (Umar) | `ios/ShooExtension/Resources/{blocked-page.js, background.js}`, `chrome/extension/blocked-page.js`, `Tests/` | Jadwal adaptif (Q1); klien WebSocket di `blocked-page.js`, tiket lewat pesan `liveTicket` ke background (Q2–Q4) | 25a-ext, 25c-ext |
| Kontrak (Umar) | `contracts/api.md:77-85` | Usulan teks di bawah (Q1, Q3) | issue |
| Dokumen (Alief) | `backend/API.md` "Verdicts", `ARCHITECTURE.md` §3 (baris DO) + §4 butir 4 | Setelah kontrak merge | 25c |
| CI | `.github/workflows/backend.yml` | Tidak berubah; deploy DO lewat CI biasa (wrangler menerapkan `migrations`) | – |
| Privasi | `SECURITY.md` §3 | Tidak ada data baru di Postgres; log tanpa id/domain/tiket; event hanya ke socket owner | 25b |
| Biaya Free | Workers, Hyperdrive, DO | Lihat K8 dan tabel M | semua |

### Usulan kontrak (teks untuk issue Umar, bahasa Inggris seperti `contracts/`)

```md
### Verdicts (per domain)
| Method | Path | Body | Response | PRD |
|---|---|---|---|---|
| POST | `/verdicts` | (unchanged) | (unchanged) | GD-07 |
| GET | `/verdicts?domain=` | — | `{ verdict: Verdict \| null }` | EX-06 auto-open |
| POST | `/verdicts/live-ticket` | — | `{ ticket, expiresAt }` — single use, valid 60 s, bound to the caller's device. `404 not_found` when live verdicts are off → keep polling | EX-06 |
| GET | `/verdicts/live` | WebSocket upgrade, `Sec-WebSocket-Protocol: shoo-live.v1, t.<ticket>` | Server picks `shoo-live.v1`. Bad/used/expired ticket → `401` before upgrade | EX-06 |

Live messages (server → client, JSON text): `{ "type": "verdict", "domain": "<registrable domain>" }` after any verdict
on this device's scans changes. It carries no verdict: the client then calls `GET /verdicts?domain=` (one source of truth).
Client sends the text `ping` every 30 s; the server answers `pong`. No `pong` within 10 s, or any close → back to polling.
The server may close with 4401 (device gone) or 1001 (restart); clients just fall back.

Polling while the block screen is visible: every 2 s for the first 2 min after it opens or becomes visible again,
then every 5 s up to 10 min, then every 15 s. While a live socket is open: once right after it opens (a verdict may land before the socket does), then every 60 s (safety net).
Hidden tab: no polling; poll once when it becomes visible. 429 → wait `Retry-After` (unchanged).
The token never goes in a URL.
```

## Keputusan

**K1 — Arah (butuh Alief + Umar).** (a) Polling adaptif saja. (b) Polling adaptif sekarang + DO WebSocket lewat spike di belakang flag. (c) Langsung DO WebSocket. (d) Supabase Realtime. (e) SSE. (f) Silent push. Rekomendasi **(b)**. Alasan: (a) murah tetapi tidak bisa sekaligus cepat dan hemat (tabel K2); (c) berisiko karena C2 belum terverifikasi; (d)(e)(f) ditolak di C5–C7. Polling adaptif tetap dibutuhkan sebagai fallback realtime.

**K2 — Jadwal polling (butuh Umar; angka dari M5).** Request per layar blokir menurut lama menunggu:

| Jadwal | 1 mnt | 5 mnt | 10 mnt | 30 mnt | 60 mnt | Latensi rata-rata saat verdict datang |
|---|---|---|---|---|---|---|
| (a) tetap 5 s (sekarang) | 12 | 60 | 120 | 360 | 720 | 2,5 s |
| (b) 2 s × 2 mnt → 5 s s/d 10 mnt → 15 s | 30 | 96 | 156 | 236 | 356 | 1 s / 2,5 s / 7,5 s |
| (c) realtime + jaring 60 s | 3 | 7 | 12 | 32 | 62 | ±0,3–1 s |

(c) dihitung: 1 tiket + 1 upgrade + 1 GET/menit (+ 1 GET per event, + 1 GET tepat setelah socket terbuka dan tiap sambung ulang; tanpa GET ini verdict yang jatuh di celah antara poll terakhir dan socket terbuka baru terlihat ≤ 60 s kemudian). Angka baris (c) karena itu ±1 lebih tinggi di menit pertama. Pesan `ping` 30 s tidak menambah request Worker; di DO paling banyak ditagih 20:1 (±0,1 request DO/menit/layar; docs tidak menyebut apakah pesan yang dijawab auto-response dihitung). Rekomendasi **(b)** sebagai fallback, tetapi angka 2 min dan 10 min disesuaikan dengan sebaran waktu reaksi Guardian M5 (kalau p50 reaksi > 5 menit, fase cepat 2 s tidak berguna). (b) melanggar target ≤ 10 s (`ARCHITECTURE.md:78`) setelah 10 menit kecuali tab baru terlihat lagi (poll langsung); terima, karena (c) yang menutup ekor itu.

**K3 — Di mana socket dibuka (butuh Umar).** (a) `blocked-page.js` (tab terlihat). (b) `background.js`. (c) Long-poll DO dari `blocked-page.js`. Rekomendasi **(a)**: background tidak hidup lama (C1), dan realtime hanya berarti saat layar terlihat. (c) cadangan kalau S2 gagal. (a) dan (c) sama-sama butuh pengecualian aturan Lead `ShooExtension/CLAUDE.md:21,24` (C2): halaman menerima tiket + URL `wss://` dari background, tidak pernah token. Umar menolak → hanya (b) yang tersisa, yang tidak andal (C1) → K8 no-go, fase selesai dengan polling adaptif.

**K4 — Auth WebSocket.** (a) Tiket HMAC sekali pakai 60 s di `Sec-WebSocket-Protocol`. (b) Token bearer di pesan pertama. (c) Token di query. Rekomendasi **(a)**. (c) dilarang aturan. (b) memaksa DO memverifikasi token ke DB dan membawa token permanen ke halaman. (a): Worker memverifikasi tanpa query DB (pola `screenshotLinks.ts:17-18`, jadi `services/signedLinks.ts` setelah fase 20b, `fase-20-screenshot-sunset.md:89`; pesan `live:v1|deviceId|exp|nonce`, format kirim C3), nonce dicatat di SQLite DO sampai `exp`; baris kedaluwarsa dihapus malas di tiap upgrade (`delete … where exp < now`), **bukan** alarm (alarm membangunkan DO dan mencegah hibernasi, C4). Tiket diambil background (yang sudah punya token) dan diteruskan ke halaman lewat balasan `runtime.onMessage` `{ticket, url}` (Q4; butuh pengecualian `ShooExtension/CLAUDE.md:24`, C2). Rate limit tiket pakai `hitLight` (satu statement, `rateLimit.ts:55-71`; batas kapasitas, bukan anti-tebak), jadi tiket = 2 query Hyperdrive.

**K5 — Isi event.** (a) `{type:"verdict", domain}` lalu klien `GET /verdicts`. (b) Verdict lengkap (nama Guardian, nilai). Rekomendasi **(a)**: satu sumber kebenaran, rate limit dan aturan putus hubungan tetap di `GET`, data minimum di jalur baru. Biaya: +1 RTT (±100–300 ms, masih ≤ 1 s).

**K6 — Kunci DO.** (a) Satu DO per owner device (`idFromName(deviceId)`). (b) Satu DO global. Rekomendasi **(a)**: socket device lain tidak pernah satu objek, tidak ada fan-out salah alamat; beban per objek kecil.

**K7 — Log latensi (butuh Alief).** Di `GET /verdicts`: kalau verdict ada dan `now − decidedAt ≤ 120 s`, `console.log(JSON.stringify({ event: "verdict_seen", ageMs, value }))`. Tanpa domain, device id, nama. Klien berhenti polling setelah verdict pertama (`blocked-page.js:134-143`), jadi biasanya satu baris per keputusan; lookup `content.js` (cache 60 s) bisa menambah noise kecil. `ageMs` = latensi sisi server (tanpa RTT terakhir + render). Rekomendasi **ya**, 25a-be, karena dipakai untuk mengukur semua varian.

**K8 — Go/no-go spike 25b (butuh Alief).** Go kalau semua: M1 p95 ≤ 1,5 s (20 percobaan, tab terlihat); M2 ≤ 2 request/menit/layar; socket tetap hidup ≥ 10 menit saat tab terlihat di iPhone fisik (S2); M3 durasi DO < 10% dari 13 000 GB-s/hari dan request DO < 10% dari 100 000/hari pada beban demo; fallback ke polling terbukti (S3). Satu gagal → 25c batal, fase selesai dengan (b) saja, catat di `log/DECISIONS.md`.

**K9 — `ETag`.** Tidak (C9).

## Output

- `log/fase-25.md`: baseline M1–M5 sebelum/sesudah 25a-ext, sesudah 25c.
- 25a-be: log `verdict_seen` + test.
- Issue ke Umar (satu topik): `EX-06: verdict realtime + jadwal polling layar blokir` dengan Q1–Q5.
- 25b: DO `VerdictHub`, endpoint tiket + live, notify di `POST /verdicts`, close saat hapus device, flag `LIVE_VERDICTS`, test, halaman uji `plan/alief/qa/live-verdict.html` (dibuka di Safari simulator, bukan extension).
- 25c: flag `on` lewat PR, `backend/API.md` + `ARCHITECTURE.md` diperbarui.

## Langkah kerja

### 25-0 — Baseline (tanpa branch)

1. M5 (LANGKAH MANUAL 1): sebaran waktu reaksi Guardian dari DB produksi, agregat saja.
2. M1/M2/M4 dengan build TestFlight sekarang (LANGKAH MANUAL 2–3).
3. Tulis angka ke `log/fase-25.md`.

### Issue ke Umar (LANGKAH MANUAL 4)

Q1 jadwal polling adaptif + teks kontrak (K2). Q2 boleh/tidak WebSocket dari `blocked.html` (pengecualian aturan `ShooExtension/CLAUDE.md:21` "every network call goes through `background.js`" dan `:24` "no reply carries … the base URLs", C2), dan siapa menjalankan spike S2 di device. Q3 setuju endpoint + format tiket (K4, K5). Q4 pesan background baru `liveTicket` (`{type:"liveTicket"}` → `{ticket, url}`, tidak pernah token), sama untuk Chrome. Q5 urutan rilis: 25c flag `on` hanya setelah build extension yang memakainya ada di TestFlight. Sampai dijawab: Alief mengerjakan 25-0 dan 25a-be saja; 25b boleh dibangun lokal di branch spike tanpa merge.

### 25a-be — `feat/EX-06-verdict-latency-log`

1. **Merah.** `test/verdicts.test.ts`: setelah `POST /verdicts`, `GET /verdicts` memancarkan satu log `verdict_seen` dengan `ageMs` angka ≥ 0 dan `value`; verdict > 120 s tidak memancarkan; `null` tidak memancarkan. `test/log-hygiene.test.ts`: baris `verdict_seen` tidak memuat domain, `deviceId`, nama, token.
2. **Kode.** `routes/verdicts.ts:55-61`: hitung dari `verdict.decidedAt` setelah `findVerdict`.
3. **Hijau.** `pnpm -C backend/api test && pnpm -C backend/api typecheck`. PR kecil, review `ecc:typescript-reviewer`, deploy lewat CI.

### 25b — `spike/EX-06-verdict-live` (flag `off`, belum merge)

1. **Merah — tiket.** Dulu: project vitest kedua di `vitest.config.ts` (`test.projects`) untuk `test/live/**` dengan `isolate: false` + satu worker (known issue C4); project lama mengecualikan `test/live/**`; `pnpm test` menjalankan keduanya (CI `backend.yml:43` tetap). Bentuk persis (satu `cloudflareTest` per project atau bersama) belum terverifikasi: coba dulu, cadangannya config kedua `vitest.live.config.ts` + `vitest run --config … --no-isolate --max-workers=1` di script `test`. Lalu `test/live/verdicts-live.test.ts`: `POST /verdicts/live-ticket` tanpa bearer → 401; flag `off` → 404; flag `on` tapi `LIVE_TICKET_SECRET` kosong/< 32 byte → 404; flag `on` → `{ticket, expiresAt}` dengan `expiresAt − now ≤ 60 s` dan tiket cocok `^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$`; rate limit 6/menit/device (`limits.liveTicket` baru, `hitLight`) → 429 + `Retry-After`.
2. **Merah — upgrade.** `GET /verdicts/live` tanpa header `Upgrade: websocket` → 426; tiket di query → 401 (query diabaikan); tiket salah/kedaluwarsa/dipakai ulang → 401; tiket benar → 101 dengan `Sec-WebSocket-Protocol: shoo-live.v1`.
3. **Merah — event.** Dua socket (device A, device B). Guardian `POST /verdicts` pada scan A → socket A menerima `{"type":"verdict","domain":"…"}` ≤ 500 ms; socket B tidak menerima apa pun. `ping` → `pong`. `DELETE /devices/me` oleh A → socket A ditutup 4401. Verdict yang diputuskan sebelum upgrade tidak menghasilkan event di socket baru, tetapi `GET /verdicts` sesudah upgrade menemukannya (bukti bahwa celah K2 c hanya ditutup oleh GET klien tepat setelah socket terbuka; aturan klien ada di usulan kontrak, kode milik Umar).
4. **Kode.** `live/VerdictHub.ts`: `ctx.acceptWebSocket()` (Hibernation API, bukan `ws.accept()`), `ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping","pong"))`, `fetch` internal `/notify {domain}` → kirim ke semua `ctx.getWebSockets()`, `/close` → tutup 4401, nonce tiket di `ctx.storage.sql` + hapus malas baris kedaluwarsa (tanpa alarm, K4); DO tidak menyimpan `deviceId`. `routes/verdictsLive.ts`: `requireDevice` hanya di `/verdicts/live-ticket` (middleware `verdicts.use("/verdicts", …)` di `routes/verdicts.ts:25` cocok persis `/verdicts` saja), tidak di `/verdicts/live`; verifikasi tiket (HMAC, `exp`, mode tidak relevan), teruskan request upgrade ke `env.VERDICT_HUB.get(idFromName(deviceId))`. Respons `stub.fetch` kemungkinan ber-header immutable, sedangkan middleware global menulis header setelah `next()` (`app.ts:46,54-63`) → bungkus ulang `new Response(null, { status: 101, webSocket: res.webSocket, headers: res.headers })` sebelum dikembalikan (belum terverifikasi; test langkah 2 "101" menangkapnya). `routes/verdicts.ts` POST: setelah `result` sukses, `c.executionCtx.waitUntil(notify(owner, domain).catch(logName))` — butuh `ownerId` + `domain` dari `decideVerdict` (tambah ke `VerdictResult`, tanpa mengubah respons JSON).
5. **Hijau** + `wrangler deploy --dry-run --outdir /tmp/shoo-dry` lokal (cek bundle, kelas DO ter-export; ukuran dibanding dry-run yang sama di `main`, Verifikasi).
6. **S1 lokal.** `wrangler dev` + `plan/alief/qa/live-verdict.html` di Safari simulator: ukur waktu `POST` → event (20×), lihat socket bertahan saat tab terlihat, putus saat Safari ke background, sambung ulang saat kembali.
7. **S2 device (Umar atau build lokal Umar, Q2).** Halaman extension sungguhan di iPhone fisik, tab terlihat 10 menit, lalu ke app lain 2 menit, kembali.
8. **S3 fallback.** Matikan flag / putuskan jaringan / DO melempar → klien kembali ke jadwal polling; `POST /verdicts` tetap 200.
9. Review `ecc:security-reviewer` → `ecc:typescript-reviewer` → `ecc:performance-optimizer` (berurutan). Hasil + K8 ke `log/fase-25.md`.

### 25c — `feat/EX-06-verdict-live`

1. Rebase spike ke `main`, buang halaman uji kalau tidak dipakai lagi, PR (flag tetap `off`), deploy CI.
2. Setelah kontrak merge (Umar) dan build extension TestFlight memakai endpoint: PR kecil `LIVE_VERDICTS: "on"`.
3. Ukur ulang M1–M4 24 jam dan 7 hari setelah `on`. Perbarui `backend/API.md`, `ARCHITECTURE.md` §3 (baris Durable Objects) dan §4 butir 4 (target ≤ 1,5 s).

## LANGKAH MANUAL

- [ ] 1. (Alief, Supabase SQL editor, baca saja) M5, hasil agregat ke log (tanpa baris mentah):
  ```sql
  select count(*) as n,
         percentile_cont(array[0.5, 0.9, 0.95]) within group (order by extract(epoch from v.decided_at - s.created_at)) as detik
  from verdicts v join scans s on s.id = v.scan_id join devices d on d.id = s.owner_id
  where d.mode = 'protected' and s.status = 'blocked' and v.decided_at >= s.created_at;
  ```
  Data hanya 14 hari (retensi); n kecil = catat apa adanya.
- [ ] 2. (Alief + 1 penguji, 2 iPhone) M1: Protected membuka situs uji sampai layar blokir, Guardian tap Aman di Detail. Rekam kedua layar dengan satu kamera 60 fps; hitung frame dari tap sampai halaman terbuka. 20× per varian (sekarang, 25a-ext, 25c). p50/p95 ke log.
- [ ] 3. (Alief, Mac + iPhone) M2: Safari → Develop → [iPhone] → Web Extension Background Content → Network, layar blokir terbuka 10 menit, hitung `GET /verdicts` (dan `live-ticket`). Socket varian 25c ada di halaman `blocked.html`, bukan background: buka juga Develop → [iPhone] → tab layar blokir → Network untuk upgrade/sambung ulang. M4 (indikatif): Xcode → Debug Navigator → Energy Impact / Instruments Energy Log, layar blokir 10 menit per varian. Hasil = "indikatif", bukan klaim baterai.
- [ ] 4. (Alief, GitHub) Issue ke Umar: template question, label `question`, assign @umarmuhdhor, judul `EX-06: verdict realtime + jadwal polling layar blokir`, Q1–Q5 bernomor, usulan kontrak di atas, "sampai dijawab" dari Langkah kerja. Tautkan nomor issue di `TODO.md` E3.
- [ ] 5. (Alief, cloud) Sebelum 25c deploy, dari `backend/api`: `npx wrangler secret put LIVE_TICKET_SECRET` (nilai dari `openssl rand -base64 48`, diketik, tidak ditempel di chat/log). Simpan di password manager.
- [ ] 6. (Alief, dashboard) M3: Workers & Pages → `shoo-api` → Durable Objects → `VerdictHub`: request/hari + durasi GB-s; Workers request/hari; Hyperdrive query/hari. 24 jam sebelum dan sesudah flag `on`.
- [ ] 7. (Alief, cloud) `npx wrangler tail shoo-api --format json` saat M1: salin hanya baris `verdict_seen` (`ageMs`, `value`).

## Verifikasi

```bash
# lokal, dari root repo; test log-hygiene = token/tiket tidak pernah di log
(cd backend/db && supabase start)
pnpm -C backend/api test -- verdicts log-hygiene            # project biasa (25a-be, 25b)
pnpm -C backend/api exec vitest run --project live          # project live: isolate false, satu worker (C4); 25b
pnpm -C backend/api test && pnpm -C backend/api typecheck   # seluruh suite, sama dengan CI backend.yml:42-43
git worktree add /tmp/shoo-main origin/main && pnpm -C /tmp/shoo-main/backend/api install --frozen-lockfile && pnpm -C /tmp/shoo-main/backend/api exec wrangler deploy --dry-run --outdir /tmp/shoo-dry-main && git worktree remove --force /tmp/shoo-main   # baseline bundle main
pnpm -C backend/api exec wrangler deploy --dry-run --outdir /tmp/shoo-dry && du -k /tmp/shoo-dry-main/index.js /tmp/shoo-dry/index.js   # kelas VerdictHub ada; selisih ≤ 20 KB
# tiket di query harus ditolak (wrangler dev, flag on di .dev.vars)
curl -si "http://localhost:8787/verdicts/live?ticket=x" -H "Upgrade: websocket" -H "Connection: Upgrade" | head -1   # 401
```

## Kriteria selesai (DoD)

- [ ] `log/fase-25.md` berisi baseline M1 (p50/p95), M2 (request/menit), M5 (sebaran reaksi Guardian), M4 indikatif.
- [ ] Issue Umar terbuka dengan Q1–Q5, nomornya di `TODO.md` E3.
- [ ] 25a-be merge + deploy CI; `verdict_seen` muncul di `wrangler tail` tanpa domain/id (test log-hygiene hijau).
- [ ] 25a-ext (Umar) terukur: M2 sesuai tabel K2 jadwal yang disepakati, M1 p95 ≤ 2,5 s di 2 menit pertama.
- [ ] 25b: semua test merah → hijau (dua project vitest, `pnpm -C backend/api test` hijau); K8 diputuskan dan dicatat di `log/DECISIONS.md` sebagai keputusan baru yang menggantikan D-alief-08 "EX-06 tetap polling" (`log/DECISIONS.md:77-80`) kalau go, atau merujuknya kalau no-go.
- [ ] Kalau go — 25c: flag `on`; M1 p95 ≤ 1,5 s (20 percobaan); M2 ≤ 2 request/menit/layar; M3 DO < 10% kuota Free; S3 fallback terbukti; `backend/API.md` + `ARCHITECTURE.md` diperbarui.
- [ ] Tidak ada token/tiket di URL atau log; tidak ada kunci Supabase di extension; tidak ada kolom/tabel baru di Postgres.

## Risiko & rollback

| Risiko | Tanda | Mitigasi / rollback |
|---|---|---|
| iOS menutup WebSocket halaman extension bahkan saat terlihat | S2 gagal | 25c batal; tetap jadwal adaptif (K1 b). Cadangan: long-poll DO (K3 c) dengan hitungan durasi C10 |
| DO error / kuota DO habis | Event tidak datang; dashboard DO merah | Klien tetap polling 60 s + kembali ke jadwal adaptif saat socket tutup. Matikan: PR `LIVE_VERDICTS: "off"` → deploy CI → `live-ticket` 404 → semua klien polling. `POST /verdicts` tidak bergantung DO (notify di `waitUntil`, error ditelan) |
| Polling 2 s menaikkan kuota harian | Workers/Hyperdrive > 70% (otomatis hanya `worker_requests_high` ≥ 80 000 fase 21; Hyperdrive yang habis lebih dulu dicek manual M3) | Umar memperpendek fase cepat (Q1); rollback = revert `blocked-page.js` ke 5 s (build TestFlight baru) |
| Tiket bocor | – | 60 s, sekali pakai, terikat device, hanya memberi event `{domain}` milik device itu sendiri; rotasi `LIVE_TICKET_SECRET` membatalkan semua |
| Kelas DO tidak bisa "dihapus" sembarangan | Ingin cabut total | Jangan ganti nama kelas. Cabut = migrasi baru `deleted_classes: ["VerdictHub"]` di `wrangler.jsonc` setelah binding dibuang, lewat PR + CI |
| Socket device yang dihapus tetap terbuka | – | `/close` 4401 dari `DELETE /devices/me` + ganti mode (P13). Tiket dibuat lewat `requireDevice` (device pasti ada saat itu), tetapi upgrade tidak menanyai DB: tiket yang belum terpakai tetap bisa menyambung ≤ 60 s setelah hapus. Dampaknya kosong (DO device itu tidak menerima event lagi); kalau reviewer menolak, upgrade menambah satu `findByTokenHash`-setara `select 1 from devices where id = …`. Hapus oleh cron device tidak aktif (fase 24a, `fase-24-privacy-data.md:292`) praktis tidak mengenai socket terbuka: socket aktif = `GET` tiap 60 s → `touchLastSeen` ≤ 5 menit (`auth.ts:42`); kalau tetap terjadi, dampaknya sama kosong |
| Build extension lama + backend baru | – | Aman: endpoint lama tidak berubah, build lama terus polling 5 s |

## Catatan handoff

- Semua kode extension (`blocked-page.js`, `background.js`, Chrome) milik Umar; Alief hanya menulis issue dan backend. Jangan menyentuh `contracts/` atau `ios/ShooExtension/`.
- Fakta Free tier dibaca 31 Okt 2026; cek ulang halaman pricing DO dan Supabase sebelum 25c (angka bisa berubah).
- Belum terverifikasi: (1) WebSocket dari `blocked.html` di Safari iOS (S2) dan jawaban Umar soal pengecualian `ShooExtension/CLAUDE.md:21,24` (Q2); (2) iOS membekukan timer/menutup socket di tab tersembunyi (hanya bukti tidak langsung); (3) header immutable pada respons `stub.fetch` vs middleware `app.ts:46` (langkah 25b-4); (4) lokasi DO terhadap `placement: smart`. Sudah terverifikasi 31 Okt 2026: teks docs Apple background push dan `dispatchMessage` = macOS saja (C7).
- Sebaran reaksi Guardian (M5) menentukan angka jadwal K2; jangan kunci angka sebelum M5 ada.
- `ageMs` (K7) memakai jam server untuk dua titik (`decided_at` = `clock_timestamp()` di Postgres, `verdicts.ts:81`; `now` di Worker): selisih jam Postgres–Worker kecil tetapi tidak nol; pakai untuk tren, M1 untuk angka resmi.

## Riwayat verifikasi

- Ronde 1 (31 Okt 2026): 17 temuan (0 kritis, 0 tinggi, 4 sedang, 13 rendah); diperbaiki: socket/long-poll di `blocked-page.js` melanggar aturan Lead `ShooExtension/CLAUDE.md:21` (semua jaringan lewat background) dan `:24` (tanpa base URL di balasan) → C2, K3, K4, Q2, Q4 meminta pengecualian eksplisit (tiket + URL, tidak pernah token), ditolak = K8 no-go; GET tepat setelah socket terbuka (sebelumnya verdict di celah poll→socket baru terlihat ≤ 60 s) di kontrak, K2 (c), test; test WebSocket DO di project vitest kedua tanpa isolasi (known issue resmi Vitest Workers; `pnpm test` CI tetap); bungkus ulang respons 101 karena middleware `app.ts:46` menulis header (belum terverifikasi); rendah: `requireDevice` per route, `hitLight` untuk tiket, field "Fase berikutnya" + risiko kuota (Hyperdrive habis lebih dulu, fase 21 hanya `worker_requests_high`), secret kosong gagal tertutup + file Peta, C7 terverifikasi (Apple JSON docs), `signedLinks.ts` fase 20b, nonce dihapus malas tanpa alarm, format tiket token HTTP, fase 24a di baris 226, D-alief-08, baseline bundle, inspector halaman + direktori `wrangler secret put`, fakta DO tambahan di C4; baris 69 dan 226 tetap (dirujuk `fase-24-privacy-data.md:292`); dicatat tanpa diubah: tidak ada.
- Ronde 2 (31 Okt 2026): bagian yang diubah dibaca ulang; 2 temuan rendah (bentuk config project vitest kedua belum pasti → cadangan config terpisah; test celah K2 c diperjelas sebagai tanggung jawab klien + angka (c) ±1), diperbaiki; 0 kritis/tinggi/sedang. Baris 69 dan 226 tetap. Belum terverifikasi: WebSocket dari `blocked.html` di Safari iOS + jawaban Umar soal `ShooExtension/CLAUDE.md:21,24` (S2, Q2), socket di tab tersembunyi, header immutable `stub.fetch` vs `app.ts:46`, bentuk config vitest DO, lokasi DO vs Smart Placement, tagihan pesan auto-response, Supabase Realtime 2 juta pesan/bulan, WWDC21 10027/forum 790310 (C1).
- Cek lintas fase (1 Nov 2026): tidak ada konflik keputusan. File bersama yang perlu rebase: `vitest.config.ts` (20b menghapus `localSupabase()`/binding `SUPABASE_*`, 21a menambah `OPS_STATUS_TOKEN`, 25b menambah `test.projects`), `src/app.ts:65-77` (21a `/ops`, 25b `/verdicts/live*`), `src/env.ts` + `test/env.d.ts` (20b, 21a, 24a, 25b), `wrangler.jsonc` (20b vars, 22a-1 `minify`, 24a `INACTIVE_DEVICES`, 25b `durable_objects`), `routes/devices.ts` (24a tidak menyentuh route; notify `close` DO di 25b hanya untuk jalur route, hapus cron 24a = dampak kosong, `:226`). Pola tiket memakai `screenshotLinks.ts` → `signedLinks.ts` setelah 20b dan cache kunci 22a-1 (fase 22 O1) boleh dipakai ulang. Baris `:69,226` tetap.
