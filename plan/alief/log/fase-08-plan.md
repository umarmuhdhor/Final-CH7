# Rencana fase 08 — Family (feat/BE-family, stacked on #9)

Sumber: `fase-08-be-family.md`, `contracts/api.md` Family + Devices, `fixtures/family-members.json`, R2, R3 §1–§5, R4 §1–§2, SECURITY T2/T11–T13, §3 P3.

1. **Migrasi `20261021160000_family.sql`** (pgTAP dulu): `join_attempts.ip inet` → `ip_hash bytea` (sha256 `join:<ip /64>`, D-alief-B02 konsisten: tanpa IP mentah), indeks `(ip_hash, attempted_at desc)`, `join_attempts(attempted_at)`, `family_codes(expires_at)` untuk retensi fase 12.
2. **`POST /family/code`** (guardian, 403 protected): batas 6/menit per guardian (`hit`), transaksi: hapus kode lama guardian, pilih 4 digit acak tanpa bias, `insert … on conflict (code) do update … where expires_at < now()` (menimpa kode kedaluwarsa yang bentrok), maks 20 percobaan → 503 `code_unavailable`. Respons `{ code, expiresAt, inviteUrl }`.
3. **`POST /family/join`** (protected, 403 guardian): satu transaksi, advisory lock per device lalu per IP (urutan tetap → tanpa deadlock, percobaan paralel tidak lolos batas), R4 §2 urut: 429 `too_many_attempts` (+`Retry-After`, 5 gagal/10 menit per device dan per IP) → 409 `already_connected` → 404 `code_invalid` (catat gagal) → 410 `code_expired` (catat gagal) → lock guardian, ≥ 3 → 409 `family_full` → insert link, catat sukses → `{ guardian }`. Race PK/trigger dipetakan ke `already_connected`/`family_full`.
4. **`GET /family/members`**, **`DELETE /family/members/{id}`**, **`DELETE /family/guardian`**: akses selalu dari `family_links` saat request (T12); 404 kalau bukan milik.
5. **`GET /join?code=`**: HTML EN atau ID (Accept-Language), kode hanya kalau `^\d{4}$`, escape, CSP + `nosniff` + `no-store` + `no-referrer`; tidak memeriksa status kode.
6. **`GET /devices/me`** (kontrak) dan **`DELETE /devices/me`** (usulan C19): hapus device (cascade link, kode, percobaan, scan, verdict dibuat/ditujukan, push_log) dalam satu statement; path screenshot dikumpulkan untuk dihapus dari Storage setelah commit (placeholder sampai fase 09).
7. Test vitest per cabang (jam = `expires_at` digeser di DB), bentuk respons = fixture; pgTAP kolom baru.
8. Review: typescript + database + security (T2, T11, T12, T13). Verifikasi. LANGKAH MANUAL deploy (migrasi fase 07 + 08, Worker), lalu `[m]`.
