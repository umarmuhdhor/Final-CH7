# Fixbug — tracker perbaikan dari QA (Alief)

Dipakai setelah setiap ronde QA (06Q dan 16). Satu bug = satu test yang gagal dulu = satu commit = satu branch `fix/QA-<ronde>-<ID>-<slug>` (atau beberapa bug kecil yang berkaitan dalam satu PR). Centang kotak saat commit-nya sudah ada di branch fix dan PR dibuka.

## Aturan

- Urutan: semua P0, lalu P1, lalu P2. P3 hanya kalau sempat.
- Setiap perbaikan dimulai dari test yang mereproduksi bug (Swift Testing / XCUITest / vitest / pgTAP) — `superpowers:systematic-debugging` sebelum mengubah kode.
- Setelah merge, jalankan **retest** sesuai langkah di laporan QA dan tulis blok "Retest" di laporan (R7 §4).
- Bug di luar folder kita (extension, detector, kontrak) → jangan diperbaiki. Tulis di bagian "Diteruskan" dengan isi pesan untuk Umar/Imelda (TODO §C).

## Ronde QA-A (fase 06Q)

Laporan: [`qa/QA-A-2026-10-22.md`](qa/QA-A-2026-10-22.md). P0 = 0, P1 = 0; P2 kecil yang berkaitan (tata letak XL / layar kecil) digabung dalam satu PR, satu commit per bug.

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| P2-1 | P2 | ON-01 | Titik halaman menimpa teks splash di XL | `QALayoutUITests.testSplashDotsDoNotCoverText` | `fix/QA-A-P2-layout` | [ ] |
| P2-2 | P2 | ON-03 | Kata terpotong di kartu mode (XL) | `QALayoutUITests.testModeCardTextUsesFullWidthAtAccessibilitySizes` | `fix/QA-A-P2-layout` | [ ] |
| P2-3 | P2 | DT-01 | Cincin skor Detail memenuhi layar di XL | `ComponentLogicTests` (ukuran cincin) | `fix/QA-A-P2-layout` | [ ] |
| P2-4 | P2 | GD-03 | Tombol Invite tertutup tab bar | `QALayoutUITests.testInviteButtonIsAboveTabBar` | `fix/QA-A-P2-layout` | [ ] |
| P2-5 | P2 | PR-05 / komponen | Judul empty state terpotong, deskripsi `.secondary` | screenshot retest (judul terpotong tidak terlihat di pohon aksesibilitas) | `fix/QA-A-P2-layout` | [ ] |
| P2-6 | P2 | A11y | Suara VoiceOver tidak ikut bahasa app | butuh iPhone + VoiceOver | ditunda ke QA-E2E #14 | [ ] |

## Ronde QA-E2E (fase 16)

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| | | | | | | [ ] |

## Diteruskan ke tim lain

| ID | Ke | Isi singkat | Status |
|---|---|---|---|
| | | | |
