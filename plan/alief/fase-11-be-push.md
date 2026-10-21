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
- `ref/R3` §6–§7, `ref/R4` §3, `SECURITY.md` T9
- Docs Apple: "Sending notification requests to APNs", "Establishing a token-based connection to APNs" (lewat `ecc:documentation-lookup`)

## Output

- `services/push/{sender,apns,log,messages}.ts` (+ `relay.ts` dan `backend/db/supabase/functions/push/index.ts` HANYA kalau D-alief-16 = fallback)
- Pemilihan sender di `app.ts`: secret APNs ada → `ApnsSender` (atau `RelaySender`), tidak ada → `LogSender`
- Test: teks EN/ID, payload, tidak ada push untuk scan Guardian sendiri, tidak ada push kalau Protected belum punya Guardian / Guardian tanpa `apns_token`, token ditolak APNs → `apns_token` dikosongkan, error APNs tidak menggagalkan `POST /scans`

## Langkah kerja

1. `messages.ts`: R3 §6. Nama pemilik = `devices.name` Protected.
2. `ApnsSender`: JWT ES256 (`crypto.subtle.importKey('pkcs8', …)`, header `kid`, klaim `iss` = Team ID, `iat`), cache JWT ±50 menit di memori isolate, `POST https://api{.sandbox}.push.apple.com/3/device/<token>`, header R3 §6. Respons 410/`BadDeviceToken` → kosongkan token.
3. Fallback (kalau spike gagal): Edge Function Deno `push` menerima `{ apnsToken, body, scanId }` + header `x-push-secret`, memakai `jsr:@negrel/apns` atau HTTP/2 `fetch` Deno; Worker memanggilnya via `RelaySender`.
4. Panggil sender dari `POST /scans` lewat `ctx.waitUntil`, tulis `push_log`.
5. Contract note C9 (push dilokalkan).
6. LANGKAH MANUAL: B7 (`.p8` → `wrangler secret put`), uji push ke iPhone Alief (butuh build dengan capability Push, C3); sampai itu cukup bukti `push_log` + test.

## Verifikasi

```bash
pnpm -C backend/api test -- push
```

## Kriteria selesai (DoD)

- [ ] Semua test hijau; payload persis kontrak + `sound`.
- [ ] Bukti satu push sandbox nyata diterima (screenshot iPhone) ATAU status `[~]` dengan alasan (B6/B7/C3 belum) dan `push_log` menunjukkan `logged`.
