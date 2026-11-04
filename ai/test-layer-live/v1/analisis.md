## Analisis

**Terbukti** = terukur di log atau screenshot tes ini. **Dugaan** = penjelasan saya, belum diuji.

### Kesimpulan

Arsitektur baru menaikkan blokir scam dari 7 menjadi 10 dari 21 walau L1 dimatikan, tanpa salah tanda di legit. Target 70% belum tercapai. Sisa masalah terbesar ada di halaman yang totalnya di bawah 30, karena LLM tidak pernah ditanya di sana.

### Terbukti

**1. Semua blokir bergantung pada LLM.** Tanpa flag L4, total tertinggi hanya 74 (`scam-03` dan `scam-21`), jadi tidak ada yang mencapai 80. Kalau LLM mati atau timeout, 10 blokir ini turun menjadi peringatan.

**2. Aturan "flag selalu memblokir" menentukan 5 halaman.** `scam-08`, `scam-09`, `scam-13`, `scam-14`, dan `scam-22` berhenti tepat di 80. Dengan bobot flag tetap 30, skornya 70, 66, 76, 67, dan 63, jadi hanya peringatan.

**3. Dibanding 31 Okt.**

| Perubahan | Link |
|---|---|
| Naik ke blokir | `scam-08` (dulu kosong), `scam-13` (76), `scam-14` (67), `scam-22` (63) |
| Tetap blokir, sekarang tanpa L1 | `scam-09`, `scam-21` |
| Tetap blokir | `scam-03`, `scam-05`, `scam-12`, `scam-16` |
| Turun | `scam-10` (blokir L1 menjadi 12), `scam-18` (45 menjadi 25), `scam-20` (45 menjadi 15) |

`scam-15` juga baru terbaca sebagai peringatan 30, karena dulu kosong. `scam-19` dulu diadang Safari, sekarang dialog JavaScript menahan halamannya.

**4. Gate 30 membuat `scam-20` lolos.** Login Instagram palsu ini mendapat total 15, jadi LLM tidak ditanya. Pada 31 Okt, gate lama bertanya karena ada form, dan flag +30 membawanya ke 45. Ini kasus yang sama dengan temuan tes perbandingan.

**5. Enam halaman scam punya sinyal, tapi total di bawah 30.** Totalnya: `scam-10` 12, `scam-20` 15, `scam-23` 13, `scam-24` 24, `scam-17` 24, `scam-18` 25. LLM tidak ditanya di semuanya. `scam-06` dan `scam-11` malah bertotal 0.

**6. Batas confidence 0,7 melewatkan satu halaman.** `scam-15` (form OTP) dijawab tidak wajar dengan confidence 0,6, jadi tetap 30. Dua halaman lain lolos tepat di 0,7 (`scam-12` dan `scam-16`).

**7. RDAP 1 detik habis di 3 dari 25 lookup.** `scam-15`, `scam-18`, dan `legit-19`. `scam-18` tidak mendapat `new_domain`, padahal pada 31 Okt mendapat +20.

**8. Waktu aman.** LLM paling lama 4.542 ms dan `/analyze` paling lama 5.343 ms, di bawah batas server 6,5 detik. Biaya: 12 panggilan LLM, 27.191 token, rata-rata 2.266 token per panggilan.

**9. Skor di layar cocok dengan log.** Semua halaman yang menampilkan persen sama dengan total hitungan `pipeline.js`.

### Dugaan

- **`scam-10`:** halaman jelas meminta OTP lewat 6 kotak, tapi `asks_otp` tidak menyala. Mungkin kotaknya muncul setelah snapshot, atau bentuk field-nya tidak dikenali. Perlu dicek dengan membaca snapshot halaman ini.
- **`scam-18`:** penurunan ke 25 kemungkinan besar karena RDAP timeout, bukan karena umur domainnya berubah. Satu putaran belum cukup untuk memastikan.
- **`scam-23` dan `scam-24`:** form nama dan telepon untuk Telegram kemungkinan tidak punya sinyal L3 yang cocok.

Penyebab total 0 di `scam-06` (login KlikBCA di `sites[.]google[.]com`) belum diselidiki.

### Pilihan untuk v2

Belum diterapkan. Ini keputusan Imelda.

1. **Tanya LLM di bawah 30 kalau ada form sensitif**, supaya `scam-20` tertangkap lagi. Risikonya biaya naik, dan perlu dites ke legit.
2. **Perbaiki deteksi OTP** untuk `scam-10`, sesudah penyebabnya dicek.
3. **Tinjau batas 0,7 dan RDAP 1 detik** dengan lebih banyak data. Satu putaran ini belum cukup untuk mengubah angkanya.
4. **Rencanakan saat LLM mati**, karena semua blokir sekarang bergantung padanya.
5. **Tambah halaman legit yang punya form** ke sampel, karena jalur LLM belum teruji di legit.
