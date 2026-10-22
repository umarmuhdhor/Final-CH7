# Fixbug — tracker perbaikan dari eval (Imelda)

Dipakai setelah setiap run eval besar (fase 04 dan 07) atau laporan salah deteksi dari tim. Satu temuan = satu test yang gagal dulu = satu commit = satu branch `fix/AI-<ID>-<slug>` (beberapa temuan kecil yang berkaitan boleh satu PR).

## Aturan

- Urutan: **false positive di situs resmi dulu**, lalu scam yang lolos, lalu kelambatan, lalu kosmetik.
- Mulai dari test yang mereproduksi temuan (sampel eval + test aturan). `superpowers:systematic-debugging` sebelum mengubah kode.
- Perbaikan yang butuh perubahan bobot lintas sinyal → jangan tambal satu sampel; kumpulkan dan kerjakan di fase 07 dengan tabel sebelum/sesudah.
- Jangan menambah pengecualian per domain ("kalau `x.com` jangan"). Perbaiki aturannya, atau tambahkan brand ke `brands.json`.
- Temuan di luar folder kita (snapshot, pipeline, ambang, kontrak) → tulis di "Diteruskan" dengan isi pesan untuk Umar/Alief (TODO §C). Jangan diperbaiki sendiri.

## Prioritas

| Prio | Definisi | Contoh |
|---|---|---|
| P0 | Situs resmi terblokir (skor ≥ 80) atau data pribadi bocor lewat server | Domain bank resmi skor 85; URL muncul di log |
| P1 | Situs resmi terkena peringatan (30–79); scam populer lolos (< 30) | Toko resmi skor 35; kampanye scam kurir skor 12 |
| P2 | Alasan membingungkan, `labelSimple` pakai istilah teknis, latensi lewat anggaran | "TLD" tampil ke orang tua |
| P3 | Kosmetik/dokumen | Typo di label |

## Tracker

| ID | Prio | Area | Temuan singkat | Test | Branch | Status |
|---|---|---|---|---|---|---|
| | | | | | | [ ] |

## Diteruskan ke tim lain

| ID | Ke | Isi singkat | Status |
|---|---|---|---|
| | | | |
