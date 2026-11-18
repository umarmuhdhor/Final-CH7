Kerjakan tes layer 3 versi 7: model impersonation kita dijalankan pada data baru, dipasang ke Shoo untuk pengecekan, lalu dicek live di simulator iPhone. Aku Imelda, pemilik `ai/`. Data baru: `<PATH_DATA_BARU>` (daftar URL + label scam/legit). Kalau path ini masih placeholder, tanya dulu sebelum mulai.

## Konteks (sudah diputuskan, jangan ditanya ulang)

- **Model terbaik:** "Ours, impersonation only" di `~/Documents/Swift/Final-CH/shoo-impersonation-lab/`. Isinya judge kata + judge alamat (TF-IDF + LR), fakta impersonation (brand di domain bukan miliknya, password field, form dikirim ke situs lain, TLD murah, shared host, sinyal rules `asks_*`), dan 2 combiner GBT. Tanpa `bge-m3` dan tanpa gambling.
- **Tier:** `safe` / `gate` (diteruskan ke layer 4 LLM) / `warn` / `block`. Cut-off diset supaya halaman legit dev yang lolos ke gate/warn/block hanya 15% / 2% / 0,5% per kelompok bahasa. Host brand resmi selalu `safe`.
- **Popular-sites top 1.000 AKTIF** (K1). Domain Tranco top 1.000, dikurangi `SHARED_HOSTS` dan `USER_CONTENT`, dianggap resmi. Model: `out/impersonation-popular1000/model.joblib` (AUC test 0,988). Jangan naikkan ke 10k: scam di r2.dev dan shortener ikut lolos.
- **Pass rule TIDAK dipakai** (K2). Aturan ini memotong sekitar dua pertiga scam yang tertangkap. Boleh dilaporkan sebagai baris tambahan saja.
- **Integrasi = sidecar Python lokal** (K3). Server Python memuat joblib dan dipanggil `ai/src` lewat flag env (misalnya `SHOO_L3_MODEL=impersonation`). Flag mati berarti perilaku lama tidak berubah sama sekali. Belum di-port ke JS atau Worker.
- **Branch** (K4): buat branch baru dari kondisi Final-CH7 sekarang (`docs/imelda-layer-test-results`, ada sekitar 84 file belum di-commit, ikut dibawa). Nama usulan: `feat/l3-impersonation-sidecar`.
- **`playwright-core` boleh di-install** (K5), sekitar 13,7 MB lewat npm.
- **Hasil sebelumnya**, sebagai pembanding:

  | Test | Rules | Alief (bge-m3) | Ours impersonation |
  |---|---|---|---|
  | Test split Alief, AUC | 0,54 | 0,983 | 0,988 |
  | v5 (6.623 halaman), AUC | 0,50 | 0,654 | 0,690 |
  | v6 situs belum dilihat, AUC | 0,53 | 0,858 | 0,841 |
  | v6 situs belum dilihat, scam tertangkap / block / legit sampai gate | 0,9% / 0% / 0,8% | 68% / 9% / 12% | 72% / 24,5% / 17% |
  | v6 halaman dengan password field, AUC | 0,49 | 0,868 | 0,889 |

  Ablation (Alief tanpa bge-m3) dapat AUC 0,981, sama dengan Alief (0,981). Kesimpulannya, bge-m3 tidak menambah apa-apa.

## Baca dulu (wajib, urut)

1. `CLAUDE.md` (root) dan `ai/CLAUDE.md`
2. `shoo-impersonation-lab/README.md`, `train.py`, `apply.py`, `popular.py`
3. `ai/test-layer3/v5-2026-11-13-compare-alief-l3/` dan `v6-2026-11-13-compare-phishing-url-test/`: `PLAN.md`, `HASIL.md`, `sample.py`, `build-rows.mjs`, `report.py`. **Format laporan v7 mengikuti v6.**
4. `ai/src/analyze.js` (`analyzeSnapshot`), `ai/src/layer3/`, `ai/src/app.js`, `ai/src/dev-server.mjs`
5. `ai/test-layer-live/README.md`, `v1/PROMPT.md`, `v1/PLAN.md`, `scripts/` (alat tes live simulator yang sudah ada)
6. `ios/ShooExtension/Resources/pipeline.js` dan `SafariWebExtensionHandler.swift`. Cek apakah layer 3 juga jalan di perangkat. Kalau iya, laporkan dulu sebelum mengubah apa pun.
7. `shoo-impersonation-lab/site/` (`server.py`, `reader.mjs`, `build_row.mjs`): compare site yang setengah jadi

## Yang harus dikerjakan

### Tahap 1: model pada data baru (folder ini, `ai/test-layer3/v7-2026-11-16-impersonation-new-data/`)

1. Tulis `PLAN.md` dulu (salin pola v6, dengan bagian "Beda dari v6" di paling atas), lalu minta aku setujui.
2. Buka tiap URL jadi snapshot (pola `build-rows.mjs` / `reader.mjs`, pakai Chrome sistem atau playwright-core). Catat yang mati atau dialihkan ke host lain, jangan dibuang diam-diam.
3. Buang situs yang ada di train/dev Alief, lalu tandai `unseen` / `seen-by-alief` seperti di v6.
4. Nilai dengan: rules sekarang, Alief (bge-m3), Ours impersonation, dan Ours impersonation + popular 1.000.
5. `report.py` menulis `HASIL.md` dengan bagian yang sama seperti v6: jumlah halaman, situs belum dilihat, halaman dengan password field, semua halaman, contoh (yang semua model lewatkan, yang hanya ours tangkap, yang hanya Alief tangkap, legit yang ours warn/block), dan AUC. Tambahkan perbandingan dengan v5/v6.

### Tahap 2: pasang ke Shoo (branch K4)

1. Sidecar: `ai/l3-sidecar/server.py` (atau lokasi lain yang lebih cocok, sebutkan alasannya). Endpoint `POST /score` menerima PageSnapshot dan mengembalikan `{score, tier, judges, facts}`. Hanya bind ke `127.0.0.1`. Hanya memuat joblib yang kita tulis sendiri.
2. `ai/src`: saat flag menyala, `analyzeSnapshot` (atau pemanggilnya) memanggil sidecar lalu memetakan tier ke alur yang ada. `gate` diteruskan ke layer 4, `warn`/`block` langsung tampil. Kalau sidecar mati atau timeout, kembali ke rules lama dan catat di log.
3. Tes: perilaku lama identik saat flag mati (jalankan tes yang sudah ada di `ai/test`), plus tes baru untuk jalur sidecar dan fallback.

### Tahap 3: cek live (link dan simulator iPhone)

1. Jalankan dev-server dengan flag menyala, ditambah sidecar.
2. Compare site lokal (`shoo-impersonation-lab/site`) harus jalan. Uji beberapa link dari data baru, termasuk login Amazon UK sebagai kontrol legit.
3. Simulator: pakai pola `ai/test-layer-live/` (buat versi baru di sana, `v3`, dengan PLAN.md dan PROMPT.md sendiri). Pakai simulator `Shoo QA L1-4`, buka panel simulator untukku, build dan launch app dari branch K4. Kunjungi sampel link (tanya jumlahnya, usulan 20 scam + 20 legit). Screenshot tiap link dan lihat sendiri, jangan menebak dari skor.
4. Laporkan per link: tier layer 3, keputusan akhir di Safari, dan apakah sama dengan hasil tahap 1.

## Aturan

- **Jangan ubah** `ai/prompts/`, `contracts/`, `detector/`, `plan/alief/`. `ios/` hanya boleh diubah kalau sudah aku setujui. Perubahan `ai/src/` hanya di belakang flag.
- **Hanya memuat halaman.** Jangan mengetik, mengetuk isi halaman, atau mengunduh. Jangan isi data Imelda ke mana pun.
- **Jangan cetak isi `ai/.env`.** Jangan arahkan simulator ke `shoo-api` atau `shoo-ai` yang sudah deploy. L1 tetap mati.
- **Repo publik:** host di laporan disamarkan (`bni-diirect[.]com`). Jangan simpan teks halaman atau `evidence`. `.hasil/` dan `.raw/` di-gitignore.
- Bandingkan model satu dengan yang lain, bukan dengan 100%. Label bisa basi. Bedakan yang terbukti dan yang masih dugaan.
- Jangan commit atau push. Setelah tiap tahap, laporkan ringkasan dan tanya apakah lanjut atau commit.
- Kalau tahap 1 menunjukkan Ours lebih buruk dari Alief di situs belum dilihat lebih dari 0,03 AUC, berhenti dan lapor sebelum tahap 2.
- Ada yang tidak jelas? Tanya dulu, jangan menebak.
