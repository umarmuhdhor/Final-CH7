# Keputusan — Team AI (Imelda)

Append-only. Format: `D-imelda-NN` · tanggal · keputusan · alasan · status.

| ID | Tanggal | Keputusan | Alasan | Status |
|---|---|---|---|---|
| D-imelda-00 | 22 Okt 2026 | Plan di `plan/imelda/`, pola mengikuti `plan/alief/` tapi diringkas; ditambah ARCHITECTURE, SECURITY, VERIFY_PROMPT, fixbug, ref/R1-R2 setelah dibandingkan dengan plan Alief | Lingkup Team AI lebih kecil: 2 folder, 1 service | Berlaku |
| D-imelda-01 | 22 Okt 2026 | Usulan: `/analyze` dan `/public-blocklist` sebagai Cloudflare Worker + Hono di `ai/` | Sama dengan stack Alief, memudahkan M7; stateless cocok untuk Worker | **Menunggu konfirmasi Imelda** |
| D-imelda-02 | 22 Okt 2026 | Urutan fase: M5-detector → M3 → M2 data → M5-server → M4 → M6 → M7 | Saran handoff: kecil dan tanpa dependensi dulu; model LLM dipilih setelah eval ada | Berlaku |
| D-imelda-03 | 22 Okt 2026 | Push dan PR selalu menunggu izin Imelda; agent berhenti sebelum `git push`/`gh pr create` | Aturan kerja Imelda (tindakan terlihat publik) | Berlaku |
| D-imelda-04 | 22 Okt 2026 | Prinsip bobot: hindari false positive dulu; kasus ambigu bobot kecil dan tidak mencapai 30 sendirian | Target mandat #1 + pengguna inti orang tua | Berlaku |
| D-imelda-05 | 22 Okt 2026 | Usulan gerbang LLM: panggil layer 4 hanya bila ada ≥ 1 form dengan field dan skor layer 1–3 sementara ≥ 15; situs resmi tidak memanggil LLM | Hemat biaya dan latensi; halaman tanpa form tidak punya "data yang diminta" untuk dinilai | **Menunggu konfirmasi Imelda** (ref/R1 §4) |
| D-imelda-06 | 22 Okt 2026 | Layer 4 hanya menambah bobot, tidak pernah mengurangi skor layer 1–3 | Cegah prompt injection menurunkan skor (SECURITY A1) | Berlaku |
| D-imelda-07 | 22 Okt 2026 | Set eval dibagi ±70% tuning / ±30% uji lewat hash `id`; sampel sintetis tidak dihitung untuk klaim target | Cegah menghafal sampel (SECURITY A12, ref/R2 §3) | Berlaku |
| D-imelda-08 | 22 Okt 2026 | Anggaran latensi `/analyze`: jaringan 1,0 s · layer 3 ≤ 0,1 s CPU · RDAP timeout 1,5 s · LLM timeout 4,0 s · margin 1,4 s; layer 3 tidak menunggu LLM | Total klien 8 s (ref/R1 §3) | Usulan awal, disetel di fase 02/03/06/08 |
| D-imelda-19 | 22 Okt 2026 | Sumber scam (TODO A4) = campuran (c): tidak ada feed publik yang lisensinya jelas untuk disalin ke repo. OpenPhish: syarat melarang distribusi/karya turunan tanpa izin tertulis; PhishTank: halaman developer tanpa lisensi, merujuk EULA Cisco; URLhaus: URL malware (bukan phishing), perlu Auth-Key, lisensi tidak tertulis di halaman. Maka: sampel scam = sampel nyata yang sudah ada (lphone-login + fixture kontrak) + sintetis bertanda `synthetic: true` dari pola terdokumentasi | Aturan keras: tanpa lisensi jelas = tidak dipakai | Berlaku (dipilih Imelda 22 Okt 2026) |
| D-imelda-20 | 22 Okt 2026 | Komposisi 50+50 sesuai usulan. Scam: bank 10, e-wallet 8, kurir 8, hadiah 8, pemerintah 8, iCloud/Apple 4, lain 4. Legit: login bank 8, e-commerce checkout 12, pemerintah 8, populer ID 10, trap 12 | Mencakup kategori R2 §2 dan risiko false positive fase 03 | Berlaku |
| D-imelda-21 | 22 Okt 2026 | Holdout ±30%, tag `holdout`, dipilih deterministik dari `sha256(seed:id)` dengan seed acak yang dicatat di `ai/eval/data/HOLDOUT.json`; bukan dipilih tangan, dan tidak bergeser saat sampel ditambah. Menggantikan "hash id mod 10" di D-imelda-07 (tujuan sama) | Cegah menghafal sampel (SECURITY A12) | Berlaku |
| D-imelda-22 | 22 Okt 2026 | DoD sampel nyata: legit nyata >= 60%; scam nyata sebisanya (sumbernya terbatas oleh D-imelda-19). Klaim target mandat dihitung dari sampel nyata saja dan dilaporkan terpisah dari sintetis (R2 §4) | Sintetis ditulis oleh kita sendiri, tidak boleh dipakai membuktikan recall | Berlaku |
