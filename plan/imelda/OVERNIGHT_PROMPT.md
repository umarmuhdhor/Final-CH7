# Prompt semalaman — fase 05 sampai 08 (Team AI, Imelda)

Imelda tidak ada di depan layar. Jalankan lewat `plan/imelda/PROMPT.md`, dengan perubahan aturan di bawah.

Sebelum pergi:
- Sesi pakai mode izin yang tidak berhenti di tiap perintah (auto / accept edits), kalau tidak sesi macet semalaman.
- Mac jangan tidur: `caffeinate -dimsu` di terminal lain.

Tempel blok ini ke Claude Code di root `Final-CH7`:

```text
Saya Imelda, Team AI. Saya tidur dan tidak bisa menjawab apa pun sampai pagi.
Kerjakan fase 05, 06, 07, 08 berurutan sesuai plan/imelda/PROMPT.md, dengan ATURAN SEMALAMAN di bawah.
Aturan semalaman MENGALAHKAN PROMPT.md bila bertentangan. Tidak ada pertanyaan ke saya: kalau ragu, pilih
opsi paling aman (privasi, false positive rendah), catat di log/DECISIONS.md (D-imelda-NN), lanjut.

<keadaan_awal>
- Cabang sekarang feat/AI-M2-eval-data (fase 04, ahead 7, belum di-push). plan/imelda/fixbug.md punya perubahan
  yang belum di-commit: commit dulu di cabang itu (`docs(plan): record F-04 findings from eval data`).
- Fase 02 = PR #44 (feat/AI-M3-forms), fase 03 = PR #50 (feat/AI-M3-content, sudah memuat forms). Keduanya
  masih OPEN, jadi `ai/src` (service Hono, layer3, rdap) hanya ada di feat/AI-M3-content, bukan di main.
  Data eval 50+50 hanya ada di feat/AI-M2-eval-data. Fase 05-08 butuh keduanya.
- Langkah 0 (sekali): `git fetch origin`. Segarkan status PR (`gh pr view 44/50 --json state`). Buat cabang
  `wip/AI-overnight-base` dari feat/AI-M3-content, lalu `git merge feat/AI-M2-eval-data`. Konflik (PROGRESS,
  fixbug, ai/README, ai/eval/*): gabungkan dua sisi, jangan buang baris siapa pun. Jalankan semua test.
  Kalau PR #44/#50 ternyata sudah MERGED, pakai origin/main sebagai dasar gantinya.
- Rantai cabang (stacked, tiap fase di atas fase sebelumnya):
  05 feat/AI-M5-server dari wip/AI-overnight-base -> 06 feat/AI-M4-reality-check dari 05
  -> 07 feat/AI-M6-calibration dari 06 -> 08 feat/AI-M7-deploy dari 07.
  Ini beda dari PROMPT.md langkah 3 (yang bilang dari origin/main); catat di DECISIONS.
- Fase 04 sendiri belum punya PR: buka PR-nya dulu (feat/AI-M2-eval-data -> main) sebelum mulai fase 05.
</keadaan_awal>

<aturan_semalaman>
1. BOLEH: git push cabang kita sendiri (feat/AI-*, wip/AI-overnight-base) dan `gh pr create` — saya sudah
   mengizinkan, ini menggantikan PROMPT.md langkah 11 (tidak perlu bertanya). Syarat PR sesuai PROMPT.md:
   judul `<ID>: <judul>`, reviewer umarmuhdhor, isi = ringkasan log + cara menguji + tabel eval, status [r] + nomor PR.
   Buka PR hanya untuk fase yang test-nya hijau dan sudah lolos review; fase [!] tidak di-PR-kan.
   Stacked: PR fase 04 (feat/AI-M2-eval-data) base main. PR 05 base wip/AI-overnight-base (push cabang itu),
   PR 06 base cabang 05, PR 07 base cabang 06, PR 08 base cabang 07; tulis di isi PR "stacked on #<no>, ubah
   base ke main setelah #44/#50/sebelumnya merged". Fase [m] boleh di-PR kalau kodenya selesai; tulis
   LANGKAH MANUAL yang tersisa di isi PR.
   DILARANG: gh pr merge, push ke main atau cabang milik orang lain, force push, deploy, mengubah
   secret/akun cloud, sudo, memasukkan password. Jangan kirim pesan ke Umar/Alief; tulis di TODO §C.
2. Tidak ada API key. Jangan mencari, meminta, atau membuat key. Jangan panggil LLM sungguhan, jangan buka URL
   scam. Satu-satunya jaringan yang boleh: membaca dokumentasi/lisensi publik lewat WebFetch/WebSearch.
3. Hambatan LANGKAH MANUAL tidak menghentikan seluruh run. Kerjakan semua yang bisa dikerjakan tanpa
   langkah manual, tulis checklist [ ] di log fase untuk sisanya, tandai PROGRESS baris fase [m], lalu LANJUT
   ke fase berikutnya (bukan berhenti seperti di PROMPT.md langkah 13).
4. Satu kegagalan yang sama 3 kali (test, build, review) = tandai fase [!], tulis penyebab + keluaran
   perintah di log, kembali ke cabang yang hijau, lanjut ke fase berikutnya yang tidak bergantung padanya.
5. Test baseline tidak boleh turun. Jangan hapus atau lemahkan test. Jangan turunkan target eval.
6. Sebelum tiap fase: `git status` bersih, test hijau. Sesudah tiap fase: commit, update PROGRESS + log.
7. Tiap fase: review `ecc:security-reviewer` + `ecc:typescript-reviewer`, perbaiki CRITICAL/HIGH.
   Kalau subagent tidak tersedia, review sendiri dengan SECURITY.md §5 dan catat bahwa itu review mandiri.
</aturan_semalaman>

<per_fase>
FASE 05 — /public-blocklist (M5-A)
- Sumber daftar belum disetujui saya (TODO A3). Jangan memilih sumber dan jangan mengunduh feed.
  Riset dokumentasi + lisensi 3-4 kandidat (mis. OpenPhish community, PhishTank, URLhaus, phishing.army) dari halaman
  resmi mereka; tulis tabel (lisensi, boleh dipakai di app?, format, frekuensi, ukuran) di log + ai/README.md,
  tandai "BELUM DIVERIFIKASI" untuk yang tidak jelas, dan rekomendasikan satu dengan alasan.
- Bangun semuanya di belakang antarmuka sumber (`ai/src/blocklist/source.js`) dengan sumber fixture
  `ai/data/public-blocklist.seed.json` (domain karangan, bukan feed nyata): registrable domain (Public Suffix
  List), filter allowlist (brands.json + situs populer + host berbagi seperti github.io tanpa subdomain),
  `since`, `removed`, `nextSince`, batas 200.000, rate limit per IP, token Bearer tidak diverifikasi dan tidak
  dilog. Respons persis docs/design/blocklist.md. TDD sesuai fase-05 file.
- Selesai = semua DoD fase-05 kecuali "sumber + lisensi tercatat" (itu [m] menunggu persetujuan saya).

FASE 06 — Reality check LLM (M4)
- Tanpa key. Bangun lapisan penyedia generik (`ai/src/layer4/`): model + base URL + key dari env, timeout,
  validasi JSON dengan skema (keluaran rusak diabaikan, bukan error), anggaran total 8 detik, LLM mati/timeout
  -> layer 3 saja. Uji dengan penyedia PALSU (mock) saja. Prompt di ai/prompts/, input = jenis halaman + data
  yang diminta (bukan seluruh halaman), isi halaman hanya sebagai data. Test prompt injection
  ("abaikan instruksi sebelumnya") di mock. Gerbang panggilan D-imelda-05 (form >= 1 field dan skor sementara
  >= 15): pakai usulan, catat sebagai sementara. `.env.example` diperbarui; tanpa key sungguhan.
- Jangan memilih model (TODO A2) dan jangan mengklaim eval layer 4. Di log tulis [m]: pilih model, isi
  ai/.env, jalankan `node ai/eval/run.mjs --analyze-url ... ` dengan dan tanpa layer 4. Jangan mengisi tabel
  eval layer 4 dengan angka karangan.
- Kerjakan juga F-04-5 sejauh bisa tanpa LLM: catat di fixbug.md bahwa itu tugas layer 4 dan butuh model asli.

FASE 07 — Kalibrasi bobot (M6)
- Ikuti ref/R2: pisahkan sampel tuning dan uji (holdout bertanda di data), jalankan eval apa adanya = "Sebelum".
  Kalibrasi hanya layer 1-3 (layer 4 belum bisa diukur). Urutan: nol salah blokir dulu, baru deteksi.
  Satu perubahan bobot = satu commit + alasan di log. Tangani F-04-1 .. F-04-4 lewat aturan, bukan pengecualian
  per domain. Tidak boleh menghafal sampel; laporkan angka tuning dan angka uji terpisah.
- Ukur analyzeLocal < 50 ms dan /analyze lokal. Jalankan detector/scripts/sync-to-extension.sh bila bobot detector
  berubah. Isi tabel Sebelum/Sesudah di PROGRESS dengan angka dari keluaran perintah.
- Target tidak tercapai = laporkan angkanya apa adanya (TODO C6 untuk Umar), jangan ubah target atau ambang.
  Ambang 30/50/80 milik Umar: jangan diubah.

FASE 08 — Deploy (M7)
- Hanya kode + persiapan: rate limit per IP dan batas body (413) untuk /analyze dan /public-blocklist, header
  keamanan, CORS, tanpa log URL/teks/form. TDD (429/413). Siapkan perintah deploy + secret dan checklist
  LANGKAH MANUAL di log/fase-08.md (akun hosting B2, secret, URL, smoke test curl, p95). Tandai [m]. Tidak ada deploy.
</per_fase>

<laporan_pagi>
Di akhir (atau bila semua fase [m]/[!]), tulis plan/imelda/log/MORNING.md, Bahasa Indonesia sederhana, ≤ 40 baris:
1. Tabel 4 fase: status, cabang, hash commit terakhir, jumlah test (angka dari keluaran perintah).
2. Hasil eval Sebelum/Sesudah (kalau ada) dan target yang belum tercapai.
3. Daftar tugas manual untuk saya, berurutan: sumber daftar (A3), model + key (A2/B1), gerbang A5, akun hosting (B2).
4. Keputusan baru D-imelda-NN yang saya perlu setujui.
5. Daftar PR yang dibuka (nomor, URL, base) dan fase yang tidak di-PR-kan beserta alasannya.
Lalu berhenti. Jangan commit file MORNING.md ke cabang fase mana pun.
</laporan_pagi>
```
