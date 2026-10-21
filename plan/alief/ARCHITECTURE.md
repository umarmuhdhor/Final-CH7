# Shoo · Team App + Backend — Arsitektur teknis (1 halaman)

> Cakupan: `ios/ShooApp/` dan `backend/` (milik Alief). Extension Safari, Live Activity (Umar), dan detector/AI (Imelda) hanya digambar sebagai tetangga.
> Kontrak: `contracts/api.md`, `contracts/app-group-keys.md`, `contracts/scan-result.schema.json`. Detail implementasi: `ref/R1`–`R4`.

## 1. Gambaran besar

```mermaid
flowchart LR
  subgraph iPhone["iPhone (Guardian atau Protected)"]
    APP["Shoo app (SwiftUI)\nios/ShooApp"]
    EXT["Safari extension\n(Umar + detector Imelda)"]
    AG[("App Group\ngroup.com.shoo.app")]
    APP -- tulis sesi --> AG
    EXT -- baca sesi, tulis heartbeat --> AG
  end
  subgraph CF["Cloudflare (Free)"]
    W["Worker shoo-api\nHono + postgres.js"]
    HD["Hyperdrive shoo-db"]
    CRON["Cron Trigger\nretensi 14 hari"]
  end
  subgraph SB["Supabase shoo-demo (Free, ap-southeast-1)"]
    PG[("Postgres\nrole shoo_api")]
    ST[("Storage\nbucket screenshots (private)")]
  end
  AI["AI service /analyze\n(Imelda)"]
  APNS["APNs"]
  APP -- "REST + Bearer device token" --> W
  EXT -- "POST /scans, GET /verdicts, GET /blocklist" --> W
  EXT -- "POST /analyze" --> AI
  W --> HD --> PG
  W -- "Storage REST (service key)" --> ST
  CRON --> W
  W -- "HTTP/2 + JWT ES256" --> APNS --> APP
```

Satu-satunya pintu ke data adalah Worker. Postgres tidak diekspos lewat PostgREST (grant `anon`/`authenticated` dicabut). App dan extension tidak pernah memegang kunci Supabase.

## 2. Komponen & tech stack

| Komponen | Stack | Folder | Catatan |
|---|---|---|---|
| App iOS | SwiftUI, iOS 17, Observation (`@Observable`), Swift Concurrency, String Catalog EN/ID | `ios/ShooApp/` | Data lewat protocol `ShooRepository`: `MockRepository` (fixtures, fase 01–06) → `ApiRepository` (fase 13) |
| Test iOS | Swift Testing (`ShooAppTests`), XCUITest (`ShooAppUITests`) | `ios/ShooApp/Tests/`, `ios/ShooApp/UITests/` | Target ditambah lewat PR `chore/APP-test-targets` (D-alief-02) |
| API | Cloudflare Worker, TypeScript, Hono, zod, postgres.js | `backend/api/` | Runtime-agnostic: hanya Web API (`fetch`, `crypto.subtle`) |
| Koneksi DB | Cloudflare Hyperdrive → pooler Supabase | `backend/api/wrangler.jsonc` | Lokal: `localConnectionString` ke `supabase start` (port 54322) |
| DB | Supabase Postgres 15+, migrasi SQL, pgTAP | `backend/db/supabase/` | Role `shoo_api` least-privilege (R2 §3) |
| Screenshot | Supabase Storage, bucket private `screenshots`, signed URL 1 jam | lewat `ScreenshotStore` di `backend/api/src/services/screenshots.ts` | Adapter: ganti ke R2 = satu file (E1) |
| Push | APNs HTTP/2, token-based (JWT ES256 dari `.p8`) | `backend/api/src/services/push/` | Spike fase 07: kalau `fetch` Worker gagal ke APNs → fallback Edge Function Supabase `push` (Deno) dipanggil Worker dengan shared secret |
| Retensi | Worker Cron Trigger harian | `backend/api/src/cron/retention.ts` | Hapus scan > 14 hari + objek Storage-nya (lewat Storage API, bukan SQL) |
| CI (draf) | GitHub Actions | `backend/ci/backend.yml`, `ios/ShooApp/ci/ios-app.yml` | Inert sampai Umar memindahkannya ke `.github/workflows/` (C2) |

## 3. Hosting, kuota & biaya

| Layanan | Plan | Kuota yang relevan | Penjaga |
|---|---|---|---|
| Cloudflare Workers | Free | 100k request/hari, CPU 10 ms/request, 50 subrequest/request | Tidak ada kerja berat di Worker; satu signed URL per `GET /scans/{id}`; polling verdict 5 s hanya saat layar blokir terbuka |
| Hyperdrive | Free | BELUM DIVERIFIKASI (kuota query/hari) | Spike fase 07. Fallback: postgres.js langsung ke pooler via `connect()` TCP |
| Supabase DB | Free | 500 MB, 2 proyek/org, pause setelah 7 hari tidak aktif | Retensi 14 hari; monitor uptime (B9). BELUM DIVERIFIKASI: apakah query lewat pooler dihitung "aktif" — dicek di fase 12 |
| Supabase Storage | Free | 1 GB file, 5 GB egress/bulan | ≤ 150 KB/screenshot, 1 per pemilik+domain per 24 jam, maks 50/device/hari, hanya dimuat di Detail, cache di app, retensi 14 hari. Ambang pindah ke R2: 700 MB atau 3,5 GB egress |
| APNs | Termasuk Apple Developer Program | – | Sandbox dulu, production saat TestFlight |
| TestFlight | Apple Developer Program | – | Butuh Team ID (B6) |

Perkiraan kasar: 150 KB × 50/hari × 14 hari = ±105 MB per device paling sibuk. Rata-rata jauh di bawah itu karena dedupe per domain.

## 4. Alur utama

1. **Onboarding (ON-02, ON-03, fase 13).** App → `POST /devices {name, mode, apnsToken?}` → `{deviceId, token, avatarId}`. App menulis `device.id`, `device.token`, `device.mode`, `device.name`, `api.baseURL`, `ai.baseURL` ke App Group (kontrak) + menyimpan token di Keychain untuk app sendiri.
2. **Pairing (GD-04, PR-01..03, fase 08 + 14).** Guardian → `POST /family/code` (tiap 60 s, app menghitung mundur) → QR + kode + `inviteUrl` https. Protected → `POST /family/join {code}` (scan QR, ketik kode, atau buka `shoo://join?code=`) → `{guardian}`. Server menolak kalau kode salah/kedaluwarsa, keluarga penuh (3), atau percobaan berlebih.
3. **Scan → push (EX-07, GD-06, fase 09 + 11 + 15).** Extension → `POST /scans` (skor ≥ 30, + `screenshotBase64?`) → Worker menyimpan scan, mengunggah screenshot (kalau lolos kuota) → kalau pemiliknya Protected: kirim APNs ke Guardian dengan teks sesuai bahasa Guardian dan `scanId` → tap → app membuka Detail (`GET /scans/{id}`).
4. **Verdict → buka blokir (GD-07, EX-06, fase 10 + 15).** Guardian menekan It's safe / Not safe di Detail → `POST /verdicts {scanId, value}` (langsung, tanpa konfirmasi) → verdict berlaku untuk domain itu milik pemilik scan → extension Protected yang polling `GET /verdicts?domain=` tiap 5 s melihat `safe` → layar blokir terbuka. `not_safe` → domain masuk `GET /blocklist`.
5. **Retensi (fase 12).** Cron harian menghapus scan > 14 hari + objek Storage-nya, kode keluarga kedaluwarsa, dan catatan percobaan join lama. Verdict tidak dihapus (dipakai blocklist, D-alief-14).

## 5. Di Mac Alief (lokal)

```bash
cd backend/db && supabase start            # Postgres :54322, Storage, Studio :54323 (Docker)
cd backend/api && pnpm install && pnpm dev # wrangler dev :8787, Hyperdrive lokal → :54322
cd ios && xcodegen && open Shoo.xcodeproj  # app di simulator, api.baseURL = http://localhost:8787 (Debug)
```

Simulator iOS menjangkau `localhost` Mac tanpa port forwarding.

## 6. Keamanan singkat

- Auth tanpa login: token device acak 32 byte, disimpan sebagai hash SHA-256. Setiap request lewat middleware `auth` → `principal {deviceId, mode}`.
- Otorisasi di setiap query: Guardian hanya membaca scan miliknya sendiri atau milik Protected yang `family_links`-nya aktif ke dia. Test IDOR wajib di fase 09–10.
- Kode keluarga 4 digit: 60 s, multi-pakai selama berlaku, batas 3 Protected, 5 gagal/10 menit per device dan per IP.
- Secret hanya di `wrangler secret` dan password manager. Detail: [`SECURITY.md`](SECURITY.md).

## 7. Baca lebih dalam

`ref/R1` struktur folder · `ref/R2` skema SQL · `ref/R3` catatan API · `ref/R4` state machine · `log/DECISIONS.md`.
