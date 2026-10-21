# Rencana fase 11 — Push APNs (dari `ecc:planner`, 22 Okt 2026)

Jalur: `ApnsSender` langsung dari Worker (D-alief-B01 lebih baru dari teks relay di file fase 11). Tanpa relay, Edge Function, Deno test, `PUSH_RELAY_*`. Relay hanya kalau uji iPhone nyata (D7) gagal di jalur langsung.

## Keputusan (D-alief-B11)
- `push_log.body` dihapus (privasi D-alief-40): menyalin nama Protected ke tabel kedua dan basi setelah ganti nama; payload bisa dibangun ulang dari `pushText` + `scan_id`. CHECK format `result` (`sent` | `logged` | `failed:<3 digit>[ <Reason>]` | `failed:timeout|network|config`) supaya token/JWT tidak pernah tersimpan.
- Tanpa retry (403/429/5xx): satu push per scan, dicatat lalu dilepas.

## Langkah TDD
1. Migrasi `20261022100000_push_log_privacy.sql` (pgTAP dulu: `hasnt_column body`, CHECK menolak string panjang/token).
2. Env/config: hapus `APNS_SPIKE`/`SPIKE_KEY`; secret `APNS_KEY_P8_B64`, `APNS_KEY_ID`, `APNS_TEAM_ID`; var `APNS_TOPIC` (`""` sampai B6), `APNS_ENV: "sandbox"`.
3. Hapus spike: test `POST /debug/apns-spike` → 404, hapus `routes/debug-apns.ts`.
4. `pushSender(env)`: 4 nilai lengkap + `APNS_ENV ∈ {sandbox, production}` → `ApnsSender`; selain itu `LogSender` + log `push_config_incomplete` (nama saja).
5. `ApnsSender` (`services/push/apns.ts`): fetch + now di-inject; cache modul per `keyId:teamId` (CryptoKey + JWT < 50 menit, single-flight); `POST https://api{.sandbox}.push.apple.com/3/device/<token>`, header R3 §6, body kontrak + `sound`, `AbortSignal.timeout(5000)`. 200 → `sent`; 410 `Unregistered`/`ExpiredToken` → `clearToken`; 403 `ExpiredProviderToken` → buang JWT cache; 400 `BadDeviceToken` → token tetap; timeout/network/config → `failed:timeout|network|config`. `reason` disaring `^[A-Za-z]{1,64}$`. `send` tidak pernah throw.
6. `services/push/log.ts`: `recordPush` (tanpa body), `clearApnsToken` compare-and-clear (`where id = $1 and apns_token = $2`).
7. `deliverPush(sql, sender, msg)` dipanggil di `waitUntil` `POST /scans`: send → clear → record. Error dicatat `err.name` saja (pesan fetch bisa memuat URL berisi token).
8. Docs: R3 §6–§7, R2 (`push_log`), SECURITY T9, README backend, catatan C9.

Deviasi dari planner: tanpa project vitest kedua. `ApnsSender` diuji dengan `fetch` di-inject + DB lokal; `deliverPush` diuji dengan sender palsu; route `POST /scans` diuji dengan `LogSender` (baris `logged`).

## Test
- `push-apns.test.ts`: host per env, header persis, JWT terverifikasi (`kid`/`iss`), body kontrak + `sound`, 200/410×2/400/403×2/500 non-JSON/timeout/network, cache JWT (+49 menit sama, +51 menit baru, paralel satu tanda tangan), log tanpa token/JWT/nama.
- `push-deliver.test.ts`: 410 → token kosong; token baru (PATCH sebelum 410 selesai) tetap; baris `push_log` per hasil; sender throw → `failed:network`, tidak throw.
- `scans.test.ts`: Protected + Guardian bertoken → `push_log` `logged`; tanpa baris untuk scan Guardian sendiri / tanpa Guardian / Guardian tanpa token.

## Risiko
- DB di `waitUntil` setelah respons (Hyperdrive): dibuktikan lokal `wrangler dev` + cloud; fallback `createSql` baru di dalam `waitUntil`.
- Test flaky karena `waitUntil` melewati test → polling baris `push_log`.
- Cache JWT per isolate → `TooManyProviderTokenUpdates` mungkin kalau banyak isolate dingin; diterima untuk MVP.
- Bukti lokal: workerd lokal mungkin tidak HTTP/2 → `failed:network` dicatat; bukti cloud = LANGKAH MANUAL.

## LANGKAH MANUAL
Migrasi; secret APNs B7 lewat prompt `wrangler secret put`; `APNS_TOPIC` = bundle ID B6; `wrangler secret delete SPIKE_KEY`; deploy + `/debug/apns-spike` 404; smoke token palsu → `failed:400 BadDeviceToken`; D7 iPhone (C3/B6/B7) → `sent` + screenshot.
