## Ringkasan

| Yang diukur | Hasil |
|---|---|
| Scam diblokir | **10 dari 21** halaman yang terbuka (48%). Target 70%: **gagal** |
| Scam skor ≥ 50 | **10 dari 21** (48%). Target 90%: **gagal** |
| Scam diberi peringatan saja | 2 dari 21 |
| Scam tanpa tanda | 9 dari 21 |
| Legit kena tanda | **0 dari 23**. Target 0: lulus |
| Waktu LLM | Median 1,4 detik, paling lama 4,5 detik |
| Error server | 0 |

## Pengaturan

- **Tanggal:** 3 Nov 2026, satu putaran, tiap link satu kunjungan.
- **Kode:** branch `feat/AI-M4-thinking-off-asks-otp-boxes`, commit `2c51aee` (PR #232 belum merge).
- **Simulator:** `Shoo QA L1-4`, iPhone 17 Pro, iOS 26.5, Safari dengan ekstensi build Debug.
- **Layer:** L1 mati. L2 `detector.js` apa adanya, termasuk batas 25 per bagian URL. L3 dan RDAP live dengan batas 1 detik. L4 `deepseek-v4-flash`, prompt `reality-check.v4`, thinking off.
- **Sampel:** 25 scam dan 23 legit dari `ai/test-layer2`.
- **Tunggu:** 20 detik per halaman, lalu screenshot.

### Beda dari plan

- **Port:** server tes memakai 8790, bukan 8788, karena 8788 dan 8789 dipakai proxy lama dari sesi lain.
- **Sesi palsu:** ditulis dengan `simctl spawn ... defaults write` saat simulator menyala. Tulisan dari Mac saat simulator mati hilang setelah simulator menyala lagi.
- **`page_type`:** tidak tercatat di v1 karena salah nama field di `server.mjs`. Sudah diperbaiki untuk versi berikutnya. Tidak memengaruhi skor.
- **Link asli:** plan K9 memakai domain yang disamarkan. Atas permintaan Imelda, tabel memakai URL asli yang bisa diklik, satu kolom.
- **`scam-19`:** dialog JavaScript menahan halaman. Tetap dihitung sebagai halaman terbuka tanpa tanda, karena pengguna asli juga melihat halaman itu tanpa peringatan.

### Batasan

- L1 mati, jadi skor scam yang biasanya kena daftar bisa lebih rendah daripada di produksi. `mit.edu` tidak diblokir di tes ini, tapi masalah daftarnya **belum** terbukti selesai.
- Tidak ada halaman legit yang mencapai 30, jadi jalur LLM baru **tidak teruji** di halaman legit.
- Sesi palsu, jadi alur Guardian, kirim scan, verdict, dan push tidak dites.
- LLM dan RDAP dipanggil dari Mac, bukan dari Cloudflare, jadi waktunya bisa beda dari produksi.
- Simulator, bukan iPhone asli.
- Hanya pemuatan halaman. Scam yang menampilkan form setelah diketuk tidak terlihat.
- Satu putaran. Situs juga bisa berubah sejak 31 Okt.
