# R7 — Protokol QA (format laporan QA Catalyst untuk Shoo)

Laporan QA kita mengikuti struktur "Laporan QA End-to-End — Catalyst": tabel header, ringkasan P0–P3 + kesimpulan, daftar temuan, detail per temuan (Langkah / Hasil / Harapan / Catatan / Bukti), blok Retest, bagian "Yang sudah berjalan baik", dan lampiran matriks uji. Template siap pakai: [`../qa/README.md`](../qa/README.md).

## 1. Ronde

| Ronde | Fase | Lingkungan | Cakupan |
|---|---|---|---|
| QA-A | 06Q | Simulator iPhone (iOS 17+), `MockRepository` (fixtures) | Semua layar Fase A, EN + ID, light/dark, Dynamic Type XL, VoiceOver, layar kecil (iPhone SE) dan besar |
| QA-E2E | 16 | 2 iPhone fisik via TestFlight (Guardian + Protected) + Worker & Supabase cloud; simulator untuk skenario tanpa push | Alur penuh: onboarding → pairing → scan → push → Detail → It's safe/Not safe → unblock; API skenario keamanan |

## 2. Prioritas

| Prio | Definisi (disesuaikan dari Catalyst) | Contoh Shoo |
|---|---|---|
| P0 | Memblokir alur inti, membocorkan data, atau memberi informasi salah | Guardian melihat scan keluarga lain; It's safe tidak membuka blokir; push tidak terkirim; crash di onboarding |
| P1 | Fitur inti salah/tidak konsisten, ada workaround | Hitung mundur kode tidak sinkron; filter Activity salah; bahasa ID tidak berlaku di satu layar |
| P2 | Kualitas data/UX yang terlihat pengguna | Teks terpotong di Dynamic Type XL; format waktu campur; empty state tanpa ilustrasi |
| P3 | Kosmetik | Spasi, ikon tidak sejajar, typo |

Kesimpulan laporan: "Siap" hanya kalau P0 = 0 dan P1 = 0. Selain itu "Belum siap sampai P0/P1 ditutup".

## 3. Bukti

- PNG di `plan/alief/qa/img/<ronde>/` dengan nama `<ID>_<slug>.png`, mis. `QA-A/P1-2_hitung_mundur.png`. Retest: `<ID>_retest.png`.
- Screenshot simulator lewat iOS Simulator tool; perangkat fisik lewat tangkapan layar iPhone lalu dipindah ke folder.
- Untuk API: potongan `curl` + respons (tanpa token; ganti dengan `<TOKEN_A>`).
- Setiap temuan menyebut lingkungan: build/commit, iOS, perangkat, bahasa.

## 4. Retest

Setelah fix di-merge, tambahkan di bawah temuan:

```text
Retest <lingkungan> · <commit/build> · <tanggal> · LULUS | SEBAGIAN | GAGAL
<apa yang dicoba ulang dan hasilnya>
Retest: <ID>_retest.png — <keterangan>
```

SEBAGIAN = sebagian harapan terpenuhi; sisa masalah ditulis jelas, dan kalau perlu dibuat temuan baru.

## 5. Matriks uji

QA-A: setiap ID layar PRD (ON-01..05, PR-04/05, GD-01/02/03/05, DT-01..06, PF-01) × {EN, ID} × {Guardian, Protected bila relevan} × {light, dark} × {Dynamic Type default, XL}.

QA-E2E minimal:

| # | Skenario | Lulus kalau |
|---|---|---|
| 1 | Onboarding Guardian + Protected | `POST /devices` 201, key App Group terisi, avatar acak |
| 2 | Pairing lewat QR | Protected melihat "You're protected by …" |
| 3 | Pairing lewat kode diketik | sama |
| 4 | Pairing lewat link WA (`https://…/join?code=`) | app terbuka dengan kode terisi |
| 5 | Kode kedaluwarsa (> 60 s) | pesan jelas + coba lagi |
| 6 | 6× kode salah | `too_many_attempts`, pesan jelas |
| 7 | Keluarga penuh (Protected ke-4) | `family_full`, pesan jelas |
| 8 | Protected buka situs warning (fixture/staging) | Guardian dapat push warning EN/ID, tap → Detail |
| 9 | Protected buka situs blocked | Guardian dapat push blocked, tap → Detail dengan screenshot |
| 10 | Guardian It's safe | layar blokir Protected terbuka ≤ 10 s, Detail "Marked safe by …" |
| 11 | Guardian Not safe | tetap diblokir, "Verified scam by …", domain masuk antrean `blocklist_entries`; setelah disetujui lewat SQL editor muncul di `/blocklist` |
| 12 | Guardian lain mencoba `GET /scans/{id}` milik keluarga lain | 404 |
| 13 | Disconnect dari kedua sisi | daftar x/3 berkurang, data lama tidak terlihat |
| 14 | Ganti bahasa ke Indonesia | semua layar + push dalam ID |
| 15a | Extension Off (HP sendiri) | Shield Protected/Guardian sendiri "Off" (dari `extension.lastSeenAt` App Group, selalu bisa diuji) |
| 15b | Extension Off (anggota keluarga) | GD-03 "Not connected" — **hanya diuji kalau C11 sudah jalan** (extension mengirim `extensionLastSeenAt`). Kalau belum: tulis di "Batasan" header laporan dengan rujukan D-alief-15/24, bukan temuan P0 |
| 16 | Retensi | scan > 14 hari (data uji dengan `created_at` mundur) hilang + objek Storage terhapus |
| 17 | ON-04 di iPhone (Guardian + Protected) | Turn on membuka Settings; setelah extension On + satu halaman dimuat, kembali ke app → lanjut ke ON-05; Off → tetap di ON-04; video tutorial bisa PiP (kalau C3 butir 4 sudah ada, kalau belum tulis di "Batasan") |

Kolom **Waktu** (detik, opsional) diisi untuk skenario yang lulus berdasarkan waktu (#10, #17) dan untuk catatan performa.
