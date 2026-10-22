# Fase 03 — Sinyal konten + `new_domain` (M3b)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M3-content` |
| Prasyarat | Fase 02. Jawaban Umar TODO C2 (layer `new_domain`) |
| Requirement | M3: `urgent_language`, `brand_logo_offsite`, `new_domain` |
| Review | `ecc:security-reviewer` wajib (lookup RDAP dari server) |
| Fase berikutnya | 04 |

## Tujuan

Tambah sinyal dari teks/judul/gambar halaman, dan umur domain lewat RDAP di server (bukan di HP, supaya riwayat browsing tidak bocor ke pihak ketiga dari perangkat user).

## Bacaan wajib

- `contracts/api.md`, `contracts/detector-interface.md` (tabel Known signal ids)
- `contracts/fixtures/blocked-92.json`, `warning-63.json`
- `detector/data/brands.json`

## Langkah kerja

1. **`urgent_language`**: frasa ID + EN ("diblokir dalam 24 jam", "klaim sekarang", "akun Anda akan ditutup"). `evidence` = potongan **persis** dari `snapshot.text`/title (di-stabilo extension; jangan parafrase).
2. **`brand_logo_offsite`**: nama brand di `imageAlts`/title, domain bukan domain resmi (`brands.json`). Domain resmi → tanpa sinyal.
3. **`new_domain`**: lookup RDAP di server; hasil di-cache per domain (TTL tertulis di DECISIONS). Bobot naik makin muda umur domain.
   - Layer: sampai TODO C2 dijawab, pakai layer sesuai kontrak (2) dan catat bahwa `pipeline.js` membuangnya; usulan layer 3 ada di TODO C2. Jangan edit kontrak.
   - RDAP gagal/timeout → tanpa sinyal, bukan error. Batas waktu pendek supaya p95 `/analyze` < 8 s.
   - Kirim hanya domain ke RDAP, bukan URL penuh.
4. Test dulu: positif/negatif per sinyal, RDAP di-mock (sukses, gagal, timeout, cache hit).
5. Target: `blocked-92.json` dan `warning-63.json` direproduksi kira-kira (sinyal sama, skor ±10).

## Verifikasi

```bash
node --test ai/ detector/test ai/eval/test ios/ShooExtension/Tests
node ai/eval/run.mjs --analyze-url http://localhost:8787
```

## Kriteria selesai (DoD)

- [ ] Tiga sinyal punya test positif + negatif; `evidence` urgent/brand persis dari teks (test string-equal).
- [ ] RDAP: cache dan fallback teruji; tidak ada URL penuh keluar dari server.
- [ ] Fixture `blocked-92` dan `warning-63` terpenuhi (±10).
- [ ] Layer 3 tetap menjawab saat RDAP mati.

## Catatan handoff

- Bobot awal; dikalibrasi di fase 07.
