Kerjakan tes live L2-L4 versi 1 di simulator iPhone, repo Shoo, folder `ai/test-layer-live/`. Aku Imelda, pemilik `ai/`.

## Baca dulu (wajib, urut)
1. `CLAUDE.md` (root) dan `ai/CLAUDE.md`
2. `ai/test-layer-live/README.md` dan `ai/test-layer-live/v1/PLAN.md`: ini spesifikasinya. Keputusan K1-K9 sudah final, jangan ditanya ulang
3. `ai/src/dev-server.mjs`, `ai/src/app.js`, `ai/src/analyze.js`, `ai/src/layer4/reality.js`
4. `ios/ShooExtension/Resources/pipeline.js` dan `ios/ShooExtension/SafariWebExtensionHandler.swift`
5. Contoh pola: `plan/alief/qa/live-visit.sh`, `plan/alief/qa/corpus-dns.mjs`, `ai/test-layer-update-full/run.mjs`, dan tabel "Scam links" di `plan/alief/qa/figma-parity-2026-10-31.md`

## Yang harus dikerjakan
1. Pastikan branch `feat/AI-M4-thinking-off-asks-otp-boxes` dan commit `2c51aee` ada di riwayat
2. Tulis `scripts/links.mjs`, `scripts/server.mjs`, `scripts/visit.sh`, `scripts/report.mjs` sesuai PLAN.md
3. Kerjakan bagian "Penyiapan" sampai uji asap lolos. Kalau tahap 2 atau 5 gagal, berhenti dan lapor
4. Kerjakan bagian "Urutan tes": dua link dulu, baru semua link, satu per satu
5. Lihat tiap screenshot sendiri, jangan menebak dari skor, lalu tulis `v1/observed.json`
6. Jalankan `report.mjs`, tulis bagian Analisis di `v1/HASIL.md`, dan perbarui tabel versi di `README.md`. Bedakan yang terbukti dan dugaan
7. Bandingkan dengan hasil 31 Okt, dan tandai baris yang dulu diblokir karena L1

## Aturan
- **Jangan ubah** `ai/src/`, `ai/prompts/`, `contracts/`, `detector/`, `ios/`, `plan/alief/`. Cuma tulis di `ai/test-layer-live/`
- **Hanya memuat halaman.** Jangan mengetik, mengetuk isi halaman, atau mengunduh. Jangan isi data Imelda ke mana pun
- **Jangan cetak isi `ai/.env`** ke chat, log, `v1/`, atau `HASIL.md`. Nama model dan host boleh dicatat
- **Jangan simpan teks halaman atau `evidence`.** Domain di `HASIL.md` disamarkan: `bni-diirect[.]com`
- **L1 tetap mati.** Jangan pakai blocklist asli, dan jangan arahkan simulator ke `shoo-api` atau `shoo-ai` yang sudah deploy
- Simulator yang sudah ada jangan disentuh, pakai `Shoo QA L1-4`
- Tiap link satu kali kunjungan. Jangan ulang tes penuh "supaya yakin"
- Jangan commit. Setelah selesai, laporkan ringkasan (scam diblokir, legit kena tanda, lulus atau gagal, waktu LLM, link yang berubah dari 31 Okt) dan tanya apakah mau di-commit
- Kalau ada yang tidak jelas di PLAN.md, tanya dulu sebelum menebak
