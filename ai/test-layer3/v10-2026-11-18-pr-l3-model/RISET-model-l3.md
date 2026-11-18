# Riset kombinasi model layer 3: plan + prompt

Target: model impersonation di Worker (`shoo-impersonation-lab` → `Final-CH7-l3model/ai/src/layer3/model/impersonation.js`).
Prioritas: **turunkan scam yang lolos (miss)**, FP boleh naik sedikit asal terukur.
Alat: **agent-reach** (dipasang dulu).

Riset dibuat **dua tahap** supaya tidak terjebak di sekitar model sekarang (anchoring):

- **Tahap 1 (buta):** agent hanya tahu masalah, batas input, batas Worker, metrik. Arsitektur dan angka kita tidak disebut.
- **Tahap 2 (banding):** baru setelah tahap 1 selesai, arsitektur dan baseline dibuka untuk memetakan kandidat.

Kirim Prompt 1 dulu. Kirim Prompt 2 di chat yang sama setelah `RISET-PAPER.md` tahap 1 jadi.

## 1. Diagnosis prompt asli

| Masalah | Akibat | Perbaikan |
|---|---|---|
| "Model sekarang TF-IDF + LR" tidak lengkap | Riset bisa salah sasaran. Model sebenarnya TF-IDF+LR (teks, URL) + 2×300 HistGB combiner + fakta + v3g + umur domain | Tulis arsitektur lengkap, tapi di tahap 2 |
| Menyebut model sejak awal | Agent cenderung mencari variasi TF-IDF/LR/boosting saja, pendekatan lain terlewat | Tahap 1 buta, minimal 4 keluarga metode |
| "Beberapa lost, banyak FP" tanpa angka | Tidak ada baseline untuk membandingkan paper | Masukkan angka baseline di tahap 2 |
| Tidak ada batas deploy | Paper berat (BERT, CNN visual, screenshot) ikut masuk | Wajib JS di Worker, ≤3 MB (Free) / ≤10 MB (Paid) gzip, tanpa GPU |
| Tidak ada batas input | Paper yang pakai screenshot/HTML mentah tidak bisa dipakai | Input hanya url, title, teks, form |
| Output riset tidak didefinisikan | Hasil berupa ringkasan acak | Minta tabel paper + shortlist + desain eksperimen |
| Tidak ada larangan | Agent bisa langsung ubah kode/commit | Riset saja, tanpa edit worktree, tanpa commit |

## 2. Plan

| # | Langkah | Hasil | Waktu |
|---|---|---|---|
| 1 | Pasang agent-reach, jalankan `agent-reach doctor --json` | Daftar channel aktif (Exa, GitHub, Reddit, web) | 10–15 menit |
| 2 | **Tahap 1:** riset paper + GitHub + diskusi tanpa konteks model kita | ≥15 paper dari ≥4 keluarga metode | 60–75 menit |
| 3 | **Tahap 2:** buka arsitektur + baseline, petakan kandidat | Tiap kandidat: sudah kita punya / menutup miss / tidak relevan | 20 menit |
| 4 | Saring kandidat dengan batas Worker + input kita | Shortlist 3–5 kombinasi | 15 menit |
| 5 | Tulis desain eksperimen per kandidat di lab | Langkah uji di `shoo-impersonation-lab`, metrik sama dengan baseline | 15 menit |
| 6 | (Sesi terpisah) jalankan eksperimen kandidat teratas | Angka catch vs FP vs ukuran bundle | 1–3 jam per kandidat |

Langkah 1–5 = satu sesi riset (~2 jam). Langkah 6 = sesi implementasi sendiri.

## 3. Prompt teroptimasi (versi lengkap)

### Prompt 1: tahap buta

```
Riset metode deteksi halaman web scam/phishing yang menyamar sebagai brand (bank, e-commerce, pemerintah,
operator seluler) dan meminta data sensitif (password, OTP, data diri).
Jawab dalam bahasa Indonesia. Riset saja: jangan ubah kode apa pun, jangan commit, jangan push.

## Batas wajib untuk kandidat
- Input hanya: URL, judul halaman, teks halaman yang terlihat, daftar field form (nama, tipe, label).
  Tidak ada HTML mentah, screenshot, DOM tree, atau WHOIS selain umur domain.
- Jalan di Cloudflare Worker: JavaScript murni, tanpa GPU, inferensi < 50 ms CPU,
  ukuran model + kode ≤ 3 MB gzip (target) atau ≤ 10 MB (maksimum).
- Halaman berbahasa Indonesia dan Inggris.
- Label training lama dan sebagian salah (situs scam yang sudah berganti isi masih berlabel scam).
- Prioritas: recall scam tinggi pada false positive rate rendah (0,5% dan 2%).

## Langkah
1. Pasang agent-reach (https://github.com/Panniantong/Agent-Reach) sesuai README-nya,
   jalankan `agent-reach doctor --json`, catat channel yang aktif. Tanya dulu sebelum login ke platform apa pun.
2. Cari paper 2019–2026 (pakai Exa via agent-reach; fokus arXiv, USENIX Security, IEEE S&P, NDSS,
   ACM CCS, WWW, ACL, IEEE Access, Elsevier). Wajib mencakup minimal 4 dari keluarga metode ini,
   minimal 2 paper per keluarga:
   a. Model berbasis URL/leksikal
   b. Model berbasis isi teks halaman, termasuk model neural kecil atau terkuantisasi
   c. Deteksi berbasis referensi brand (brand yang diklaim vs domain asli, niat meminta kredensial)
   d. Teknik belajar untuk label kotor dan data timpang (positive-unlabeled, cost-sensitive, label cleaning)
   e. Distillation dari model besar atau LLM ke model kecil
   f. Ensemble / stacking / cascade beberapa model
   g. Deteksi scam di konteks Indonesia atau Asia Tenggara
   Kata kunci awal (kembangkan sendiri):
   - "lightweight phishing webpage detection"
   - "reference-based phishing detection brand intention text"
   - "positive-unlabeled learning phishing noisy labels"
   - "knowledge distillation phishing detector edge"
   - "cascade phishing detection low false positive"
   - "LLM phishing website detection brand knowledge"
   - "Indonesian phishing scam website detection", "deteksi situs phishing bahasa Indonesia"
3. Cari kode di GitHub (`gh search repos`) dan diskusi praktisi (Reddit r/MachineLearning, r/netsec, Kaggle).
   Catat ukuran model nyata dan apakah bisa jalan di JavaScript.
4. Untuk tiap paper isi tabel:
   judul | tahun | venue | link | keluarga (a–g) | kombinasi model | fitur (URL/teks/form/HTML/visual) |
   dataset | recall/TPR pada FPR tertentu atau AUC | ukuran/latency | lolos batas? (ya/tidak + alasan)

## Output
File ~/Documents/Swift/Final-CH/shoo-impersonation-lab/RISET-PAPER.md bagian "Tahap 1":
tabel ≥ 15 paper, ringkasan per keluarga (kelebihan, kelemahan, cocok dengan batas atau tidak), daftar sumber.
Ringkas dengan kata sendiri dan beri link; jangan menyalin isi paper panjang.

## Selesai jika
- ≥ 15 paper, ≥ 4 keluarga, ≥ 2 paper per keluarga yang dipilih
- Tiap baris punya angka (recall@FPR atau AUC) dan link yang bisa dibuka
- Paper yang tidak lolos batas tetap dicatat dengan alasannya
- Tidak ada file kode yang berubah

## Jangan
- Jangan menyusun shortlist atau rekomendasi dulu; itu tahap 2
- Jangan menebak model yang sedang kami pakai
```

### Prompt 2: tahap banding (kirim setelah tahap 1 selesai)

```
Tahap 1 selesai. Sekarang bandingkan hasilnya dengan model kami. Riset saja: jangan ubah kode, jangan commit.

## Model kami sekarang
Lokasi: ~/Documents/Swift/Final-CH/shoo-impersonation-lab (training, Python/sklearn)
dan ~/Documents/Swift/Final-CH/Final-CH7-l3model/ai/src/layer3/model/impersonation.js (port JS untuk Worker).
- Judge 1: teks halaman → TF-IDF (hash FNV) + Logistic Regression
- Judge 2: bentuk URL → TF-IDF char n-gram + Logistic Regression
- Fakta: brand di domain yang bukan milik brand, form password, form dikirim ke situs lain, TLD murah,
  shared host, signal rules lama (asks_password, asks_otp), flag bahasa Indonesia
- 2 combiner HistGradientBoosting (300 pohon; satu pakai URL, satu tidak), skor = rata-rata
- Tier safe/gate/warn/block, cut-off dari FP legit 15%/2%/0,5% per grup bahasa
- Aturan tambahan: saringan klaim v3g, umur domain < 30 hari minimal warn,
  brand-in-host, kata umpan Indonesia di host (hadiah, undian)
- Bundle Worker sekarang 3,7 MB gzip (di atas batas Free 3 MB)

## Baseline (tanpa LLM)
- Scam segar tertangkap 66,5% → 76,3% (+brand-in-host) → 87,7% (+kata umpan di host, FP Kaggle naik)
- FP legit Kaggle 0,25%
- AUC test split lama 0,988; sampel v5 (6.623 halaman) hanya 0,690 → generalisasi lemah
- Masalah utama: scam yang lolos (miss), lalu FP

## Langkah
1. Untuk tiap kandidat di tabel tahap 1, beri label:
   "sudah kami punya" | "menutup kelemahan kami" | "tidak relevan", dengan alasan satu kalimat.
2. Baca kode training dan port JS di atas seperlunya untuk memastikan label "sudah kami punya" benar.
3. Pilih shortlist 3–5 kombinasi yang paling mungkin menaikkan recall scam segar.
   Per kandidat: kelemahan kami yang ditutup, risiko FP, perkiraan ukuran bundle, cara menggabungkan
   dengan komponen yang sudah ada (ganti, tambah judge, atau tambah fakta).
4. Tulis desain eksperimen per kandidat untuk shoo-impersonation-lab:
   data dan split sama dengan baseline (split per situs), metrik utama =
   recall scam segar pada FP Kaggle tetap 0,5% dan 2%, plus PR-AUC, ukuran bundle gzip, waktu inferensi JS.

## Output
Tambahkan bagian "Tahap 2" di RISET-PAPER.md: tabel pemetaan, shortlist, desain eksperimen.

## Selesai jika
- Semua kandidat tahap 1 punya label pemetaan
- Tiap kandidat shortlist punya alasan lolos batas Worker dan perkiraan ukuran
- Tidak ada file kode yang berubah (cek `git status` di worktree dan lab)

## Jangan
- Jangan training atau ubah model di sesi ini
- Jangan klaim angka paper bisa dibandingkan langsung dengan angka kami (dataset beda)
```

## 4. Prompt versi singkat

Prompt 1:

```
Pakai skill agent-reach (pasang dulu, cek `agent-reach doctor --json`).
Riset paper 2019–2026 + repo GitHub: deteksi halaman phishing yang menyamar sebagai brand.
Input hanya URL/judul/teks/field form, harus jalan di Cloudflare Worker JS ≤ 3–10 MB tanpa GPU,
label training kotor, prioritas recall pada FPR 0,5–2%. Wajib ≥ 4 keluarga metode (URL, teks,
referensi brand, label kotor/PU, distillation, ensemble/cascade, konteks Indonesia), ≥ 2 paper per keluarga.
Output bagian "Tahap 1" di shoo-impersonation-lab/RISET-PAPER.md: tabel ≥ 15 paper
(keluarga, kombinasi, fitur, data, recall@FPR/AUC, ukuran, lolos batas?). Belum ada shortlist.
Riset saja, tanpa ubah kode, tanpa commit.
```

Prompt 2:

```
Model kami: TF-IDF+LR untuk teks dan URL, fakta brand/form/TLD, 2 combiner HistGB, aturan v3g,
umur domain < 30 hari, brand-in-host, kata umpan di host. Baseline: catch scam segar 66,5–87,7%,
FP Kaggle 0,25%, AUC v5 0,690, bundle 3,7 MB. Labeli tiap kandidat tahap 1
(sudah punya / menutup kelemahan / tidak relevan), pilih shortlist 3–5, tulis desain eksperimen
(recall @ FP 0,5% dan 2%, PR-AUC, ukuran bundle). Tambahkan "Tahap 2" di RISET-PAPER.md. Tanpa ubah kode.
```

## 5. Alasan perubahan

| Tambahan | Alasan |
|---|---|
| Dua prompt terpisah (buta, lalu banding) | Agent membaca seluruh prompt sekaligus; memisah prompt satu-satunya cara supaya tahap 1 benar-benar tidak tahu model kita |
| Minimal 4 keluarga metode, 2 paper per keluarga | Memaksa pencarian melebar, tidak hanya variasi model linear |
| Kata kunci TF-IDF/LR dihapus dari tahap 1 | Kata kunci ikut mengarahkan hasil pencarian |
| Batas Worker + batas input tetap di tahap 1 | Itu syarat, bukan anchoring; membuang paper yang mustahil dipakai |
| Arsitektur lengkap + baseline di tahap 2 | Kandidat bisa dipetakan ke kelemahan nyata kita |
| Label "sudah kami punya" | Mencegah rekomendasi yang sebenarnya sudah ada |
| Metrik recall @ FPR tetap | Sesuai cara tier kita dipotong; akurasi menyesatkan pada data timpang |
| Format output + kriteria selesai | Hasil bisa dicek, bukan ringkasan bebas |
| Larangan ubah kode/commit | Sesuai aturan handover |
