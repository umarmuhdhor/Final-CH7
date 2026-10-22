# Master prompt: verifikasi seluruh plan Imelda (read-only)

Tempel blok di bawah ke AI mana pun (Claude Code, Codex, dll.) di root repo `umarmuhdhor/Final-CH7`.

```text
<peran>
Kamu reviewer teknis independen untuk Shoo (iPhone Safari Web Extension + app yang memblokir situs penipuan).
Tugasmu MEMBACA, MEMAHAMI, dan MEMVERIFIKASI rencana kerja Imelda (Team AI) di plan/imelda/.
Jangan mengubah, membuat, atau menghapus file apa pun. Jangan commit. Jangan menjalankan build, install,
atau perintah cloud. Jawab dalam Bahasa Indonesia, kalimat sederhana.
</peran>

<bacaan>
Baca berurutan dan lengkap:
1. CLAUDE.md (root), detector/CLAUDE.md, ai/CLAUDE.md, .github/CODEOWNERS
2. docs/README.md, docs/mandates/imelda.md, docs/design/blocklist.md
3. contracts/README.md, contracts/api.md, contracts/detector-interface.md, contracts/scan-result.schema.json,
   contracts/fixtures/*.json
4. ios/ShooExtension/Resources/pipeline.js, lists-client.js, capture.js, content.js, manifest.json
5. detector/src/detector.js, detector/data/brands.json, detector/test/, ai/eval/ (README, run.mjs, lib.mjs, tools/, data/)
6. plan/imelda/README.md, PROMPT.md, PROGRESS.md, TODO.md, ARCHITECTURE.md, SECURITY.md, fixbug.md
7. plan/imelda/log/DECISIONS.md (keputusan yang lebih baru MENGALAHKAN teks lama yang bertentangan)
8. plan/imelda/fase-01 … fase-08, plan/imelda/ref/*
9. Sebagai pembanding pola: plan/alief/README.md dan SECURITY.md
</bacaan>

<yang_diverifikasi>
A. PEMAHAMAN. Ringkas: produknya apa, 5 layer deteksi, siapa memiliki apa (kita: bobot; Umar: ambang), alur snapshot →
   analyzeLocal → /analyze → skor → popup/blokir, dan apa yang terjadi saat server mati.
B. CAKUPAN MANDAT. Setiap checkbox di docs/mandates/imelda.md (M1–M7) dipetakan ke satu fase? Ada yang hilang, dobel,
   atau di luar folder detector/ dan ai/?
C. KONSISTENSI KONTRAK. Apakah plan cocok dengan contracts/api.md dan detector-interface.md (bentuk request/respons,
   id sinyal, layer, evidence persis, label dua bahasa)? Apakah ada fase yang diam-diam mengubah kontrak
   (id sinyal baru, field snapshot baru, layer new_domain) tanpa usulan ke Umar? Sebut setiap selisih dengan file:baris.
D. ATURAN REPO. Hard rule CLAUDE.md (folder, contracts/, satu branch = satu ID PRD, secret). Apakah plan melanggar?
E. KELAYAKAN TEKNIS. Worker Free (CPU, subrequest), RDAP (kuota, format, TLD yang tidak punya RDAP), API LLM (latensi,
   biaya, JSON terstruktur), batas 8 detik total. Apakah anggaran latensi di ref/R1 masuk akal? Tandai asumsi yang
   belum terbukti dan apakah ada langkah uji untuknya.
F. KEAMANAN. Prompt injection dari halaman scam, SSRF lewat RDAP, ReDoS, log yang membocorkan URL/teks, evidence palsu,
   peracunan daftar publik, lisensi feed, key LLM, biaya yang meledak. Apakah SECURITY.md + fase menutupnya?
G. KUALITAS EVAL. Apakah protokol di ref/R2 cukup untuk membuktikan target mandat (situs resmi < 30, scam ≥ 50 / ≥ 80)?
   Ada risiko menghafal sampel, kelas tidak seimbang, atau metrik yang menyesatkan?
H. EKSEKUSI OTOMATIS. Apakah PROMPT.md cukup jelas agar AI bekerja tanpa ambigu (pemilihan fase, batas push/PR,
   LANGKAH MANUAL, placeholder TODO(sync), sinkronisasi setelah merge)? Sebutkan instruksi yang ambigu.
</yang_diverifikasi>

<format_jawaban>
1. Ringkasan pemahaman (maks 12 poin).
2. Verdict: SIAP / SIAP DENGAN CATATAN / BELUM SIAP, plus alasan satu kalimat.
3. Tabel temuan, urut dari paling parah:
   | # | Tingkat (KRITIS/TINGGI/SEDANG/RENDAH) | File § bagian | Masalah | Usulan perbaikan |
   Maks 25 baris. Setiap temuan menyebut file dan bagian spesifik. Jangan menebak.
4. Kontradiksi antar-dokumen, satu poin per pasangan file.
5. Lima risiko terbesar untuk MVP + mitigasinya.
6. Pertanyaan yang harus dijawab Imelda/Umar sebelum fase 02 dan 06 (maks 8).
Kalau suatu bagian tidak bisa diverifikasi, katakan terus terang.
</format_jawaban>
```
