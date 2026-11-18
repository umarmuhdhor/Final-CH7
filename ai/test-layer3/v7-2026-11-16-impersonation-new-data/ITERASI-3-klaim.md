# Iterasi 3: warn/block hanya kalau halaman membuat klaim

Ditulis 2026-11-16. Kode: `shoo-impersonation-lab/eval_v3.py`. Tabel lengkap semua varian: `shoo-impersonation-lab/out/impersonation-v3/eval.md`.
Model v2 **tidak dilatih ulang** dan file model tidak diubah. Iterasi 3 adalah aturan setelah model. Semua angka tanpa LLM: hanya warn/block yang dihitung ditandai.

## Masalah

Dari cek mata 50 halaman (`.hasil/eyecheck50/laporan.html`), 16 dari 25 halaman berlabel legit yang ditandai v2 ternyata salah tanda. Polanya: login sah (Puskesmas, SAKTi, Super Indo, bank), situs resmi di hosting gratis (vercel/netlify/blogspot), dan situs lama bisnis kecil.
Hampir semuanya punya **skor alamat tinggi** (0,6 sampai 0,9, karena hosting bersama atau subdomain acak), **skor kata rendah**, dan **tidak membuat klaim apa pun**.

## Aturan

Hasil warn/block dari v2 tetap dipakai hanya kalau halaman membuat klaim. Kalau tidak, tingkatnya turun ke `gate` (tanpa LLM: tidak ada banner).

Klaim (v3e, versi yang direkomendasikan):
1. Brand dari daftar brand Shoo: di judul, teks, host, atau logo di luar situs resmi.
2. Minta OTP, PIN, KTP, CVV, kartu, atau selfie+KTP (sinyal rules).
3. Kata pancingan: hadiah, undian, bansos, CS, verifikasi, pencairan, giveaway, prize, claim, ...
4. Ada link t.me/wa.me.
5. Kata phishing kredensial tanpa nama brand: webmail, mailbox, Microsoft/Office/Outlook, dokumen dibagikan, seed phrase, "sign in to your account", ...
6. Ada kolom password **dan** skor kata minimal 0,75.
7. Kata password yang disamarkan (`Passvvord`, `P@ssw0rd`, `Pαssword`, `WebmaiI`), atau form email/user + password di site builder (Weebly, ubpages, GoDaddy Sites, Wix, ...).

v3f = v3e ditambah 5 brand yang belum ada di daftar brand Shoo (Roblox, Garena/Free Fire, Xfinity, Pinterest), dibaca dari judul atau host.

## Hasil (terbukti)

| Set | v2 scam | v2 legit | **v3e scam** | **v3e legit** | v3f scam | v3f legit |
|---|---|---|---|---|---|---|
| Link segar, unseen (856 scam / 12 legit) | 67,9% | 5 | 63,4% | 1 | **64,5%** | 1 |
| Link aman manual (15 legit) | - | 5 | - | **1** | - | 1 |
| phishing-url v6 unseen (323 / 5.170) | 41,8% | 2,8% | 23,2% | **1,2%** | 23,2% | 1,2% |
| Test Alief Indonesia (33 / 323) | 84,8% | 0,3% | 84,8% | **0,0%** | 84,8% | 0,0% |
| Kaggle v7 unseen legit (17.410) | - | 1,9% | - | **0,5%** | - | 0,5% |
| Kaggle v7 legit Indonesia (87) | - | 10,3% | - | 8,0% | - | 8,0% |
| Legit Indonesia kalibrasi (805) | - | 2,2% | - | 1,4% | - | 1,4% |

Cek mata 50 halaman, yang masih ditandai:
- Legit salah tanda: **16 → 4**.
- Scam benar ditandai: **16 → 13**. Yang hilang 3 tiruan Pinterest.
- Legit yang sebenarnya judi: 6 → 4. Yang hilang togel dan kasino kripto, bukan peniruan brand.

Ringkasnya: salah tanda legit turun **sekitar 60 sampai 75%** di semua set. Recall scam di feed Indonesia segar turun **3,4 poin** (v3f).

## Kenapa v6 turun banyak (41,8% → 23,2%)

Dari 74 scam v6 yang hilang di v3d, cek judul dan teks satu per satu: **sekitar 50 bukan phishing**. Isinya judi Tiongkok/Vietnam, situs perusahaan biasa, crypto explorer, latihan Frontend Mentor "Easybank", serta halaman mati atau cek bot. Label phishing-url sudah basi untuk halaman-halaman ini.
Sekitar 22 sisanya phishing sungguhan: webmail, tiruan Microsoft, form login di Weebly. v3e mengembalikan 14 di antaranya (aturan 5 dan 7). **Dugaan:** recall phishing sungguhan di v6 turun sekitar 8 halaman, bukan 60.

## Batasan

- **Tiruan Pinterest (sekitar 15 halaman di feed segar) tetap lolos.** Snapshot statis hanya berisi CSS, tanpa kata "Pinterest". Di Safari, ekstensi membaca DOM hasil render, jadi kemungkinan tertangkap oleh brand list. Belum diuji.
- **Daftar brand Shoo kurang:** Roblox, Garena/Free Fire, Xfinity, Pinterest. Menambah 4 brand ini memberi +9 scam segar (v3f) tanpa salah tanda baru.
- Masih salah tanda di cek mata: aplikasi BPS (teks menyebut brand), situs festival komedi, Bank Gaborone resmi, toko grosir dengan link wa.me.
- Regex kata pancingan dan kredensial disusun setelah melihat data uji v6 dan v7. Ada risiko terlalu pas dengan data ini (overfit). Perlu set baru untuk konfirmasi.
- Link chat hanya diketahui untuk halaman yang diambil `links_fetch.mjs`. Di v6 dan Kaggle 17.410, aturan 4 tidak aktif.

## Kesimpulan

- **v3e/v3f layak jadi aturan tanpa LLM di app.** Banner jauh lebih jarang salah: link aman 5 → 1 dari 15, legit Kaggle 1,9% → 0,5%. Recall scam Indonesia hampir sama: −3,4 poin di feed segar, sama di test Alief.
- Untuk app, yang perlu dipindahkan: daftar brand (+4 brand), sinyal rules yang sudah ada, regex kata pancingan, kredensial, dan password samaran, daftar site builder, dan link t.me/wa.me (perlu `links` di `PageSnapshot`).
- Berikutnya: (a) tambah 4 brand ke daftar brand Shoo; (b) uji v3f live di simulator, termasuk tiruan Pinterest yang dirender; (c) cek mata ulang pada set baru untuk mengukur risiko overfit regex.
