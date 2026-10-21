# Fixbug — tracker perbaikan dari QA (Alief)

Dipakai setelah setiap ronde QA (06Q dan 16). Satu bug = satu test yang gagal dulu = satu commit = satu branch `fix/QA-<ronde>-<ID>-<slug>` (atau beberapa bug kecil yang berkaitan dalam satu PR). Centang kotak saat commit-nya sudah ada di branch fix dan PR dibuka.

## Aturan

- Urutan: semua P0, lalu P1, lalu P2. P3 hanya kalau sempat.
- Setiap perbaikan dimulai dari test yang mereproduksi bug (Swift Testing / XCUITest / vitest / pgTAP) — `superpowers:systematic-debugging` sebelum mengubah kode.
- Setelah merge, jalankan **retest** sesuai langkah di laporan QA dan tulis blok "Retest" di laporan (R7 §4).
- Bug di luar folder kita (extension, detector, kontrak) → jangan diperbaiki. Tulis di bagian "Diteruskan" dengan isi pesan untuk Umar/Imelda (TODO §C).

## Ronde QA-A (fase 06Q)

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| | | | | | | [ ] |

## Ronde QA-E2E (fase 16)

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| | | | | | | [ ] |

## Diteruskan ke tim lain

| ID | Ke | Isi singkat | Status |
|---|---|---|---|
| | | | |
