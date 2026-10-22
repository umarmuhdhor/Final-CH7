# Fase 01 — Layer 1 sisi detector: `db_match` (M5-B)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M5-detector` |
| Prasyarat | M1 merged. `ShooLists` sudah ada di `main` (`ios/ShooExtension/Resources/lists-client.js`) |
| Requirement | M5 bagian B |
| Fase berikutnya | 02 |

## Tujuan

Kalau domain yang sedang dibuka ada di daftar (milik Shoo atau daftar phishing publik), detector langsung memberi `db_match` bobot 100 tanpa jaringan.

## Bacaan wajib

- `docs/mandates/imelda.md` bagian M5, `docs/design/blocklist.md`
- `contracts/detector-interface.md` (bentuk sinyal, id `db_match`)
- `ios/ShooExtension/Resources/lists-client.js` (bentuk `match`, nilai balik `hit.source`)
- `detector/src/detector.js`, `detector/CLAUDE.md`

## Langkah kerja

1. Test dulu dengan mock `globalThis.ShooLists = { match: async (h) => ... }`: cocok, tidak cocok, `ShooLists` tidak ada.
2. Di `analyzeLocal`: `const hit = await globalThis.ShooLists?.match(new URL(snapshot.url).hostname)`.
   - Ada → kembalikan `db_match` (layer 1, weight 100, `label`/`labelSimple` EN + ID, `evidence` = `hit.source`).
   - `null`/tidak ada → lanjut aturan layer 2 seperti biasa.
3. Pastikan `match` yang melempar error tidak menjatuhkan `analyzeLocal` (tangkap, lanjut layer 2).
4. `detector/scripts/sync-to-extension.sh`, commit `src/` dan `detector.js` bersamaan.
5. Ukur `analyzeLocal` < 50 ms dengan mock (catat angkanya).

## Verifikasi

```bash
node --test detector/test ai/eval/test ios/ShooExtension/Tests
grep -nE "fetch|XMLHttpRequest|WebSocket" detector/src/detector.js   # harus kosong
```

## Kriteria selesai (DoD)

- [ ] `db_match` muncul untuk domain yang di-mock cocok (test).
- [ ] Tanpa `ShooLists` atau `match` melempar error → tetap jalan (test).
- [ ] Tidak ada request jaringan di detector (grep kosong).
- [ ] `label` dan `labelSimple` EN + ID; `labelSimple` tanpa istilah teknis.
- [ ] Baseline test tetap hijau.

## Catatan handoff

- Fase 05 membuat daftar yang dikonsumsi `ShooLists`; fase ini tidak memanggilnya.
