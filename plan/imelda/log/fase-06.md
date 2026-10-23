# Fase 06 — Layer 4: reality check LLM (M4)

**Status:** `[m]` kode + test selesai dengan penyedia PALSU; sisa LANGKAH MANUAL (pilih model, isi key, eval dengan LLM).
**Branch:** `feat/AI-M4-reality-check` dari `feat/AI-M5-server` (stacked). 22 Okt 2026, dikerjakan semalaman tanpa key.

## Rencana (dijalankan)
1. Test dulu dengan `fetch` palsu (`ai/test/layer4.test.mjs`, 18 test): sinyal, skema rusak, error penyedia, timeout, gerbang, injection, kebocoran data, evidence, batas harian, konfigurasi env.
2. Implementasi `ai/src/layer4/{config,schema,provider,reality}.js`, `ai/prompts/reality-check.js` (v1), sambungan di `analyze.js` / `app.js`.
3. `.env.example`, bagian README, DECISIONS D-imelda-27..29, TODO C5.
4. Tidak ada key, tidak ada panggilan LLM sungguhan, tidak ada klaim eval layer 4.

## File
Baru: `ai/src/layer4/*`, `ai/prompts/reality-check.js`, `ai/test/layer4.test.mjs`, `ai/.env.example`.
Diubah: `ai/src/{analyze,app,index}.js`, `ai/src/dev-server.mjs` (muat `ai/.env` bila ada), `ai/README.md`, `plan/imelda/{TODO,fixbug}.md`, `log/DECISIONS.md`.

## Verifikasi
- `node --test --test-concurrency=1 detector/test ai/test ai/eval/test ios/ShooExtension/Tests`: 374 lolos, 0 gagal (351 + 23, setelah perbaikan review).
- Eval TANPA layer 4 (service lokal `npm run dev`, hanya sampel non-holdout terlihat satu per satu): sama dengan fase 04, scam >=30 40/50, >=50 33/50, >=80 20/50; legit >=30 4/51; scam nyata 1 (target mandat TIDAK dinilai). Karena `LLM_*` kosong, layer 4 mati dan angkanya identik, sebagai bukti layer 4 tidak mengubah apa pun tanpa key.
- Eval DENGAN layer 4: **belum dijalankan** (butuh model + key). Tabel eval layer 4 sengaja kosong.

## Review keamanan (`ecc:security-reviewer`)
Diperbaiki: HIGH-1 `localSignals` dari klien memicu biaya -> gerbang memakai skor aturan server saja + batas 20 panggilan LLM per IP per jam (rate limit `/analyze` penuh = fase 08); MED-2 evidence hanya dari title, min 8 karakter; MED-3 hanya registrable domain dikirim, IP/intranet tidak dikirim, email dan deret angka di title/label disamarkan; LOW-5 `checker.meta` memuat versi prompt + model; LOW-6 respons penyedia > 64 KB diabaikan; LOW-7 `LLM_BASE_URL` harus host publik (bukan IP/localhost/intranet); LOW-8 dev server hanya meneruskan `LLM_*` dan gagal keras bila `.env` rusak.
Tidak berubah: MED-4 (tes injection sudah ada: `prompt injection: page words are data...`; injeksi hanya bisa menekan sinyal layer 4, tidak menurunkan skor layer 1-3); LOW-9 aman-gagal. Batas harian tetap per isolate (lihat catatan handoff).

## DoD
- [x] Output LLM tervalidasi skema; keluaran rusak diabaikan, bukan error (test, 12 bentuk rusak).
- [x] Timeout dan LLM down -> respons layer 3 (test, termasuk penyedia yang mengabaikan abort).
- [ ] Eval: layer 4 mengurangi salah blokir tanpa menurunkan deteksi scam: **belum bisa diukur** (LANGKAH MANUAL).
- [x] Key hanya di env; `.env.example` di-commit; prompt injection teruji (halaman dan label field berisi "abaikan instruksi sebelumnya").

## LANGKAH MANUAL (Imelda)
- [ ] Pilih model (TODO A2) setelah membaca eval; isi `ai/.env` (`LLM_API_KEY`, `LLM_MODEL`, `LLM_BASE_URL`). Atur batas pengeluaran di dashboard penyedia.
- [ ] Putuskan gerbang D-imelda-05 (TODO A5). Catatan: implementasi memakai skor aturan server saja (tanpa `localSignals`), sedikit lebih ketat dari usulan awal.
- [ ] `cd ai && npm run dev`, lalu `node ai/eval/run.mjs --analyze-url http://localhost:8787` dengan `.env` terisi dan tanpa `.env`; tempel dua tabel ke PR/PROGRESS. Catat `PROMPT_VERSION` dan nama model.
- [ ] Kabari Alief/Umar soal label privasi (TODO C5): host, title, label field halaman yang lolos gerbang dikirim ke penyedia LLM.
- [ ] Putuskan D-imelda-29 (evidence yang tak cocok: sinyal tetap, tanpa evidence).

## Catatan handoff
- F-04-5 (scam tanpa kolom form) bukan pekerjaan layer 4 karena gerbang menutupnya; dicatat di `fixbug.md`.
- Batas harian panggilan hanya per isolate (memori). Pemutus sungguhan = batas pengeluaran di dashboard penyedia + (fase 08) rate limit Cloudflare.
- `localSignals` dari klien ikut menghitung gerbang (tiap bobot dibatasi 100); klien jahat bisa memicu panggilan LLM pada form apa pun, dibatasi rate limit/batas harian.
