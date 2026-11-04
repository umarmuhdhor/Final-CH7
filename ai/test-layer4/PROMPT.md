Kerjakan tes Layer 4 (LLM) di repo Shoo, folder `ai/test-layer4/`. Aku Imelda, pemilik `ai/`.

## Baca dulu (wajib, urut)
1. `CLAUDE.md` (root) dan `ai/CLAUDE.md`
2. `ai/test-layer4/PLAN.md`: ini spesifikasinya. Keputusan K1–K8 sudah final, jangan ditanya ulang
3. `ai/prompts/reality-check.js` (prompt `reality-check.v4`, `LINK_TEXT`, `RULE_TEXT`)
4. `ai/src/layer4/reality.js` (`buildInput`, aturan sinyal), `ai/src/layer4/provider.js`, `ai/src/layer4/schema.js` (`parseVerdict`), `ai/src/analyze.js`
5. Contoh pola: `ai/test-layer2/analyze.mjs` (cara menjalankan `detector.js` lewat `vm`), `ai/test-layer3/l3-penuh.mjs` (gaya skrip + laporan), `ai/testing/tools/run-model-compare.mjs` (cara mengirim `chat_template_kwargs`)

## Yang harus dikerjakan
1. Tulis `ai/test-layer4/run.mjs` sesuai PLAN.md:
   - Sampel: `ai/test-layer3/snapshots/01–25.json` (scam), `L01–L10.json` (legit), dan `trap-github-pages-dokumentasi` dari `ai/eval/data/legit/traps.json` (legit, ditulis terpisah di laporan)
   - L2: `analyzeLocal` dari `ios/ShooExtension/Resources/detector.js` lewat `vm`. Catat semua sinyal + bobot
   - L3: `analyze(snapshot, { localSignals, rdap: null, llm: null })`. Catat id + bobot + skor, dan apakah gate produksi (`passesGate`) lolos
   - Payload: `buildInput(snapshot, ruleIds, localSignals)` + `SYSTEM_PROMPT`, persis seperti `reality.js`
   - **Gate dilewati** (K1): panggil provider langsung, bukan `check()`
   - Model dari `ai/.env` (`deepseek-v4-flash`). **Thinking off**: tambahkan `chat_template_kwargs: { thinking: false }` ke body request, hanya di skrip ini
   - Batas waktu 8 dtk per panggilan. Tandai yang > 6 dtk
   - Tiap sampel 3 kali, satu per satu (tidak paralel). Total 108 panggilan
   - Bungkus `fetch` untuk mengukur waktu (ms) dan membaca `usage` (`prompt_tokens`, `completion_tokens`, `total_tokens`) dari respons
   - Simpan semuanya ke `ai/test-layer4/.hasil/l4.json`
   - Opsi: `--dry` (tanpa LLM, cetak payload), `--only 01` (satu sampel), `--report` (tulis HASIL.md dari JSON)
2. `node run.mjs --dry --only 01`, `--only 11`, `--only L01`. Cek payload tidak berisi teks halaman, path/query URL, atau nilai ketikan
3. `node run.mjs --only 01` (1 sampel × 3 ke LLM). Cek `usage` ada dan jawaban lolos `parseVerdict`. Kalau `usage` tidak ada, pakai perkiraan karakter ÷ 4 dan beri tanda
4. Jalankan penuh, lalu `node run.mjs --report` → `ai/test-layer4/HASIL.md` dengan isi persis seperti bagian "Isi HASIL.md" di PLAN.md (tabel per link, detail per link, ringkasan, batas lulus lulus/gagal)
5. Tambahkan bagian "Analisis" di HASIL.md: apa yang tertangkap, apa yang lolos dan kenapa, false positive di legit (terutama trap GitHub Pages: apakah `link_checks` memicu false), waktu dan token, serta usulan perubahan prompt kalau ada. Bedakan yang terbukti dan dugaan

## Aturan
- **Jangan ubah** `ai/src/`, `ai/prompts/`, `contracts/`, `detector/`, `ios/`. Cuma tulis di `ai/test-layer4/`
- **Jangan cetak isi `ai/.env`** ke chat, log, `.hasil/`, atau HASIL.md. Cek cuma `grep -c '^LLM_' ai/.env` = 3. Nama model dan host boleh dicatat
- **Jangan buka situs scam** dan jangan ambil HTML baru. Pakai snapshot yang ada. Tidak ada RDAP live
- Domain di HASIL.md disamarkan: `hxxps://bni-diirect[.]com`
- Jangan ulang tes penuh "supaya yakin" (biaya ~120k token). Kalau ada 10 `http_error` berturut-turut, berhenti, simpan hasil sebagian, lalu lapor
- Jangan commit. Setelah selesai, laporkan ringkasan (angka utama + batas lulus) dan tanya apakah mau di-commit
- Kalau ada yang tidak jelas di PLAN.md, tanya dulu sebelum menebak
