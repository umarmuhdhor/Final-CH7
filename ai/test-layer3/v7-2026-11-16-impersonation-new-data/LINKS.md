# Link keluar ke aplikasi chat (t.me, wa.me, ...) sebagai sinyal tanpa LLM

_Dibuat oleh `links_measure.py report`. Halaman diambil ulang sekali (GET statis, tanpa JavaScript) hanya untuk menghitung link; HTML tidak disimpan. Model: v2, ambang kalibrasi luar, popular 1.000 aktif._

## Seberapa sering ada link chat

| Kelompok | Halaman | Terbuka lagi | Ada link chat (href) | Link chat hanya di script/onclick | Paling sering |
|---|---|---|---|---|---|
| scam_fresh_unseen | 856 | 846 | 144 (17%) | 2 | `wa.me` 78, `api.whatsapp.com` 63, `t.me` 3 |
| scam_fresh | 867 | 856 | 147 (17%) | 2 | `wa.me` 80, `api.whatsapp.com` 64, `t.me` 3 |
| legit_kaggle | 1500 | 1463 | 34 (2%) | 2 | `api.whatsapp.com` 10, `wa.me` 9, `t.me` 8 |
| legit_indonesian | 805 | 770 | 217 (28%) | 18 | `wa.me` 115, `api.whatsapp.com` 75, `t.me` 32 |
| legit_manual | 15 | 14 | 0 (0%) | 0 | - |

## Aturan yang dicoba

- **Model**: warn/block dari model v2 saja.
- **R1**: ada link chat (href atau script) langsung warn.
- **R2**: ada link chat **dan** kata klaim/CS/bansos/verifikasi di judul atau teks.
- **R3**: ada link chat **dan** model minimal `gate`.
- **R4**: ada link chat **dan** halaman sedikit link (paling banyak 15) atau minimal 30% link-nya ke chat (halaman yang isinya mengarahkan ke chat).

Halaman yang gagal dibuka lagi dihitung tanpa link (model saja).

| Aturan | scam_fresh_unseen | scam_fresh | legit_kaggle | legit_indonesian | legit_manual |
|---|---|---|---|---|---|
| Model | 581/856 (67,9%) | 582/867 (67,1%) | 62/1500 (4,1%) | 18/805 (2,2%) | 5/15 (33,3%) |
| R1 | 629/856 (73,5%) | 633/867 (73,0%) | 97/1500 (6,5%) | 246/805 (30,6%) | 5/15 (33,3%) |
| R2 | 613/856 (71,6%) | 617/867 (71,2%) | 65/1500 (4,3%) | 115/805 (14,3%) | 5/15 (33,3%) |
| R3 | 612/856 (71,5%) | 613/867 (70,7%) | 67/1500 (4,5%) | 33/805 (4,1%) | 5/15 (33,3%) |
| R4 | 585/856 (68,3%) | 586/867 (67,6%) | 63/1500 (4,2%) | 29/805 (3,6%) | 5/15 (33,3%) |


## Analisis

Ditulis 2026-11-16. **Terbukti** = angka dari tabel di atas. **Dugaan** = tafsir.

### Jawaban singkat

**Link t.me/wa.me tidak layak dijadikan aturan, dan tidak sepadan dengan perubahan kontrak `PageSnapshot`.** Situs Indonesia yang sah justru lebih sering memasang link WhatsApp daripada halaman scam.

### Terbukti

- Ada link chat: scam segar **17%**, legit Indonesia **28%**, legit global (Kaggle) 2%. Hampir semuanya WhatsApp (`wa.me`, `api.whatsapp.com`). Telegram jarang: 3 halaman scam, 32 halaman legit Indonesia.
- Aturan terbaik adalah R3 (link chat **dan** model minimal `gate`): scam naik dari 67,9% ke **71,5%** (+3,6 poin), tapi legit Indonesia naik dari 2,2% ke **4,1%** (+1,9 poin). Salah tanda di Indonesia hampir dua kali lipat demi 3,6 poin recall.
- R1 (link chat saja): legit Indonesia jadi 30,6%. R2 (link chat + kata klaim/CS): legit Indonesia 14,3%, karena toko sah juga menulis "customer service", "promo", "verifikasi". R4 (halaman pengarah ke chat): hampir tidak menambah apa-apa (+0,4 poin scam).

### Dugaan

- Pola scam yang lolos di v7 (bansos palsu, CS palsu) mirip sekali dengan toko dan layanan UMKM sah yang berjualan lewat WhatsApp. Membedakannya butuh isi pesan atau konteks, bukan sekadar ada atau tidaknya link.
- Kalau tetap ingin dipakai, R3 hanya layak sebagai banner ringan, bukan block, dan sebaiknya hanya untuk Telegram (`t.me`). Data Telegram di sini terlalu sedikit untuk disimpulkan (3 scam).

### Kesimpulan untuk "tanpa LLM"

Dari tiga sinyal tambahan yang diukur hari ini:
1. **Umur domain (`RDAP.md`):** layak. Aturan < 30 hari menambah sekitar 9 poin recall pada scam yang punya domain sendiri, dengan salah tanda hampir nol. Cakupannya hanya sekitar 17% scam.
2. **Latih ulang (`LATIH-ULANG-v2.md`):** layak. Salah tanda halaman parkir turun hampir separuh, recall +4 poin.
3. **Link t.me/wa.me (laporan ini):** tidak layak.
