# Fase 05 — Layer 1 sisi server: `GET /public-blocklist?since=` (M5-A)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M5-server` |
| Prasyarat | Fase 02 (service ada). Pilihan sumber daftar (TODO A3) |
| Requirement | M5 bagian A |
| Review | `ecc:security-reviewer` wajib |
| Fase berikutnya | 06 |

## Tujuan

Server menyediakan daftar domain phishing publik untuk diunduh extension (`lists.js` milik Umar). Kita **tidak** memanggil `GET /blocklist` Alief dan tidak mengurus unduh/simpan/refresh di HP.

## Bacaan wajib

- `docs/design/blocklist.md`, `contracts/api.md` (bagian Blocklist)
- `detector/data/brands.json` (allowlist), `ios/ShooExtension/Resources/lists-client.js`

## Langkah kerja

1. **LANGKAH MANUAL:** Imelda menyetujui sumber daftar phishing publik (lisensi boleh dipakai di app). Catat sumber + lisensi di `ai/README.md`.
2. Ubah tiap entri ke registrable domain (Public Suffix List).
3. Buang allowlist: domain di `brands.json`, 100 situs populer, dan situs sah yang hanya disusupi (mis. `wordpress.com`, `github.io` tanpa subdomain). Test dulu: domain resmi tidak pernah muncul.
4. Respons persis `{ domains: [{ domain, addedAt }], removed?: [{ domain, removedAt }], nextSince }`; `since` kosong = daftar lengkap; target ≤ 200.000 domain.
5. Token Bearer dari extension tidak diverifikasi dan tidak dilog. Rate limit per IP.
6. Test: penuh, inkremental (`since`), `removed`, domain allowlist, ukuran.

## Verifikasi

```bash
node --test ai/
curl -s "http://localhost:8787/public-blocklist" | head -c 400
```

## Kriteria selesai (DoD)

- [ ] Bentuk respons persis kontrak (test dengan skema).
- [ ] Tidak ada domain allowlist di keluaran.
- [ ] Sumber + lisensi tercatat; token tidak dilog.
- [ ] ≤ 200.000 domain; waktu respons wajar.
