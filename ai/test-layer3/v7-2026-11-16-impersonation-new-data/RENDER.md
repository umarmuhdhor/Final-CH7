# Iterasi 3: cek ulang dengan halaman yang dirender

_Dibuat oleh `render_check.py report`. Chrome headless memuat halaman (JavaScript jalan, 8 detik, tanpa klik/ketik), teks DOM diambil dengan `parseHtml` (sama seperti snapshot eval). HTML tidak disimpan. Halaman = yang ditandai v2 tapi diturunkan v3f ke `gate` karena tidak ada klaim di teks statis._

**Kembali ditandai** = di teks render ada klaim v3f atau nama brand dari `brands.json` (termasuk 4 brand baru) di host yang bukan domain brand itu.

| Set | Label | Halaman | Gagal render | Kembali ditandai |
|---|---|---|---|---|
| fresh | scam | 29 | 0 | 15 |
| fresh | legit | 4 | 0 | 0 |
| legit_kaggle1500 | legit | 36 | 13 | 3 |
| legit_indonesian | legit | 7 | 0 | 0 |
| legit_kaggle17k | legit | 150 | 53 | 12 |

## Halaman yang kembali ditandai

| Set | Label | Alasan | Host | Judul render |
|---|---|---|---|---|
| fresh | scam | google | `characteraiitcom[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Insight Pilihan Deposit 5 |
| fresh | scam | google | `fitchettfilm[.]pages[.]dev` | allisonsabia |
| fresh | scam | google | `jimshandyman[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Modal Minim Deposit 5000  |
| fresh | scam | google | `kerryfreeman[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Insight Pilihan Deposit 5 |
| fresh | scam | google | `rawindowtint[.]pages[.]dev` | rui7083 |
| fresh | scam | google | `seweasyus[.]com` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| fresh | scam | google | `seweasyus[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| fresh | scam | google | `theanimealley[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Insight Pilihan Deposit 5 |
| fresh | scam | google | `therebelinyou[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Insight Pilihan Deposit 5 |
| fresh | scam | google | `tncar2money[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| fresh | scam | google | `worldgettogether[.]pages[.]dev` | rui7083 |
| fresh | scam | google | `zkgroup-consulting[.]com` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| fresh | scam | google | `zodiacfree[.]com` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| fresh | scam | google | `zkgroupconsulting[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| fresh | scam | google | `zodiacfree[.]pages[.]dev` | GANDACUAN : Slot Depo 5k Situs Slot Deposit 5000 D |
| legit_kaggle1500 | legit | kata | `www[.]timfletcher[.]com` | Tim Fletcher Co. / Understanding and Overcoming Co |
| legit_kaggle1500 | legit | google | `indianexpress[.]com` | Video: Sumo wrestlers getting babies to cry is wei |
| legit_kaggle1500 | legit | meta | `lisa[.]revues[.]org` | Le discours parlementaire sur l’emploi et les droi |
| legit_kaggle17k | legit | google | `artandpopularculture[.]com` | Lynn Taitt - The Art and Popular Culture Encyclope |
| legit_kaggle17k | legit | kata | `www[.]lakevermilionrealestate[.]com` | Home / Lake Vermilion Real Estate |
| legit_kaggle17k | legit | google | `artandpopularculture[.]com` | 1894 - The Art and Popular Culture Encyclopedia |
| legit_kaggle17k | legit | kata | `dmsretail[.]com` | Retail Management Success Site – Retail Mgmt. Succ |
| legit_kaggle17k | legit | google | `artandpopularculture[.]com` | Multi-instrumentalist - The Art and Popular Cultur |
| legit_kaggle17k | legit | google | `artandpopularculture[.]com` | François Lemoyne - The Art and Popular Culture Enc |
| legit_kaggle17k | legit | google | `charlesdentalgroup[.]com` | Charles Dental Group · Fair Oaks dentist since 197 |
| legit_kaggle17k | legit | meta | `hauntedcornmaze[.]com` |  |
| legit_kaggle17k | legit | kata | `artandpopularculture[.]com` | Cinema of Italy - The Art and Popular Culture Ency |
| legit_kaggle17k | legit | google | `indianexpress[.]com` | #ThankYouPM trends on Twitter post India’s swift r |
| legit_kaggle17k | legit | kata | `artandpopularculture[.]com` | Tales of Count Lucanor - The Art and Popular Cultu |
| legit_kaggle17k | legit | google | `indianexpress[.]com` | Video: Indian woman with 7 ft long hair aspires to |

## Analisis

Ditulis 2026-11-16.

### Terbukti

- 226 halaman dirender, 160 berhasil. Yang gagal kebanyakan Kaggle lama (domain mati).
- **"Tiruan Pinterest" ternyata bukan tiruan Pinterest.** Saat dirender, 13 dari 15 halaman `pages.dev`/`.com` itu berisi halaman judi slot ("GANDACUAN : Slot Depo 5k"). Screenshot cek mata sebelumnya menampilkan Pinterest, jadi halaman ini berganti isi atau menyamar (cloaking). Jenisnya judi, bukan pencurian akun.
- Halaman itu "kembali ditandai" hanya karena ada kata `google` di teks render. Ini kebetulan, bukan klaim brand.
- **Nama brand di mana saja dalam teks render terlalu berisik:** 15 dari 131 halaman legit yang berhasil dirender ikut kembali ditandai (sekitar 11%). Contohnya ensiklopedia, berita, dan dokter gigi yang menyebut Google/Facebook di isi atau footer. Jadi klaim brand v3 tetap harus dibatasi ke judul, host, logo, dan teks yang meniru (sinyal `brandsInText`/`brandTextOffsite` dari pipeline Shoo), bukan sekadar menyebut nama.
- Kata judi (`is_adult_gambling` dari train2) di teks render: scam 15/29, legit 9/131. Legit yang kena kemungkinan judi di domain yang diambil alih, sama seperti temuan cek mata.

### Kesimpulan

- Render tidak mengubah keputusan iterasi 3: v3f tetap dipakai, dan klaim brand **tidak** diperluas ke seluruh teks.
- Celah yang tersisa di feed segar kebanyakan **judi slot yang menyamar**, bukan peniruan brand. Kalau Shoo mau memberi banner untuk judi, itu aturan terpisah (kata judi → warn), bukan bagian model impersonation. Keputusan produk.
- 4 brand baru (Roblox, Garena/Free Fire, Xfinity, Pinterest) sudah ada di branch `feat/brands-games` (worktree `Final-CH7-brands`, belum di-commit). Domain mirip (`roblox.com.am`, `r0blox[.]com`, `p1nterest[.]com`, `pinterest-login[.]top`) sekarang kena sinyal L2.
