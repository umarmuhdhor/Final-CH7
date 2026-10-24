# Prompt siap tempel — sisa kerja Umar + Imelda - Umar

> Dibuat 23 Okt 2026, status tabel diperbarui 24 Okt 2026. Sejak hari ini **semua tugas Imelda (Team AI) diambil alih Umar**, ditandai **Imelda - Umar**.
> Sumber: [`sisa-kerja.md`](sisa-kerja.md), `docs/mandates/umar.md`, `docs/mandates/imelda.md`, `plan/imelda/TODO.md`, `plan/imelda/log/fase-08.md`, issue #37, #38, #40, #55, #73–#76.
> Tugas yang hanya milik Alief (#3, #13, #15, #17) tidak diberi prompt.

## Cara pakai

1. Buka Claude Code di root `Final-CH7`, branch `main` yang sudah di-pull.
2. Tempel **satu** prompt (isi blok `text`), jalankan, tunggu sampai selesai.
3. Agent berhenti dan bertanya sebelum: push, buka PR, merge, post komentar/issue, atau langkah yang butuh kamu (login, secret, iPhone).
4. Satu prompt = satu branch = satu PR (CLAUDE.md aturan 4).
5. Kerjakan **Prompt 00 dulu**: tanpa itu agent akan menolak mengedit `detector/` dan `ai/` (CLAUDE.md aturan 1).

## Tabel sisa kerja

| # | Siapa | Tugas | Menunggu | Prompt | Status 24 Okt |
|---|---|---|---|---|---|
| 00 | Umar | Catat pengambilalihan Team AI di `CLAUDE.md` + mandat | — | [00](#prompt-00--catat-pengambilalihan-team-ai) | Selesai |
| 1 | Umar | G1 deploy `/analyze` + `/public-blocklist` | Kamu login Cloudflare | [1](#prompt-1--deploy-worker-shoo-ai-g1-d-1d-5) | Selesai 23 Okt. Deploy ulang perlu untuk #101, #105, #106 |
| 2 | Umar | Catat hasil deploy, centang M7, issue `aiBaseURL` ke Alief | #1 | [2](#prompt-2--catat-deploy--issue-aibaseurl-d-6d-8) | Selesai (#92, #82 ditutup) |
| 3 | Alief | Isi `aiBaseURL` di `AppConfig.swift` | #2 | — | Selesai (#92) |
| 4 | Umar | Verifikasi 3 domain `brands.json` (#76) | — | [4](#prompt-4--verifikasi-domain-brandsjson-76) | Selesai (#76 ditutup) |
| 5 | Imelda - Umar | Putuskan + tutup #73, #74, #75, #76 | #4 (untuk #76) | [5](#prompt-5--putuskan-dan-tutup-issue-g0-7376) | Selesai (#73–#76 ditutup) |
| 6 | Imelda - Umar | Pilih model LLM (A2, A5, A6), pasang secret | #1, #5 | [6](#prompt-6--pilih-model-llm-dan-nyalakan-layer-4) | Selesai dengan risiko. Centang A2/A5/A6 di PR #107 (terbuka) |
| 7 | Imelda - Umar | Eval layer 4 dengan LLM nyata, centang M4 | #6 | [7](#prompt-7--eval-layer-4-dengan-llm-nyata) | Selesai (#96). Timeout 4 s → 6 s di #105 |
| 8 | Imelda - Umar | Issue privasi LLM ke Alief (C5) | #6 | [8](#prompt-8--issue-privasi-llm-ke-alief-c5) | Selesai (#97, #98) |
| 9 | Imelda - Umar | Data scam nyata berlisensi (E-1) | #5 (#73) | [9](#prompt-9--kumpulkan-data-scam-nyata-e-1) | Belum |
| 10 | Imelda - Umar | Kalibrasi ulang M6 (E-2) | #9 | [10](#prompt-10--kalibrasi-ulang-m6-e-2) | Belum |
| 11 | Imelda - Umar | Sumber blocklist publik + daftar pra-bangun (E-3, E-4) | — | [11](#prompt-11--sumber-blocklist-publik-e-3-e-4) | Kode selesai (#101, #104, #106). Sisa manual: secret, variable, run workflow, deploy |
| 12 | Imelda - Umar | Sinkronkan `PROGRESS.md` + `TODO.md` Imelda (E-5) | #5 | [12](#prompt-12--sinkronkan-progress-dan-todo-team-ai-e-5) | Selesai (#84, #85) |
| 13 | Alief | PR docs 3 temuan review #69 + kirim 3 secret CI | — | — | Selesai (#69, #90) |
| 14 | Umar | Isi secret CI `production`, jalankan ulang `deploy`, tutup #38 | #13 | [14](#prompt-14--secret-ci-dan-deploy-backend-38) | Selesai (#38 ditutup). Sisa: rotasi password DB + token Cloudflare |
| 15 | Alief | Spike 01S di iPhone (#40) | Akses tim Apple | — | Belum |
| 16 | Umar | `extensionActiveWindow` + keputusan C17 (#40) | #15 | [16](#prompt-16--extensionactivewindow-dan-keputusan-c17-40) | Belum |
| 17 | Alief | `ExtensionStatus` baca `allSites` | — | — | Belum |
| 18 | Umar | Tes U7 / EX-01 di iPhone, centang U7 | #17 | [18](#prompt-18--tes-u7--ex-01-di-iphone) | Belum |
| 19 | Umar | TestFlight bagian Umar (#55): undang Alief, kunci APNs, App Store Connect | — | [19](#prompt-19--testflight-bagian-umar-55) | Checklist selesai. Sisa manual: undang Alief, kunci APNs, App Store Connect |
| 20 | Imelda - Umar | Uji detector + `/analyze` di Safari iPhone (D3) | #3, build | [20](#prompt-20--uji-detector-dan-analyze-di-safari-iphone-d3) | Belum |
| 21 | Umar | Uji 5 definisi sukses MVP + #78/#79 di iPhone | #3, #18 | [21](#prompt-21--uji-definisi-sukses-mvp-di-iphone) | Belum |
| 22 | Umar | `accept` di `PageSnapshot` (C8 / U-7) | — | [22](#prompt-22--field-accept-di-pagesnapshot-c8) | Selesai (#87–#89) |
| 23 | Umar | Pertanyaan PM + video ON-04 (#37) | PM | [23](#prompt-23--pertanyaan-pm-dan-video-on-04-37) | Draf siap, ditunda Umar |
| 24 | Umar | Runbook review antrean blocklist (bareng Alief) | Fase 10 backend | [24](#prompt-24--runbook-review-antrean-blocklist-c6) | Selesai (#100). #99 menunggu Alief |
| 25 | Umar | Hapus branch yang sudah merge | — | [25](#prompt-25--hapus-branch-yang-sudah-merge) | Sebagian: 28 branch dihapus, 22 branch Alief menunggu izin |

Sisa yang disarankan (24 Okt): langkah manual Prompt 11 (secret, variable, run workflow, `npm run deploy`) → langkah manual 19 → 9 → 10, lalu 16, 18, 20, 21 saat syaratnya terpenuhi; 23 kapan Umar siap. Daftar langkah manual ada di [`sisa-kerja.md`](sisa-kerja.md) bagian 0.

---

## Prompt 00 · Catat pengambilalihan Team AI

```text
Saya Umar (lead, @umarmuhdhor). Mulai 23 Okt 2026 saya mengambil alih semua tugas Imelda (Team AI): detector/, ai/, plan/imelda/, dan ios/ShooExtension/Resources/detector.js (hanya lewat detector/scripts/sync-to-extension.sh).

Tugas: catat pengambilalihan ini supaya agent berikutnya boleh mengedit folder Team AI.
1. Baca CLAUDE.md, docs/mandates/imelda.md, docs/mandates/umar.md, plan/umar/sisa-kerja.md.
2. CLAUDE.md: di tabel "Who owns what", owner detector/ dan ai/ jadi "Lead (diambil alih dari Team AI, 23 Okt 2026)". Di bagian Mandates, tulis bahwa mandat Imelda sekarang dikerjakan Umar. Jangan ubah aturan lain.
3. docs/mandates/imelda.md: tambahkan catatan singkat di atas "## Peran": dikerjakan oleh Umar sejak 23 Okt 2026, tugas tetap sama.
4. plan/umar/sisa-kerja.md: label pemilik "Imelda" untuk tugas Team AI jadi "Imelda - Umar".
5. Branch docs/AI-handover-umar. Commit dengan pesan jelas, tanpa baris atribusi.
Berhenti sebelum push dan buka PR: tunjukkan diff dan tanya saya dulu.
```

## Prompt 1 · Deploy Worker `shoo-ai` (G1, D-1…D-5)

```text
Saya Umar (lead, mengambil alih Team AI). Bantu saya deploy ai/ (POST /analyze + GET /public-blocklist) ke Cloudflare Workers.

Baca dulu: plan/imelda/log/fase-08.md (bagian Langkah manual), ai/README.md, ai/wrangler.toml, ai/scripts/smoke.mjs, plan/umar/sisa-kerja.md §3.

Langkah:
1. Cek prasyarat tanpa mengubah apa pun: versi node, `cd ai && npm ci`, `npx wrangler --version`, `npx wrangler whoami`.
2. Kalau belum login: berhenti dan minta saya sendiri menjalankan `cd ai && npx wrangler login` (buka browser). Kamu tidak login dan tidak meminta token di chat.
3. Setelah saya login: cek `namespace_id` [[ratelimits]] di ai/wrangler.toml (1001, 1002) tidak bentrok dengan Worker lain di akun saya (`npx wrangler deployments list` / dashboard; kalau tidak bisa dicek lewat CLI, minta saya cek di dashboard).
4. Tanya saya dulu sebelum menjalankan `npm run deploy` di ai/. Itu aksi cloud.
5. Setelah deploy: jalankan `node ai/scripts/smoke.mjs <URL> 30` dan dua cek CORS dari fase-08 (origin safari-web-extension:// → 204 + origin di-echo; origin https://x → tanpa access-control-allow-origin).
6. Laporkan: URL, keluaran smoke test lengkap, p95 /analyze (target < 8 s), hasil CORS. Jangan ubah file repo di prompt ini (pencatatan ada di prompt 2).

Catatan: paket Free punya batas CPU 10 ms per request; sebutkan kalau smoke test menunjukkan error CPU, dan sarankan Workers Paid. Layer 4 tetap mati (belum ada secret LLM), daftar publik tetap kosong.
```

## Prompt 2 · Catat deploy + issue `aiBaseURL` (D-6…D-8)

```text
Saya Umar (lead, mengambil alih Team AI). Deploy ai/ sudah selesai.
URL: <TEMPEL URL workers.dev>
Keluaran smoke test: <TEMPEL KELUARAN>

Tugas:
1. Branch docs/AI-M7-deploy-record.
2. plan/imelda/log/fase-08.md: isi bagian hasil deploy (tanggal, URL, keluaran smoke test, p95, CORS), centang DoD yang sudah terbukti. Jangan tulis secret apa pun.
3. plan/imelda/PROGRESS.md: baris fase 08 → [x] dengan ringkasan satu kalimat; tabel metrik `/analyze` p95 diisi angka dari URL publik.
4. docs/mandates/imelda.md: centang M7 "Deploy ke URL publik HTTPS" dan "/public-blocklist ikut di-deploy", catatan singkat berisi URL.
5. plan/imelda/TODO.md: C4 dan B2 dicentang dengan status singkat.
6. plan/umar/sisa-kerja.md: D-1 … D-6 ditandai selesai.
7. Draf issue (template .github/ISSUE_TEMPLATE/question.yml, label question, assign aliefauzan, bahasa Inggris) judul "APP: set aiBaseURL to the deployed AI Worker": ios/ShooApp/App/AppConfig.swift masih `static let aiBaseURL: URL? = nil`; minta Alief mengisi URL di atas untuk release (dan debug kalau mau), kirim lewat SessionStore/getSession ke extension (contracts/app-group-keys.md). Sertakan URL, cara cek (smoke test), dan apa yang terjadi selama belum diisi (extension hanya layer 1–2).
Tunjukkan diff dan draf issue dulu. Jangan push, buka PR, atau buat issue sebelum saya bilang.
```

## Prompt 4 · Verifikasi domain `brands.json` (#76)

```text
Saya Umar (lead). Kerjakan verifikasi di issue #76: apakah tiga domain ini domain resmi brand-nya di detector/data/brands.json?
- BSI (Bank Syariah Indonesia): bankbsi.co.id
- J&T Express: jet.co.id
- BPJS Ketenagakerjaan: bpjsketenagakerjaan.go.id

Cara:
1. Baca issue #76 dan entri ketiga brand di detector/data/brands.json.
2. Untuk tiap domain, kumpulkan bukti dari sumber yang bisa dipercaya: halaman resmi brand, tautan dari aplikasi resmi di App Store, akun media sosial terverifikasi, atau situs pemerintah/OJK. Pakai built-in browser atau web search, hanya membaca. Jangan isi form apa pun.
3. Cek juga apakah brand itu punya domain resmi lain yang belum ada di brands.json (mis. domain lama atau domain layanan), karena domain resmi yang hilang bisa membuat situs asli kena `lookalike_domain`.
4. Laporkan dalam tabel: domain, resmi ya/tidak, bukti (URL sumber), domain resmi lain yang disarankan.
5. Draf komentar untuk #76 (bahasa Inggris) yang mengisi tabel di issue itu. Tunjukkan dulu, jangan post.
6. Kalau ada domain salah atau kurang: jangan ubah file dulu. Usulkan perubahan brands.json; nanti dikerjakan di branch fix/AI-M1-brands dengan `detector/scripts/sync-to-extension.sh` dan test detector.
```

## Prompt 5 · Putuskan dan tutup issue G0 (#73–#76)

```text
Saya Umar (lead, mengambil alih Team AI). Issue #73, #74, #75, #76 dulu ditujukan ke Imelda; sekarang saya yang menjawab dan memutuskan.

Baca: issue #73–#76 (gh issue view), plan/umar/sisa-kerja.md §2, plan/imelda/TODO.md, ai/eval/lib.mjs (MIN_PER_CLASS, TARGETS), ios/ShooExtension/Resources/marks.js, snapshot.js, report.js.

Untuk tiap issue, siapkan komentar "Decision (lead, Team AI taken over by Umar)" dalam bahasa Inggris yang menjawab setiap nomor pertanyaannya:
- #73: usulkan jumlah scam nyata minimum (pilih tetap 50 = MIN_PER_CLASS, atau angka lebih kecil dengan alasan), sumber berlisensi yang realistis, dan bahwa target tidak diturunkan. Beri saya 2 opsi + rekomendasi sebelum menulis drafnya.
- #74: konfirmasi aturan yang sudah merge di #78 (TEXT_SIGNALS), A7 boleh tanpa evidence, tidak ada sinyal teks baru di MVP kecuali saya bilang lain.
- #75: konfirmasi #79 (same-origin, tanpa field kontrak baru), cross-origin = Fase 2. Hitung berapa sampel scam di ai/eval/data yang punya meta.iframes dan apakah src-nya relatif (same-origin) atau domain lain.
- #76: isi dari hasil prompt 4 (minta saya tempel hasilnya kalau belum ada).
Lalu siapkan perubahan di branch docs/AI-G0-decisions: plan/imelda/TODO.md (A7, C1, C3, C6, C7, C8, C9, C10 dicentang dengan jawaban singkat + nomor issue), plan/umar/sisa-kerja.md (U-1 … U-9 status).
Tunjukkan semua draf komentar dan diff. Jangan post, tutup issue, push, atau buka PR sebelum saya bilang.
```

## Prompt 6 · Pilih model LLM dan nyalakan layer 4

```text
Saya Umar (lead, mengambil alih Team AI). Tugas: pilih model LLM untuk layer 4 (TODO A2, A5, A6) dan siapkan cara menyalakannya.

Baca: plan/imelda/TODO.md (A2, A5, A6, A7, B1, C5), plan/imelda/SECURITY.md (Q3, Q4), plan/imelda/ref/R1-sinyal-bobot-anggaran.md §3, plan/imelda/log/fase-06.md, ai/src/layer4/{config,provider,reality,schema}.js, ai/prompts/reality-check.js, ai/.env.example, docs/mandates/imelda.md M4.

Langkah:
1. Riset terkini (sebut tanggal dan URL sumber) untuk kandidat di A2 dan alternatif cepat lain: harga input/output per 1 jt token, latensi, dukungan output JSON terstruktur, dan kebijakan data API (zero data retention / tidak dipakai training). Kalau salah satu kandidat model Claude, muat skill claude-api dulu untuk model ID dan harga.
2. Cek kompatibilitas tiap kandidat dengan ai/src/layer4/provider.js (POST {LLM_BASE_URL}/chat/completions gaya OpenAI). Kalau tidak kompatibel, sebutkan perubahan kode yang perlu dan ukurannya.
3. Beri saya tabel perbandingan + satu rekomendasi. Tunggu pilihan saya.
4. Setelah saya memilih: branch feat/AI-M4-llm-model. Catat keputusan di plan/imelda/log/DECISIONS.md (D-imelda-NN berikutnya: model, penyedia, kebijakan data, alasan), centang A2/A5/A6 di TODO. Kalau provider.js perlu diubah: TDD, `node --test ai/test`.
5. Tulis langkah manual untuk saya (jangan dijalankan, jangan minta key di chat): pasang spend limit di dashboard penyedia; `cd ai && npx wrangler secret put LLM_API_KEY`, `LLM_MODEL`, `LLM_BASE_URL`; `npm run deploy`; smoke test ulang.
Syarat: A7 sudah diputuskan di #74 (prompt 5). Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 7 · Eval layer 4 dengan LLM nyata

```text
Saya Umar (lead, mengambil alih Team AI). Layer 4 sudah menyala di Worker: <TEMPEL URL>. Tugas: buktikan kriteria M4 "layer 4 mengurangi salah blokir di halaman resmi tanpa menurunkan deteksi scam".

Baca: ai/eval/README.md, ai/eval/run.mjs (flag --analyze-url, --json, --strict, --show-holdout), ai/eval/lib.mjs (layer4Stats, layer4Delta), plan/imelda/ref/R2-protokol-eval.md, plan/imelda/log/fase-06.md, fase-07.md.

Langkah:
1. Jalankan `node ai/eval/run.mjs --analyze-url <URL> --json` dan simpan hasilnya di scratchpad. Jangan pakai --show-holdout kecuali R2 bilang ini saatnya.
2. Bandingkan dengan hasil tanpa layer 4 (angka di fase-07 / #60, atau jalankan dev server lokal tanpa ai/.env). Pakai layer4Delta kalau ada.
3. Tabel sebelum/sesudah: legit >= 30, scam >= 50, scam >= 80, berapa panggilan LLM, berapa yang gagal/timeout, p95 /analyze.
4. Kalau kriteria M4 terpenuhi: branch docs/AI-M4-eval, tulis hasil di plan/imelda/log/fase-06.md, centang M4 di docs/mandates/imelda.md dan baris M4 di plan/imelda/PROGRESS.md. Kalau tidak: tulis angkanya apa adanya dan usulkan perbaikan prompt/gerbang, jangan menurunkan target.
Catatan biaya: eval mengirim 101 halaman ke penyedia LLM; sebutkan perkiraan jumlah panggilan sebelum menjalankan dan tunggu OK saya.
Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 8 · Issue privasi LLM ke Alief (C5)

```text
Saya Umar (lead, mengambil alih Team AI). Layer 4 sekarang mengirim data halaman ke penyedia LLM <NAMA PENYEDIA + MODEL>. Tugas: TODO C5 di plan/imelda/TODO.md dan SECURITY Q4.

1. Baca ai/src/layer4/reality.js dan ai/prompts/reality-check.js: daftar persis field apa yang dikirim ke penyedia (host? title? label field? teks?) dan kapan (gerbang A5). Tulis dari kode, bukan dari ingatan.
2. Baca kebijakan data penyedia yang dicatat di plan/imelda/log/DECISIONS.md.
3. Draf issue (template question, label question, assign aliefauzan, bahasa Inggris), judul "PR-privacy: AI layer 4 sends page data to <provider>": apa yang dikirim, retensi/training penyedia, apa yang perlu diubah di kebijakan privasi app dan label privasi App Store (rilis yang sama dengan layer 4), dan pertanyaan bernomor untuk Alief.
4. Setelah issue dibuat: centang C5 di plan/imelda/TODO.md dengan nomor issue (branch docs/AI-C5-privacy).
Tunjukkan draf issue dulu. Jangan buat issue, push, atau PR sebelum saya bilang.
```

## Prompt 9 · Kumpulkan data scam nyata (E-1)

```text
Saya Umar (lead, mengambil alih Team AI). Tugas E-1: tambah halaman scam NYATA berlisensi ke eval set sampai jumlah yang diputuskan di #73.

Baca: issue #73 (keputusan jumlah), ai/eval/README.md (format sampel, tabel sumber + lisensi), ai/eval/tools/capture.mjs, ai/eval/data/PLAN.md, plan/imelda/TODO.md A4, plan/imelda/log/DECISIONS.md (D-imelda-19, D-imelda-22), plan/imelda/SECURITY.md.

Aturan keras:
- Jangan membuka URL scam di browser. Ambil hanya lewat `node ai/eval/tools/capture.mjs` (GET statis, tanpa JS/cookie, masking otomatis).
- Hanya sumber yang lisensinya mengizinkan dipakai di eval (atau izin tertulis). OpenPhish/PhishTank/URLhaus sudah ditolak karena lisensi (D-imelda-19), kecuali kamu menemukan syarat baru yang mengizinkan: tunjukkan teks syaratnya.
- Data pribadi wajib tersamar; cek ulang setiap sampel.

Langkah:
1. Riset sumber scam nyata berlisensi (laporan publik, dataset riset dengan lisensi terbuka, CERT/BSSN, pengumuman resmi bank/OJK yang memuat URL scam). Beri tabel: sumber, lisensi/syarat, jumlah yang realistis, risiko. Tunggu pilihan saya.
2. Setelah saya pilih: branch feat/AI-M2-real-scam. Capture sampel, beri tag dan label, catat sumber + lisensi di ai/eval/README.md.
3. Jalankan `node --test ai/eval/test` dan `node ai/eval/run.mjs`. Laporkan jumlah scam nyata sekarang dan skor per sampel baru.
4. Centang baris M2 di docs/mandates/imelda.md kalau jumlah tercapai; perbarui plan/imelda/PROGRESS.md.
Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 10 · Kalibrasi ulang M6 (E-2)

```text
Saya Umar (lead, mengambil alih Team AI). Eval set sekarang punya cukup scam nyata (prompt 9). Tugas E-2: kalibrasi ulang bobot sampai target docs/mandates/imelda.md tercapai, atau laporkan angka jujur.

Target: situs resmi skor < 30 (semua brands.json + populer), scam >= 50 di >= 90%, scam >= 80 di >= 70%.

Baca: plan/imelda/fase-07-kalibrasi.md, plan/imelda/log/fase-07.md, plan/imelda/ref/R1-sinyal-bobot-anggaran.md, plan/imelda/ref/R2-protokol-eval.md (pemisahan tuning/holdout), ai/test/calibration.test.mjs, bobot di ai/src/layer3/signals.js, ai/src/layer3/forms.js, ai/src/layer4/reality.js, detector/src/detector.js.

Langkah:
1. Branch feat/AI-M6-recalibration. Catat angka "sebelum" dengan `node ai/eval/run.mjs --analyze-url <URL lokal dev server atau Worker>`.
2. Ubah bobot hanya berdasarkan sampel tuning; holdout dilihat sekali di akhir (R2).
3. Setiap perubahan bobot: test dulu (ai/test/calibration.test.mjs / detector/test), lalu kode.
4. Kalau bobot detector berubah: `detector/scripts/sync-to-extension.sh`, commit src dan ios/ShooExtension/Resources/detector.js bersamaan.
5. Ambang 30/50/80 di extension TIDAK diubah.
6. Jalankan semua test: node --test --test-concurrency=1 'ios/ShooExtension/Tests/*.test.mjs' 'detector/test/**/*.test.mjs' 'ai/test/**/*.test.mjs' 'ai/eval/test/**/*.test.mjs'.
7. Tabel sebelum/sesudah untuk PR; tulis di plan/imelda/log/fase-07.md; centang M6 kalau target tercapai, kalau tidak tulis angkanya dan alasannya.
Tunjukkan diff + tabel dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 11 · Sumber blocklist publik (E-3, E-4)

```text
Saya Umar (lead, mengambil alih Team AI). Tugas M5-A yang tersisa: pilih sumber daftar phishing publik berlisensi dan isi GET /public-blocklist (sekarang `emptySource`, daftar kosong).

Baca: docs/design/blocklist.md, docs/mandates/imelda.md M5-A, ai/README.md bagian "Source and licence (TODO A3)", ai/src/blocklist/{source,build,allowlist,domains,route}.js, ai/test/blocklist.test.mjs, plan/imelda/log/fase-05.md, plan/imelda/log/fase-08.md (catatan CPU: membangun 200.000 entri ±1 s CPU, tidak muat di batas Free 10 ms).

Langkah:
1. Riset sumber (sebut URL syarat/lisensi dan tanggal): boleh dipakai di app komersial/gratis? boleh redistribusi ke HP? batas unduh? format? Beri tabel + rekomendasi; tunggu pilihan saya.
2. Rancang daftar pra-bangun: daftar dibangun di luar request (mis. skrip build terjadwal atau GitHub Action yang menulis ke KV/static asset), Worker hanya melayani hasilnya. Beri 1–2 opsi + biaya/kompleksitas; tunggu pilihan saya.
3. Setelah saya pilih: branch feat/AI-M5-public-source. TDD: source baru sesuai typedef di source.js, test di ai/test/blocklist.test.mjs (allowlist tetap membuang domain resmi + shared hosts, bentuk respons persis `{ domains, removed?, nextSince }`, maks 200.000).
4. Catat sumber + lisensi di ai/README.md, keputusan di plan/imelda/log/DECISIONS.md, centang A3 di TODO dan M5-A "Pilih sumber" di docs/mandates/imelda.md.
5. Semua test lolos. Langkah deploy ulang ditulis untuk saya, tidak dijalankan.
Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 12 · Sinkronkan PROGRESS dan TODO Team AI (E-5)

```text
Saya Umar (lead, mengambil alih Team AI). plan/imelda/PROGRESS.md dan plan/imelda/TODO.md tertinggal dari main.

1. Baca keduanya, docs/mandates/imelda.md, dan `git log --oneline --merges -- detector ai plan/imelda` untuk nomor PR yang sudah merge (#25, #26, #44, #50, #57, #59, #60, #61, #67, dst.).
2. PROGRESS.md: setiap baris fase sesuai kenyataan (status, PR, tanggal selesai), tabel "Status requirement mandat" dan Gate G0–G5 diperbarui, metrik eval diisi angka terbaru. Tambahkan catatan di atas: dikerjakan Umar sejak 23 Okt 2026.
3. TODO.md: centang yang sudah terjawab dengan nomor issue/PR, tulis "diambil alih Umar" untuk baris yang dulu "tunggu Imelda".
4. Hanya ubah plan/imelda/. Jangan ubah kode.
5. Branch docs/AI-progress-sync. Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 14 · Secret CI dan deploy backend (#38)

```text
Saya Umar (lead). Alief sudah mengirim 3 nilai secret lewat password manager untuk issue #38: SUPABASE_DB_URL, CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID.

Baca: issue #38 dan #68 (keputusan), .github/workflows/backend.yml (job deploy, environment production).

Langkah:
1. Cek environment `production` ada di repo (`gh api repos/umarmuhdhor/Final-CH7/environments`). Kalau belum, beri tahu saya cara membuatnya.
2. Beri saya perintah untuk saya jalankan sendiri, satu per satu, yang meminta nilai secara interaktif (tanpa nilai di argumen atau riwayat shell):
   gh secret set SUPABASE_DB_URL --env production
   gh secret set CLOUDFLARE_API_TOKEN --env production
   gh secret set CLOUDFLARE_ACCOUNT_ID --env production
   Kamu tidak menjalankan, membaca, atau menampilkan nilainya.
3. Setelah saya bilang selesai: cek `gh secret list --env production` (nama saja), cari run backend terakhir di main (`gh run list --workflow backend.yml`), tanya saya sebelum `gh run rerun <id>` atau memicu ulang.
4. Laporkan hasil job deploy (migrasi + wrangler deploy). Kalau gagal, baca log-nya dan jelaskan penyebab tanpa mencetak secret.
5. Kalau hijau: draf komentar penutup #38 (bahasa Inggris), tunjukkan dulu, lalu post + tutup setelah saya OK. Centang C2 di docs/mandates/umar.md lewat branch docs/C2-ci-done.
```

## Prompt 16 · `extensionActiveWindow` dan keputusan C17 (#40)

```text
Saya Umar (lead). Alief sudah mengisi hasil spike 01S di issue #40 (angka heartbeat, deteksi Off, pencabutan izin, openExtensionsSettings).

Baca: issue #40 (semua komentar), docs/spikes/extension-status.md, ios/ShooShared/AppGroup.swift (extensionActiveWindow sekarang 60*60*24), contracts/app-group-keys.md, ios/ShooExtension/Resources/heartbeat.js, ios/ShooApp/CLAUDE.md (aturan heartbeat-only), docs/mandates/umar.md (S1, C17).

Langkah:
1. Ringkas hasil spike dan usulan Alief untuk extensionActiveWindow; hitung risiko false-Off (user aktif tapi heartbeat telat) vs Off yang terlambat terdeteksi.
2. Rekomendasikan nilai window dan keputusan C17 (pakai SFSafariExtensionManager.stateOfExtension di iOS 26.2+ sebagai sumber kedua, atau tetap heartbeat saja). Tunggu keputusan saya.
3. Setelah saya putuskan: branch fix/EX-01-active-window. Ubah AppGroup.extensionActiveWindow (ios/ShooShared/ milik lead), perbarui contracts/app-group-keys.md kalau window disebut di sana, isi "## Result" di docs/spikes/extension-status.md, centang item S1/C17 di docs/mandates/umar.md.
4. Build cek: `cd ios && xcodegen` lalu build scheme Shoo untuk simulator (kalau Xcode tersedia); laporkan kalau tidak bisa.
5. Draf komentar keputusan untuk #40 (bahasa Inggris). Tunjukkan diff + draf dulu; jangan push/PR/post sebelum saya bilang.
```

## Prompt 18 · Tes U7 / EX-01 di iPhone

```text
Saya Umar (lead). Alief sudah merge ExtensionStatus yang membaca extension.allSites. Tugas: tes U7 / EX-01 di iPhone saya dan centang U7.

Baca: docs/mandates/umar.md (U7), docs/spikes/extension-status.md (checklist "To test on device"), ios/ShooExtension/Resources/heartbeat.js, ios/ShooExtension/CLAUDE.md (EX-01), contracts/app-group-keys.md.

Langkah:
1. Siapkan build: `cd ios && xcodegen`, cek ios/Config/Local.xcconfig ada (jangan commit), lalu beri saya langkah build ke iPhone saya (Xcode, scheme Shoo). Kamu tidak bisa mengendalikan iPhone fisik.
2. Beri saya checklist tes langkah demi langkah dari extension-status.md: aktifkan extension + "Allow on every website" → app Active; ubah ke "Ask"/beberapa situs → app Off (langsung atau setelah halaman berikut / alarm 1 jam); matikan extension → Off setelah window.
3. Saya laporkan hasil tiap langkah. Kamu catat di "## Result" docs/spikes/extension-status.md (tanggal, iOS, hasil, waktu).
4. Kalau lulus: centang U7 + sub-item di docs/mandates/umar.md. Kalau gagal: jelaskan penyebab yang mungkin dari kode, usulkan perbaikan, jangan ubah ios/ShooApp/ (milik Alief; buat draf issue untuknya).
5. Branch docs/EX-01-u7-device-test. Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 19 · TestFlight bagian Umar (#55)

```text
Saya Umar (lead, pemegang akun Apple berbayar "umar muhdhor"). Tugas bagian saya di issue #55 (Fase 16 TestFlight).

Baca: issue #55, plan/alief/TODO.md (B6, B7, B8, C23, D7), plan/alief/fase-16-qa-e2e.md, ios/project.yml, ios/Config/Shoo.xcconfig, ios/CLAUDE.md.

Buat checklist untuk saya jalankan sendiri (kamu tidak login ke Apple dan tidak menangani kunci):
1. Undang Alief ke tim di App Store Connect → Users and Access (peran yang cukup untuk build + TestFlight, sebutkan peran minimum).
2. B7: buat kunci APNs .p8 di developer.apple.com → Keys: Sandbox (untuk D7) dan Production (TestFlight), catat Key ID + Team ID, bagikan ke Alief lewat password manager. Jangan lewat chat atau repo.
3. B8: record App Store Connect untuk bundle ID SHOO_BUNDLE_ID tim saya + grup tester internal TestFlight.
4. Build pertama: cek bundle ID, App Group, capability (Push, App Groups) cocok di project.yml dan xcconfig; beri langkah Archive + upload (Xcode Organizer atau xcodebuild archive/exportArchive), dan apa yang harus dicek di App Store Connect setelah upload.
Lalu bantu saya: cek konfigurasi lokal secara read-only (xcconfig, entitlements, project.yml) dan laporkan ketidakcocokan. Siapkan draf komentar progres untuk #55 (bahasa Inggris) setelah saya laporkan langkah yang selesai. Jangan post sebelum saya bilang.
```

## Prompt 20 · Uji detector dan `/analyze` di Safari iPhone (D3)

```text
Saya Umar (lead, mengambil alih Team AI). Tugas D3: uji deteksi (layer 1–4) di Safari iPhone sungguhan.
Syarat: aiBaseURL sudah diisi Alief (prompt 2 / item 3) dan build terbaru terpasang di iPhone saya.

Baca: plan/imelda/TODO.md D3, docs/mandates/imelda.md (definisi sukses), ios/ShooExtension/CLAUDE.md, ios/ShooExtension/Resources/{pipeline,content,snapshot,marks}.js, ai/eval/data (sampel), contracts/fixtures.

Langkah:
1. Siapkan halaman uji yang AMAN (bukan situs scam asli): halaman HTML lokal yang meniru pola scam (brand + form PIN/OTP + iframe same-origin + teks mendesak), dilayani dari Mac di jaringan yang sama (python3 -m http.server di folder scratchpad). Jangan commit halaman uji ke repo kecuali saya minta.
2. Beri saya daftar kunjungan: 5 situs resmi dari brands.json (target skor < 30), halaman uji lokal (target popup 30/50, stabilo hanya teks, field dicoret, form di iframe ikut terbaca), dan Worker dimatikan/URL salah (layer 1–2 tetap jalan).
3. Saya laporkan skor/pill/popup tiap halaman (dan Web Inspector log "[Shoo]" kalau bisa). Kamu bandingkan dengan perilaku yang diharapkan dari kode.
4. Catat hasil di plan/imelda/log/fase-08.md (bagian uji device) atau file log baru plan/imelda/log/d3-device.md, centang D3 di plan/imelda/TODO.md. Branch docs/AI-D3-device-test.
5. Bug yang ditemukan: satu bug = satu test gagal dulu, lalu perbaikan di branch fix/<PRD-ID>-..., terpisah dari PR log ini.
Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 21 · Uji definisi sukses MVP di iPhone

```text
Saya Umar (lead). Tugas: uji 5 definisi sukses MVP di docs/mandates/umar.md di iPhone, plus perubahan #78 (stabilo hanya sinyal teks) dan #79 (form di iframe + blur screenshot).

Syarat: aiBaseURL terisi, U7 lulus (prompt 18), build terbaru (`cd ios && xcodegen` dulu karena ada snapshot.js baru).

Baca: docs/mandates/umar.md (Definisi sukses MVP, EX-01…EX-07), ios/ShooExtension/CLAUDE.md, ios/ShooExtension/Resources/{pipeline,popup,marks,block,report,snapshot}.js, contracts/api.md (verdicts, scans).

Langkah:
1. Buat checklist uji per kriteria dengan langkah dan hasil yang diharapkan:
   (1) EX-01…EX-07 sesuai kolom "Selesai kalau" di tabel Ringkasan docs/mandates/umar.md (ringkasan PRD 8.5; PRD lengkap di Google Doc, tautan di docs/README.md),
   (2) skor naik bertahap (layer 1–2 lalu 3–4) dan reset tiap pindah halaman,
   (3) Worker mati → halaman tetap terbuka, layer 1–2 jalan,
   (4) Guardian tekan It's safe → layar blokir di HP orang tua terbuka sendiri (butuh 2 device / akun Protected + Guardian),
   (5) tidak ada nilai input yang terkirim: cek body POST /scans dan screenshot (field di halaman dan di iframe ter-blur, iframe cross-origin tersembunyi).
2. Pakai halaman uji lokal yang aman (lihat prompt 20) untuk kasus scam; jangan buka situs scam asli.
3. Saya jalankan dan laporkan; kamu catat hasil di file baru docs/spikes/mvp-device-test.md (tanggal, iOS, build, hasil per kriteria, bukti).
4. Kriteria gagal: draf issue (EX-xx: ...) atau langsung perbaikan TDD di branch fix/EX-xx-... kalau ada di folder lead. Jangan ubah ios/ShooApp/ atau backend/.
5. Branch docs/EX-mvp-device-test. Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 22 · Field `accept` di PageSnapshot (C8)

```text
Saya Umar (lead, mengambil alih Team AI). Tugas U-7 / C8: tambahkan atribut `accept` (input file) ke PageSnapshot.forms[].fields supaya `asks_selfie_ktp` bisa memakai accept=image/*.

Baca: contracts/detector-interface.md (PageSnapshot), contracts/api.md (body /analyze), ai/src/validate.js, ai/src/layer3/forms.js, ai/test/forms.test.mjs, ios/ShooExtension/Resources/snapshot.js, ios/ShooExtension/Tests/snapshot.test.mjs, plan/imelda/TODO.md C8.

Aturan: perubahan kontrak HARUS aditif dan opsional (`accept?: string | null`); snapshot lama tanpa `accept` tetap valid. Tidak ada nilai input yang dibaca.

Langkah (TDD, branch feat/EX-02-field-accept):
1. Kontrak: tambah `accept` opsional di contracts/detector-interface.md (+ api.md kalau field disebut di sana). Fixture contracts/fixtures tidak wajib diubah.
2. Extension: test dulu di snapshot.test.mjs (input file dengan accept="image/*" → accept terisi; field lain → null), lalu snapshot.js membaca getAttribute("accept").
3. Server: cek ai/src/validate.js menerima field baru (dan menolak tipe salah kalau validasinya ketat); test dulu di ai/test/forms.test.mjs (input file accept=image/* + label/nama KTP/selfie → asks_selfie_ktp), lalu forms.js.
4. Kalau detector/ ikut berubah: detector/scripts/sync-to-extension.sh.
5. Semua test: node --test --test-concurrency=1 'ios/ShooExtension/Tests/*.test.mjs' 'detector/test/**/*.test.mjs' 'ai/test/**/*.test.mjs' 'ai/eval/test/**/*.test.mjs'.
6. Centang C8 di plan/imelda/TODO.md dan U-7 di plan/umar/sisa-kerja.md.
Tunjukkan diff dulu; jangan push/PR sebelum saya bilang.
```

## Prompt 23 · Pertanyaan PM dan video ON-04 (#37)

```text
Saya Umar (lead). Tugas: siapkan pesan ke PM untuk dua hal yang masih terbuka.

Baca: docs/README.md ("Open questions for PM" dan "Decisions"), docs/mandates/umar.md (bagian Lead), issue #37 (video ON-04), plan/alief/TODO.md C15.

Langkah:
1. Ringkas setiap pertanyaan terbuka: apa yang ditanyakan, kenapa penting untuk MVP, opsi jawaban, dan default kita kalau PM tidak menjawab. PRD hanya ada di Google Doc (tautan di docs/README.md); kalau kamu tidak bisa membukanya, minta saya menempel bagian §4 Scope.
2. Ringkas permintaan video ON-04 dari #37: durasi ≤ 60 detik, ramah orang tua, MP4 H.264, EN + ID, caption; tenggat yang dibutuhkan Alief.
3. Draf satu pesan ke PM (bahasa Indonesia, singkat, bernomor) yang bisa saya kirim sendiri. Kamu tidak mengirim pesan.
4. Setelah saya kirim dan PM menjawab: catat jawaban di docs/README.md bagian Decisions (branch docs/PM-answers) dan komentar di #37; centang item Lead terkait di docs/mandates/umar.md.
Tunjukkan draf dulu.
```

## Prompt 24 · Runbook review antrean blocklist (C6)

```text
Saya Umar (lead). Tugas C6: siapkan review manual berkala antrean blocklist bersama Alief (lewat SQL editor Supabase).

Baca (hanya membaca, backend/ milik Alief): docs/design/blocklist.md, contracts/api.md (bagian Blocklist), backend/db (migrasi tabel blocklist/antrean, cari dengan grep), plan/alief/fase-10-be-verdicts.md, plan/alief/log (fase 10), docs/mandates/umar.md C6.

Langkah:
1. Cek apakah fase 10 backend sudah merge dan tabel antrean ada di main. Kalau belum, berhenti dan laporkan.
2. Jelaskan alur: dari mana entri antrean datang (verdict not_safe? laporan?), kapan masuk GET /blocklist, apa yang bisa salah (situs resmi masuk blocklist).
3. Tulis plan/umar/blocklist-review.md: tujuan, jadwal usulan (mis. 2× seminggu), siapa melakukan apa, query SQL SELECT saja (read-only) untuk melihat antrean, kriteria terima/tolak (cek terhadap detector/data/brands.json dan daftar populer), dan cara mencatat keputusan. Perubahan data (UPDATE/DELETE) hanya sebagai langkah yang dijalankan Alief/saya secara manual, bukan otomatis.
4. Draf issue ke Alief (template question, bahasa Inggris) untuk menyepakati jadwal dan query.
5. Branch docs/C6-blocklist-review. Tunjukkan diff + draf issue dulu; jangan push/PR/buat issue sebelum saya bilang.
```

## Prompt 25 · Hapus branch yang sudah merge

```text
Saya Umar (lead). Tugas: bersihkan branch yang sudah merge ke main.

Langkah:
1. `git fetch --prune origin`. Daftar branch remote yang sudah merge: `git branch -r --merged origin/main`, kecuali origin/main dan origin/HEAD.
2. Untuk tiap branch: cek PR-nya MERGED (`gh pr list --state merged --head <branch>`), dan tidak ada PR terbuka yang memakainya sebagai base (`gh pr list --state open --base <branch>`). Pisahkan yang aman dihapus dan yang perlu dicek.
3. Lakukan hal yang sama untuk branch lokal (`git branch --merged main`), kecuali main dan branch yang sedang dipakai.
4. Tunjukkan tabel: branch, PR, aman dihapus ya/tidak, alasan. Branch milik Alief (feat/APP-*, feat/GD-*, chore/APP-*, docs/alief-*, dst.) ditandai terpisah: jangan dihapus tanpa izin Alief.
5. Setelah saya OK: hapus yang saya setujui (`git push origin --delete <branch>` dan `git branch -d <branch>`). Jangan pakai -D (paksa).
```
