# Keputusan — Team AI (Imelda)

Append-only. Format: `D-imelda-NN` · tanggal · keputusan · alasan · status.

| ID | Tanggal | Keputusan | Alasan | Status |
|---|---|---|---|---|
| D-imelda-00 | 22 Okt 2026 | Plan di `plan/imelda/`, pola mengikuti `plan/alief/` tapi diringkas; ditambah ARCHITECTURE, SECURITY, VERIFY_PROMPT, fixbug, ref/R1-R2 setelah dibandingkan dengan plan Alief | Lingkup Team AI lebih kecil: 2 folder, 1 service | Berlaku |
| D-imelda-01 | 22 Okt 2026 | `/analyze` dan `/public-blocklist` sebagai Cloudflare Worker + Hono di `ai/`, **JavaScript ESM + JSDoc, tanpa build step**, test `node --test` memanggil `app.request()` (opsi a; b TypeScript+vitest dan c Node tanpa Worker ditolak) | Sama dengan stack Alief, memudahkan M7; stateless cocok untuk Worker; dependensi minim, konsisten dengan baseline test repo | **Berlaku** (dikonfirmasi Imelda 22 Okt 2026) |
| D-imelda-02 | 22 Okt 2026 | Urutan fase: M5-detector → M3 → M2 data → M5-server → M4 → M6 → M7 | Saran handoff: kecil dan tanpa dependensi dulu; model LLM dipilih setelah eval ada | Berlaku |
| D-imelda-03 | 22 Okt 2026 | Push dan PR selalu menunggu izin Imelda; agent berhenti sebelum `git push`/`gh pr create` | Aturan kerja Imelda (tindakan terlihat publik) | Berlaku |
| D-imelda-04 | 22 Okt 2026 | Prinsip bobot: hindari false positive dulu; kasus ambigu bobot kecil dan tidak mencapai 30 sendirian | Target mandat #1 + pengguna inti orang tua | Berlaku |
| D-imelda-05 | 22 Okt 2026 | Usulan gerbang LLM: panggil layer 4 hanya bila ada ≥ 1 form dengan field dan skor layer 1–3 sementara ≥ 15; situs resmi tidak memanggil LLM | Hemat biaya dan latensi; halaman tanpa form tidak punya "data yang diminta" untuk dinilai | **Menunggu konfirmasi Imelda** (ref/R1 §4) |
| D-imelda-06 | 22 Okt 2026 | Layer 4 hanya menambah bobot, tidak pernah mengurangi skor layer 1–3 | Cegah prompt injection menurunkan skor (SECURITY A1) | Berlaku |
| D-imelda-07 | 22 Okt 2026 | Set eval dibagi ±70% tuning / ±30% uji lewat hash `id`; sampel sintetis tidak dihitung untuk klaim target | Cegah menghafal sampel (SECURITY A12, ref/R2 §3) | Berlaku |
| D-imelda-08 | 22 Okt 2026 | Anggaran latensi `/analyze`: jaringan 1,0 s · layer 3 ≤ 0,1 s CPU · RDAP timeout 1,5 s · LLM timeout 4,0 s · margin 1,4 s; layer 3 tidak menunggu LLM | Total klien 8 s (ref/R1 §3) | Usulan awal, disetel di fase 02/03/06/08 |
| D-imelda-09 | 22 Okt 2026 | Format error `/analyze`: `{error:{code,message}}` (api.md). Kode: `bad_json` 400, `invalid_body` 400, `too_large` 413, `method_not_allowed` 405 + `Allow: POST`, `not_found` 404, `internal` 500. `method_not_allowed` tidak ada di daftar umum api.md | Kontrak tidak menentukan 405; pola kode mengikuti daftar umum | Berlaku, usulkan ke Umar bila ingin masuk kontrak |
| D-imelda-10 | 22 Okt 2026 | Batas input `/analyze`: body 200 KB, text 20.000, 20 form, 60 field/form, 300 field total, 120 karakter/string field, 50 `imageAlts` | SECURITY A3; angka usulan | Usulan awal, disetel fase 08 |
| D-imelda-11 | 22 Okt 2026 | Domain resmi (`brands.json`) dan subdomainnya tanpa sinyal form; kecuali host konten-pengguna (`docs.google.com`, `sites.google.com`, `forms.office.com`, dll.) | Cegah false positive di situs resmi; cegah form scam di layanan hosting resmi (temuan review H1) | Berlaku |
| D-imelda-12 | 22 Okt 2026 | Bobot `asks_*` mengikuti ref/R1 (pin 35, otp 30, password 15, card 30, cvv 30, ktp 30, selfie_ktp 35). Catatan: otp/card/ktp 30 mencapai ambang popup sendirian, berbeda dari saran D-imelda-04 | Perintah fase 02: ikuti R1 | Usulan awal, kalibrasi fase 07 |
