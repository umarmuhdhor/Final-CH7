# Backup: layer 3 rules (arsitektur lama)

Salinan layer 3 seperti di `main` commit `2b9bf6c1` (2026-11-18), sebelum model impersonation masuk.
Git tag yang sama: `l3-rules-2026-11-18`.

Folder ini **tidak di-import** oleh Worker, dev-server, atau tes. Ini arsip, bukan kode yang jalan.

## Isi

- `src/analyze.js`: alur layer 3 (rules + umur domain + gate layer 4), tanpa opsi `model`.
- `src/layer3/*.js`: rules form (`forms.js`), rules konten (`content.js`), brand/resmi (`official.js`, `match.js`, `fingerprints.js`), signal (`signals.js`), teks (`text.js`).

## Pakai arsitektur lama

1. **Cara biasa (tanpa folder ini):** jalankan server tanpa flag. Rules di `ai/src/layer3` tetap jalan, model tidak.
   ```
   cd ai && node src/dev-server.mjs
   ```
   Arsitektur baru: `SHOO_L3_MODEL=impersonation node src/dev-server.mjs`.
2. **Kalau rules di `ai/src` nanti diubah atau dihapus** dan perlu versi ini lagi:
   ```
   git checkout l3-rules-2026-11-18 -- ai/src/layer3 ai/src/analyze.js
   ```
   atau salin isi `src/` folder ini ke `ai/src/`. Import di file ini relatif ke `ai/src/` (`./validate.js`, `../signal-ids.js`), jadi file tidak bisa dijalankan dari folder arsip.
