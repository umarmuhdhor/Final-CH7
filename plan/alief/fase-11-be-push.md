# Fase 11 — Push APNs

| Field | Nilai |
|---|---|
| Track | be |
| Branch | `feat/BE-push` |
| Prasyarat | 10; keputusan spike D-alief-16 (fase 07) |
| Requirement | Mandat Fase B Push; GD-06 (sisi server), PRD §9 |
| Model | Opus 5.5 |
| Fase berikutnya | 12 |

## Tujuan

Saat device Protected memanggil `POST /scans`, Guardian-nya menerima push "[Mom] hit a blocked site · 92%" / "[Mom] opened a suspicious site · 41%" dalam bahasanya, dengan `scanId` untuk membuka Detail.

## Bacaan wajib

- `contracts/api.md` Push payloads, PRD §9, §8.3 GD-06
- `ref/R3` §6–§7, `ref/R4` §3, `SECURITY.md` T9, `log/DECISIONS.md` D-alief-16 + hasil spike `D-alief-B01` (fase 07)
- Docs Apple: "Sending notification requests to APNs", "Establishing a token-based connection to APNs", "Handling notification responses from APNs" (lewat `ecc:documentation-lookup`)
- Docs Supabase: Edge Functions (`supabase functions new/serve/deploy`, `supabase secrets set`, `--no-verify-jwt`)

## Output

- `services/push/{sender,relay,log,messages}.ts` (jalur utama, D-alief-16) + `backend/db/supabase/functions/push/index.ts` (Edge Function Deno)
- `services/push/apns.ts` (`ApnsSender` langsung) HANYA kalau `D-alief-B01` = spike lulus; selain itu tidak dibuat
- `src/routes/debug-apns.ts` dan route-nya **dihapus** (spike selesai di fase 07)
- Pemilihan sender di `app.ts`: `PUSH_RELAY_URL` + `PUSH_RELAY_SECRET` ada → `RelaySender`; (spike lulus + secret APNs ada → `ApnsSender`); tidak ada → `LogSender`
- Test vitest: teks EN/ID, payload, tidak ada push untuk scan Guardian sendiri, tidak ada push kalau Protected belum punya Guardian / Guardian tanpa `apns_token`, relay menjawab `410 Unregistered` atau `410 ExpiredToken` → `apns_token` dikosongkan, relay 401 → `push_log` `failed:401`, `400 BadDeviceToken` → token tetap + `push_log`, relay/APNs error tidak menggagalkan `POST /scans`, secret relay tidak pernah muncul di log
- Test Deno (`deno test` di `functions/push/`): tanpa/salah `x-push-secret` → 401, body invalid → 400, status APNs diteruskan apa adanya ke Worker

## Langkah kerja

1. `messages.ts`: R3 §6. Nama pemilik = `devices.name` Protected.
2. **Edge Function `push` (jalur utama).** `(cd backend/db && supabase functions new push)`. Menerima `POST { apnsToken, body, scanId }` + header `x-push-secret` (dibandingkan constant-time dengan secret `PUSH_RELAY_SECRET`). Membuat JWT ES256 dari secret `APNS_KEY_P8_B64` (PEM `.p8` di-encode base64 satu baris, di-decode di fungsi) / `APNS_KEY_ID` / `APNS_TEAM_ID` (`crypto.subtle.importKey('pkcs8', …)`, header `kid`, klaim `iss`, `iat`, cache ±50 menit), `fetch` HTTP/2 ke `https://api{.sandbox}.push.apple.com/3/device/<token>` sesuai `APNS_ENV`, header R3 §6, mengembalikan `{ status, reason }` dari APNs. Tambah `[functions.push]` + `verify_jwt = false` di `backend/db/supabase/config.toml` (berlaku untuk `serve` dan `deploy`; auth lewat shared secret, bukan JWT Supabase), dan tetap pakai `--no-verify-jwt` saat deploy.
3. **`RelaySender`** di Worker: `fetch(PUSH_RELAY_URL, { headers: { 'x-push-secret': … } })`, timeout 5 s. Hanya status 410 (`Unregistered` / `ExpiredToken`) mengosongkan token; `400 BadDeviceToken` dicatat saja (R3 §6). `ApnsSender` langsung hanya kalau `D-alief-B01` = lulus (logika sama, tanpa relay).
4. Panggil sender dari `POST /scans` lewat `c.executionCtx.waitUntil`, tulis `push_log` (`sent`/`failed`/`logged` + reason, tanpa token/secret).
5. Hapus `debug-apns.ts` dan var `APNS_SPIKE` dari `wrangler.jsonc`/README; LANGKAH MANUAL langkah 8 menjalankan `npx wrangler secret delete SPIKE_KEY`.
6. Contract note C9 (push dilokalkan + `sound` aditif).
7. Uji lokal: `(cd backend/db && supabase functions serve push --no-verify-jwt --env-file ./supabase/functions/.env.local)` (file gitignored, berisi secret uji), Worker lokal dengan `PUSH_RELAY_URL=http://127.0.0.1:54321/functions/v1/push` → `POST /scans` dari Protected → `push_log` berisi status APNs (token dummy → `BadDeviceToken` membuktikan jalur lengkap).
8. LANGKAH MANUAL (tulis di log, berhenti): B7 (`.p8` sandbox). Kunci privat TIDAK diketik sebagai argumen: buat file sementara di luar repo (`umask 077; printf 'APNS_KEY_P8_B64=%s\n' "$(base64 < AuthKey_XXXX.p8 | tr -d '\n')" > ~/shoo-push.env`, tambah `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC=<SHOO_BUNDLE_ID build iPhone Alief>`, `APNS_ENV=sandbox`, `PUSH_RELAY_SECRET`), `supabase secrets set --env-file ~/shoo-push.env`, lalu `rm ~/shoo-push.env`; `supabase functions deploy push --no-verify-jwt`, `wrangler secret put PUSH_RELAY_SECRET`, `wrangler secret delete SPIKE_KEY`, var `PUSH_RELAY_URL`, deploy Worker. Lalu D7: build Debug ke iPhone Alief (butuh C3 + B6; tim yang sama dengan kunci B7), ambil token dari log Xcode, `PATCH /devices/me` sebagai Guardian uji, `POST /scans` sebagai Protected → screenshot notifikasi.

## Verifikasi

```bash
(cd backend/db && supabase start)
pnpm -C backend/api exec vitest run push
(cd backend/db/supabase/functions/push && deno test --allow-env)
grep -rn "x-push-secret\|APNS_KEY_P8_B64" backend/api/src | grep -v "env\.\|c\.env" || true   # tidak ada nilai literal
```

## Kriteria selesai (DoD)

- [ ] Semua test vitest + Deno hijau; payload = kontrak + `sound` (aditif, C9).
- [ ] Uji lokal langkah 7: `push_log` mencatat respons APNs asli dari relay lokal.
- [ ] Endpoint spike sudah dihapus (`grep -rn apns-spike backend/` kosong).
- [ ] Bukti satu push sandbox nyata di iPhone Alief (screenshot) ATAU PR dibuka dengan status `[r]` + "pending B6/B7/C3" di Ringkasan (PROMPT 6h) — uji perangkat diulang di fase 15 / G7.
