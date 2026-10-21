# Fase 08 — Family: kode 4 digit, join, batas 3, members, disconnect, halaman undangan

| Field | Nilai |
|---|---|
| Track | be |
| Branch | `feat/BE-family` |
| Prasyarat | 07 |
| Requirement | Mandat Fase B Family; GD-04, PR-01, PR-03 (sisi server); keamanan "kode join dibatasi jumlah percobaannya" |
| Model | Opus 5.5 |
| Fase berikutnya | 09 |

## Tujuan

Guardian membuat kode yang berganti tiap 60 detik, Protected bergabung dengan kode/QR/link, maksimal 3 Protected per Guardian, kedua sisi bisa memutus koneksi, dan brute force kode ditahan.

## Bacaan wajib

- `contracts/api.md` Family + join errors, `fixtures/family-members.json`
- `ref/R2` (family_links, family_codes, join_attempts, I2–I4), `ref/R3` §1, §3, §4, §5, `ref/R4` §1–§2, `SECURITY.md` T2, T11, T12

## Output

- Repo `families.ts`, `codes.ts`, `joinAttempts.ts`; service `family.ts`; route `family.ts`, `join-page.ts`
- Migrasi tambahan bila perlu (indeks/trigger), pgTAP I2–I4
- Test vitest untuk semua cabang R4 §2

## Langkah kerja

1. `POST /family/code` (guardian): R4 §1. `{ code, expiresAt, inviteUrl }`, `inviteUrl = ${INVITE_BASE_URL}/join?code=` (D-alief-03).
2. `POST /family/join` (protected): R4 §2, error kontrak `code_invalid`, `code_expired`, `family_full`, `too_many_attempts` + `already_connected`. Kunci rate limit dari `CF-Connecting-IP` (lokal: header uji).
3. `GET /family/members` (guardian): `{ members: [{ deviceId, name, avatarId, extensionActive, lastScan? }] }` sesuai fixture; `extensionActive` sementara sesuai R3 §4 (D-alief-15).
4. `DELETE /family/members/{deviceId}` (guardian) dan `DELETE /family/guardian` (protected).
5. `GET /join?code=` HTML EN/ID kecil (tanpa JS pihak ketiga, CSP ketat) → tombol `shoo://join?code=`, kode besar, teks "Belum punya Shoo? Install dulu" (link App Store placeholder).
6. Usulan kontrak: D-alief-03 (`inviteUrl` https) dan D-alief-15 (`extensionLastSeenAt`) → tulis di PR "Contract proposals" + TODO C5.
7. `ecc:security-reviewer` fokus T2, T11, T12.

## Verifikasi

```bash
cd backend/db && supabase db reset && supabase test db
pnpm -C backend/api test -- family
```

Test wajib: kode 4 digit + kedaluwarsa 60 s (jam disuntik), kode multi-pakai, Protected ke-4 → `family_full`, 5 gagal → `too_many_attempts` (device dan IP terpisah), Guardian memanggil join → 403, Protected memanggil code → 403, sudah terhubung → 409, hapus member bukan milik → 404, setelah disconnect Guardian tidak melihat member itu, dua join paralel ke slot terakhir → hanya satu sukses (advisory lock).

## Kriteria selesai (DoD)

- [ ] Semua test di atas hijau.
- [ ] Respons cocok dengan `fixtures/family-members.json` (test snapshot bentuk).
- [ ] LANGKAH MANUAL deploy fase 08 tertulis; usulan C5 masuk PR.
