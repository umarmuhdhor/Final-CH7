# Layer 3 v9: aturan alamat, tiruan + login = block, model lebih kecil (2026-11-18)

Branch `feat/l3-impersonation-model`, semua di belakang flag `SHOO_L3_MODEL=impersonation`. Model v2 tidak dilatih ulang.
Host scam disamarkan (`[.]`). Angka dari `shoo-impersonation-lab/eval_v3.py` (laporan lab: `out/impersonation-v3/eval-v3g-*.md`).

## 1. Kenapa hasil Mac dan iPhone beda

- Kode snapshot ekstensi (`dom.js` + `snapshot.js`) dijalankan di Chrome dengan UA iPhone, dibanding `parseHtml` pada **pemuatan yang sama**:
  10 link, selisih skor model paling besar 0,006, tier sama semua. Masking nomor/email juga tidak mengubah skor.
- Jadi bedanya bukan dari cara membaca halaman, tetapi:
  1. halaman yang disajikan berubah antar pemuatan (satu link `.co.id` mengalihkan ke `.com` dengan isi lain: 0,08 lalu 0,51);
  2. situs scam bisa menampilkan isi berbeda ke browser otomatis (log HP punya halaman 2 form + password yang tidak pernah muncul di Chrome Mac);
  3. bug lama di HP yang sudah diperbaiki (aiBaseURL kosong di Debug; form tersembunyi yang muncul belakangan tidak dicek ulang);
  4. persen di popup HP = layer 1-4, hitungan Mac hanya layer 3;
  5. memori blokir: situs yang pernah diblokir langsung ke layar blokir 14 hari tanpa `/analyze`, jadi tidak muncul di log server.
- Setelah perbaikan, log HP 2026-11-18 (host dicatat lokal) sama dengan Mac untuk 6 dari 6 link yang sampai ke server.

## 2. Aturan baru (setelah v3g + umur domain)

| Aturan | Isi | Scam segar unseen (856) | Legit tambahan yang ditandai |
|---|---|---|---|
| (awal) v3g + umur < 30 hari | | 66,5% | |
| Brand di domain orang lain | brand di host + halaman menyebut brand, bukan domain resmi/populer; lewati domain yang labelnya/TLD-nya = nama brand (google[.]org) dan domain kampus/pemerintah | 76,3% | iphoneincanada[.]ca (warn, tanpa input) |
| Kata pancingan di host | hadiah, undian, bansos, pemenang, klaim, pencairan, bantuan di bagian alamat yang dipilih pemilik; halaman juga harus menyebut brand/pancingan | **87,6%** | 0 |
| Tiruan + minta login = block | brand di domain orang lain **atau** logo brand di luar situs resmi, **dan** kolom password / minta password-OTP-PIN-kartu | block 274 → 275 | 0 yang baru diblokir |

- Kata Inggris (prize, giveaway, reward, claim) dibuang dari aturan host: hanya menangkap 5 scam dan semua salah tanda dari situ (nobelprize, giveawayoftheday).
- Versi "brand di judul + login = block" ditolak: memblokir 5 situs legit (trakteer, pajaknow, beritasatu, ...) karena "Masuk dengan Google".
- `mandirikartukredit.com` dicek manual: milik Mandiri, dianggap resmi oleh model.
- Legit Kaggle unseen tetap 44/17.410 (0,3%), legit Indonesia kalibrasi 12/805.

**Peringatan:** scam segar didominasi kit blogspot "hadiah"/"undian" (210 dan 163 halaman). Angka 87,6% kemungkinan terlalu optimis untuk jenis scam lain;
perlu sampel scam baru yang tidak dipakai merancang aturan. Phishing global berbahasa Inggris (set v6) masih 19,2%; fokus saat ini bahasa Indonesia.

## 3. Ukuran model

Bundle Worker (`wrangler deploy --dry-run`, gzip) harus di bawah 3 MB (Workers Free). Pemangkasan istilah sudah ditolak (469 tier berubah).

| Format blob (`export_js.py`) | Bundle gzip | Tier berubah (4.283 halaman) | Paritas JS vs sklearn, skor final |
|---|---|---|---|
| 1: hash/idf/coef float32 apa adanya | ±3.700 KiB | 0 | 0,00000 |
| 2: selisih hash varint + palet idf, coef float32 (lossless) | 3.069 KiB | 0 | 0,00000 |
| **2 + coef float16 (`--coef16`, dipakai)** | **2.336 KiB** | **0** | maks 0,0018 |

Format 2 tanpa float16 tidak dipakai karena hanya 3 KiB di bawah batas. 10 link uji memberi tier yang sama dengan format 1.

## 4. Layer 2 (tidak diubah)

Usulan penguatan `detector/` diukur di salinan, `detector/` tidak disentuh. Lihat `ISSUE-layer2.md`.
