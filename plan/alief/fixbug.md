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
| P2-1 | P2 | ON-01 | Titik halaman menimpa teks splash di XL | `QALayoutUITests.testSplashDotsDoNotCoverText` | `fix/QA-A-P2-layout` | [x] `8da5da0` |
| P2-2 | P2 | ON-03 | Kata terpotong di kartu mode (XL) | screenshot retest (kartu satu elemen VoiceOver) | `fix/QA-A-P2-layout` | [x] `17b442e` |
| P2-3 | P2 | DT-01 | Cincin skor Detail memenuhi layar di XL | `ComponentLogicTests.scoreRingGrowsUpToItsCap` | `fix/QA-A-P2-layout` | [x] `8acfe63` |
| P2-4 | P2 | GD-03 | Tombol Invite tertutup tab bar | `QALayoutUITests.testInviteButtonIsAboveTabBar` | `fix/QA-A-P2-layout` | [x] `1e1f719` |
| P2-5 | P2 | PR-05 / komponen | Judul empty state terpotong, deskripsi `.secondary` | screenshot retest (judul terpotong tidak terlihat di pohon aksesibilitas) | `fix/QA-A-P2-layout` | [x] `01cb7fd` |
| P2-7 | P2 | GD-01/03 | Banner notifikasi menempel memakan layar (SE + XL) | `QALayoutUITests.testInviteButtonIsReachableAtAccessibilitySizes` | `fix/QA-A-P2-layout` | [x] `509366a` |
| P2-6 | P2 | A11y | Suara VoiceOver tidak ikut bahasa app | butuh iPhone + VoiceOver | ditunda ke QA-E2E #14 | [ ] |

## Ronde QA-E2E (fase 16)

Laporan: [`qa/QA-E2E-2026-11-09.md`](qa/QA-E2E-2026-11-09.md) (simulator + stack lokal). P0 = 0, P1 = 0. Ronde iPhone fisik (TestFlight) belum.

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| P2-1 | P2 | GD-02 / PF-01 | Guardian dengan anggota tetap "Personal" + kartu "Become a Guardian" sampai Family mode dinyalakan | – | – | [ ] menunggu keputusan desain |

## Ronde Fase 27 (audit state machine tersirat)

Plan + bukti: [`fase-27-state-machines.md`](fase-27-state-machines.md), [`log/fase-27.md`](log/fase-27.md). Test repro di `log/fase-27-repro/` (pindahkan ke suite saat memperbaiki).

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| F-A1 | T | ON-04 | Link undangan melewati consent di tengah alur + ON-04 + izin notifikasi | `inviteJoinDoesNotSwapOnboardingOutForConsent`, `protectedAfterInviteStillReachesTurnOnExtension` | `fix/ON-04-invite-onboarding-states` | [ ] |
| F-A2 | S | ON-04 | Join undangan gagal sudah menyimpan mode Protected (terkunci, tanpa jalan batal) | `failedInviteJoinSavesNoMode` | `fix/ON-04-invite-onboarding-states` | [ ] |
| F-B1 | S | PF-01 | Become-protected dengan kode sendiri → Protected tanpa Guardian | `F-B1` | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B2 | S | PF-01 | Cek `has_members` tanpa kunci, anggota baru kehilangan link | `F-B2 replay` | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B3 | S | PF-01 | Join commit sebelum delete → salinan hantu memakan slot | `F-B3 state-only` | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B6 | S | PF-01 | Batas percobaan join di become-protected tidak bekerja (id salinan baru tiap kali) | baru di 27a | `fix/PF-01-become-protected-atomic` | [ ] |
| F-B4 | S | DT-06 | Verdict `safe` terlepas saat url baris ditulis ulang | `F-B4` | `fix/DT-06-verdict-row-frozen` | [ ] (tunggu Q4) |
| F-A4 | S | GD-01 | Verdict Home ditimpa refresh lama | `homeVerdictIsNotUndoneByAnOlderRefresh` | `fix/GD-01-home-verdict-state` | [ ] |
| F-N1 | R | GD-01 | Home memasang verdict ke seluruh domain (aturan salah; tidak terlihat karena server satu baris per situs) | baru di 27e | `fix/GD-01-home-verdict-state` | [ ] |
| F-A5 | S | PR-05 | Spinner "memuat lagi" macet | `loadingMoreSpinnerClearsAfterAFailedRefresh` | `fix/PR-05-activity-list-states` | [ ] |
| F-A6 | S | PR-05 | Activity memakai model device lama setelah jadi Protected | baru di 27f | `fix/PR-05-activity-list-states` | [ ] |
| F-N2 | S | GD-06 | Push Protected dengan `scanId` membuka Shield | ganti `protectedPushTapOpensShield` | `fix/GD-06-push-tap-and-clear` | [ ] |
| F-N3 | S | GD-06 | Putus dari detail anggota tidak menghapus push (P13) | baru di 27g | `fix/GD-06-push-tap-and-clear` | [ ] |
| F-A3 | S | PF-01 | 401 lama saat switch → Session expired dengan sesi baru valid | baru di 27h | `fix/PF-01-session-lifecycle` | [ ] |
| F-A8 | S | PF-01 | `register()` tidak mereset `sentDeviceInfo` | baru di 27h | `fix/PF-01-session-lifecycle` | [ ] |
| F-B7 | R | GD-07 | Domain yang ditolak kembali ke antrean | `F-B7` | `fix/GD-07-rejected-stays-rejected` | [ ] |
| F-N4 | S | PF-01 | Salinan Protected membawa weekly summary + quiet hours tak terlihat | perbarui `settings.test.ts:296-312` | `fix/PF-01-protected-copy-settings` | [ ] (quiet hours tunggu Q2) |
| F-B5 | R/? | GD-05 | Guardian melihat riwayat anggota sebelum terhubung | probe `F-B5` | – | [ ] tunggu Q1 |
| F-A14 | R | ON-04 | Relaunch setelah registrasi undangan langsung `.done` | baru di 27d | `fix/ON-04-invite-onboarding-states` | [ ] |
| F-A15 | R | PR-05 | Verdict Detail tidak muncul di list Activity | baru di 27f | `fix/PR-05-activity-list-states` | [ ] |
| F-A12, F-A13, F-N7 | R | PF-01 | `me()` lama menulis guardian, key App Group tersisa, hapus akun → Session expired | baru di 27h | `fix/PF-01-session-lifecycle` | [ ] |
| F-A11/F-N5, F-N6 | R | PF-01 | Rollback toggle, quiet hours mulai = selesai | baru di 27i | `fix/PF-01-settings-rollback` | [ ] |
| F-A9 | R | GD-03 | "Dimatikan" lambat sampai ke Guardian | – | – | [ ] tunggu Q3 |
| F-B8, F-B9, F-B12, F-N10, F-A10 | R | – | Favicon ready, replica macet, kelas kunci, cron limit, refresh kode | lihat plan §27k | lihat plan §27k | [ ] |
| F-B10, F-B11, F-B13, F-N8, F-N9 | R | – | Diterima, dicatat di 27z | – | – | diterima |

## Diteruskan ke tim lain

| ID | Ke | Isi singkat | Status |
|---|---|---|---|
| | | | |
