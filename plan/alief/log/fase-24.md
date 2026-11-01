# Log fase 24 — Privasi dan data (E6, E7, C22)

- **Status:** [r] 24c-1 PR `fix/E6-privacy-contact`, reviewer @umarmuhdhor, **pending LANGKAH MANUAL 1–2 (mailbox K10 belum ada)** · 24a-1/24a-2 dan 24b tidak dikerjakan sesi ini (brief track be: skip 24a; 24b/24c-2 = app) .
- **Model:** Claude Opus 5.5, sesi track be. 1 Nov 2026.
- **Rencana:** `fase-24-privacy-data.md` (PR #207).
- **Keputusan K:** R8 §c (D-alief-C29): K10 (a) mailbox tim gratis (belum dibuat → LANGKAH MANUAL 1), K11 (a) tetap `workers.dev`, K12 isian App Privacy ditanyakan ke Umar (E6). Tidak ada D-alief baru.

## 24c-1 — `fix/E6-privacy-contact` (dari `origin/main` aa976af)

Mailbox K10 belum ada, jadi alamat kontak **tidak** diganti di PR ini. Supaya penggantian nanti satu baris, `CONTACT` di `routes/privacy.ts` diekspor dan dipakai bersama `/privacy` dan `/support`.

### Checklist langkah (Langkah kerja 22–23 file fase, disesuaikan)

- [x] 22. Merah: `test/support.test.ts` — `GET /support` 200, HTML, CSP `default-src 'none'`, `nosniff`, `private, no-store` (sama dengan `/privacy`), EN default + `?lang=id` + `Accept-Language: id`, memuat `CONTACT`, "Profile → Delete account" / "Profil → Hapus akun", cara putus keluarga, link `/privacy` dan `/terms`, tanpa `<script`; `CONTACT` sama di `/privacy`. 3/3 merah.
- [x] 23. Hijau: `routes/support.ts` (memakai `legalPage` + `pageLanguage`), didaftarkan di `app.ts`; `CONTACT` diekspor. `API.md` + `README.md` (tabel endpoint).
- [ ] 22b. Test "kontak = mailbox K10, tanpa 'coming before public release'": menunggu LANGKAH MANUAL 1.

### Verifikasi

| Perintah | Hasil |
|---|---|
| `npx tsc --noEmit` (`backend/api`) | bersih |
| `vitest run test/support.test.ts test/privacy.test.ts` | 8/8 (support tanpa route: 3 merah) |
| `vitest run` (suite penuh) | 538 lulus, 1 skip |

### Review

| Reviewer | Temuan | Tindakan |
|---|---|---|
| `ecc:typescript-reviewer` | HIGH: "Guardian atau orang yang dilindungi … ketuk Putuskan koneksi" salah — di app hanya Guardian yang bisa memutus (`ProfilePages.swift:814`, Protected terkunci). MEDIUM: Guardian yang masih punya anggota harus memutus dulu sebelum Hapus akun. LOW: "dihapus seketika" untuk file (R2/Storage dihapus setelah commit, retry cron). Label app cocok (`Localizable.xcstrings`); `legalPage` raw HTML aman (teks statis); header sama dengan `/privacy` | Semua diperbaiki EN + ID: Guardian memutus; Protected minta Guardian atau hapus akun; kalimat "Guardian dengan anggota memutus dulu"; "removed from our server right away". Test memaku kalimat baru |

### Privasi Apple (SECURITY §3)

- Halaman statis, tanpa DB, tanpa log baru, header sama dengan `/privacy` (`private, no-store`, CSP ketat).
- Kontak tetap placeholder (bukan alamat pribadi siapa pun; K10 menolak alamat pribadi).

## LANGKAH MANUAL

- [ ] 1. **(Alief)** Buat mailbox tim K10 (a): alamat baru di layanan email gratis, khusus tim, bukan alamat pribadi siapa pun; simpan login di password manager tim. Catat alamatnya di sini.
- [ ] 2. **(Alief, PR kecil setelah 1)** Ganti satu baris `CONTACT` di `backend/api/src/routes/privacy.ts` ke alamat itu (berlaku untuk `/privacy` dan `/support`), hapus `TODO(sync:alief)`, tambah test "kontak = mailbox, tanpa 'coming before public release'" di `privacy.test.ts` + `support.test.ts`, ubah tanggal "Last updated" `/privacy` (test `privacy.test.ts` ikut). 24c-2 (app, `AppConfig.supportEmail`) memakai alamat yang sama.
- [ ] 3. **(Alief, setelah merge + CI deploy)** `curl -s https://shoo-api.afindo-mi01.workers.dev/support | grep -o '<h1>[^<]*'` → "Shoo support"; `?lang=id` → "Bantuan Shoo".
- [ ] 4. **(Umar)** Jawab pertanyaan E6 di PR 24c-1 (`## Questions for Umar`, D-alief-C29).
