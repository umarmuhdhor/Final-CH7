# Fase 05 — `/public-blocklist` (M5-A)

**Status:** `[m]` kode + test selesai; sisa LANGKAH MANUAL (sumber daftar + lisensi, A3).
**Branch:** `feat/AI-M5-server` dari `wip/AI-overnight-base` (stacked, lihat DECISIONS). Dikerjakan semalaman 22 Okt 2026.

## Rencana (dijalankan)
1. Riset lisensi 4 kandidat dari halaman resmi (tanpa unduh feed). Tabel di `ai/README.md`.
2. Test dulu (`ai/test/blocklist.test.mjs`, 19 test), lalu implementasi di balik `src/blocklist/source.js`.
3. Sumber produksi = daftar kosong; dev = fixture karangan. Tidak ada feed nyata.

## File
Baru: `ai/src/blocklist/{source,fixture,domains,allowlist,build,route}.js`, `ai/src/ratelimit.js`, `ai/data/public-blocklist.seed.json`, `ai/test/blocklist.test.mjs`.
Diubah: `ai/src/{app,index,dev-server}.js(mjs)`, `ai/README.md`, `plan/imelda/log/DECISIONS.md` (D-imelda-23..26).

## Riset sumber (22 Okt 2026, halaman resmi)
Lihat tabel di `ai/README.md`. Ringkas: OpenPhish melarang pemakaian komersial; PhishTank memakai EULA Cisco tanpa lisensi data (BELUM DIVERIFIKASI); URLhaus "fair use", komersial mungkin berbayar (BELUM DIVERIFIKASI); Phishing Army CC BY-NC menurut katalog pihak ketiga. Rekomendasi: tanyakan PhishTank dulu; minta izin tertulis bila tidak jelas.

## Verifikasi
- `node --test --test-concurrency=1 detector/test ai/test ai/eval/test ios/ShooExtension/Tests`: 346 lolos, 0 gagal (baseline 327 + 19 baru).
- `curl http://127.0.0.1:8791/public-blocklist`: bentuk `{domains,nextSince}`; `?since=2026-10-06T08:00:00Z` memberi domain baru + `removed` + `nextSince`; `?since=bad` = 400.
- Performa: 250.000 entri mentah -> bangun daftar 1,0 s (sekali per 5 menit), respons 14,8 MB, 12 ms dari cache. **Catatan M7:** bangun 1 s melebihi batas CPU paket gratis Workers; butuh paket berbayar atau daftar pra-bangun (KV/R2). Dengan daftar kosong tidak ada masalah.
- Catatan: tes performa NFKC di `content.test.mjs` bisa gagal bila dijalankan paralel dengan `ai/eval/test` (CPU); gunakan `--test-concurrency=1`.

## Review keamanan (`ecc:security-reviewer`, 22 Okt 2026)
Diperbaiki (+5 test, 351 total hijau): HIGH-1 allowlist melewatkan CDN/platform non-PSL (sharepoint.com, googleapis.com, youtu.be, t.me, wa.me, linktr.ee...) -> ditambah; HIGH-2 `addedAt` di masa depan / sebelum 2000 memarkir kursor klien -> ditolak (2000..sekarang+1 hari); MED-3 IPv4-mapped IPv6 -> dihitung sebagai IPv4; MED-5 sumber gagal dicoba ulang tiap request -> jeda 60 s; LOW-10 `since` wajib ISO 8601 UTC ketat.
Ditunda (tercatat, bukan MVP): MED-3 rate limit per isolate bisa dilewati dengan banyak /64 dan tidak berlaku lintas isolate -> kontrol sesungguhnya = aturan rate limit Cloudflare (checklist fase 08); MED-4 bangun 200k + serialisasi di jalur request -> daftar pra-bangun + cache edge di fase 08 (sumber nyata belum ada, jadi tidak berdampak sekarang); MED-6 `addedAt` dari feed vs waktu pertama terlihat -> kewajiban implementasi sumber (LANGKAH MANUAL); LOW-7 merge tanpa urutan waktu removedAt; LOW-11 `removed` tanpa batas.

## DoD
- [x] Bentuk respons persis kontrak (test bentuk + semua kasus).
- [x] Tidak ada domain allowlist di keluaran (test: semua domain `brands.json`, subdomainnya, situs populer, platform apex, suffix).
- [ ] Sumber + lisensi tercatat: riset tercatat, **pemilihan belum** (LANGKAH MANUAL). Token tidak dilog (test).
- [x] ≤ 200.000 domain; waktu respons wajar (lihat di atas).

## LANGKAH MANUAL (Imelda)
- [ ] Pilih sumber (A3): baca EULA PhishTank / minta izin tertulis; catat sumber + lisensi di `ai/README.md`.
- [ ] Tulis implementasi `BlocklistSource` untuk sumber terpilih (satu file, `entries()` -> `[{host, addedAt, removedAt?}]`) dan pasang di `ai/src/index.js`; penarikan feed harus terjadwal (bukan per permintaan) dan mencatat `addedAt` = waktu pertama terlihat.
- [ ] Putuskan tempat daftar pra-bangun (lihat catatan performa) di fase 08.

## Catatan handoff
- Umar: `ai/src/blocklist/domains.js` mengimpor `ios/ShooExtension/Resources/{psl,domain}.js` (read-only). Jangan pindahkan tanpa kabar. (TODO §C)
- Tanpa `removedAt` dari feed nyata, `removed[]` hanya terisi bila sumber melaporkannya; sumber harus mengingat entri yang hilang dari feed.
