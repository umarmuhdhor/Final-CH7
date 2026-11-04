# Tes live L1-L4 di simulator

Tes deteksi Shoo di Safari simulator dengan ekstensi sungguhan dan situs asli. Pemilik: **Imelda** (`ai/`).

## Daftar versi

| Versi | Tanggal | Commit | Yang berubah | Scam diblokir | Legit kena tanda | Status |
|---|---|---|---|---|---|---|
| [v1](v1/HASIL.md) | 3 Nov 2026 | `2c51aee` | Tes pertama: gate L4 30-79, flag selalu memblokir, RDAP 1 detik, L1 mati | 10 dari 21 (48%) | 0 dari 23 | Selesai, target scam belum tercapai |

## Susunan folder

```text
ai/test-layer-live/
├── README.md        # daftar versi ini
├── scripts/         # skrip tes, dipakai semua versi
└── v1/
    ├── PLAN.md      # rencana versi ini
    ├── PROMPT.md    # prompt untuk menjalankannya di chat baru
    ├── HASIL.md     # laporan
    ├── data.json    # data per link, tanpa teks halaman
    ├── ss/          # satu screenshot per link
    └── .raw/        # log mentah, di-gitignore
```

## Aturan versi

- Tes penuh selalu jadi versi baru (`v2`, `v3`, ...). Versi lama tidak ditimpa.
- Tiap versi punya `PLAN.md` dan `PROMPT.md` sendiri. Plan versi baru disalin dari versi sebelumnya, lalu diberi bagian "Beda dari vN" di paling atas.
- Setelah versi dijalankan, plan-nya tidak diedit lagi. Kalau rencana berubah di tengah jalan, tulis perubahannya di `HASIL.md`.
- Tes ulang satu link tetap di versi yang sama, di bagian "Tes ulang" pada `HASIL.md`. Hasil awalnya tidak diganti.
- Setiap versi selesai, tambahkan satu baris di tabel atas.
