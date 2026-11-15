# R7 — Protokol QA (format laporan QA Catalyst untuk Shoo)

Laporan QA kita mengikuti struktur "Laporan QA End-to-End — Catalyst": tabel header, ringkasan P0–P3 + kesimpulan, daftar temuan, detail per temuan (Langkah / Hasil / Harapan / Catatan / Bukti), blok Retest, bagian "Yang sudah berjalan baik", dan lampiran matriks uji. Template siap pakai: [`../qa/README.md`](../qa/README.md).

## 1. Ronde

| Ronde | Fase | Lingkungan | Cakupan |
|---|---|---|---|
| QA-A | 06Q | Simulator iPhone (iOS 17+), `MockRepository` (fixtures) | Semua layar Fase A, EN + ID, light/dark, Dynamic Type XL, VoiceOver, layar kecil (iPhone SE) dan besar |
| QA-E2E | 16 | 2 iPhone fisik via TestFlight (Guardian + Protected) + Worker & Supabase cloud; simulator untuk skenario tanpa push | Alur penuh: onboarding → pairing → scan → push → Detail → It's safe/Not safe → unblock; API skenario keamanan. Ronde ulang setelah 15 Nov 2026 juga mencakup Live Activity (EX-03), "Ingatkan", push "Perlindungan mati" |

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
| 1 | Onboarding (semua mulai sebagai Pribadi) | `POST /devices` 201 di tap pertama ON-04, key App Group terisi, avatar = pilihan ON-02 (acak hanya kalau tidak valid, #120) |
| 2 | Pairing lewat QR (`https://…/j/<code>`) | Protected melihat "You're protected by …" |
| 3 | Pairing lewat kode diketik | sama |
| 4 | Pairing lewat link WA (`https://…/j/<code>`, Universal Link #129) | app terpasang: app terbuka, sheet join dengan kode terisi; instal baru: halaman `/j/<code>` → install → buka link lagi → onboarding Pribadi → sheet join setelah onboarding (#467). Link lama `/join?code=` tidak ada lagi |
| 5 | Kode kedaluwarsa (> 30 menit, atau diganti "Refresh code") | `code_expired` / `code_invalid`, pesan jelas + coba lagi |
| 6 | 6× kode salah | `too_many_attempts`, pesan jelas |
| 7 | Keluarga penuh (Protected ke-4) | `family_full`, pesan jelas |
| 8 | Protected buka situs warning (fixture/staging) | Guardian dapat push warning EN/ID, tap → Detail |
| 9 | Protected buka situs blocked | Guardian dapat push blocked, tap → Detail dengan salinan halaman (replica). Screenshot tidak dikirim lagi sejak fase 20a (8 Nov 2026) |
| 10 | Guardian It's safe | layar blokir Protected terbuka ≤ 10 s (polling 2 s di 2 menit pertama, PR #414), Detail "Marked safe by …"; `safe` terkunci sampai review mingguan (`verdict_locked`, #476) |
| 11 | Guardian Not safe | tetap diblokir, "Verified scam by …", domain masuk antrean `blocklist_entries` (kecuali domain terlindungi `admin.domain_lists`); setelah disetujui reviewer (dashboard admin) muncul di `/blocklist` |
| 12 | Guardian lain mencoba `GET /scans/{id}` milik keluarga lain | 404 |
| 13 | Disconnect dari kedua sisi | daftar x/3 berkurang, data lama tidak terlihat, verdict Guardian itu untuk anggota terhapus (P13, `db/repo/families.ts:150-168`) |
| 14 | Ganti bahasa ke Indonesia | semua layar + push dalam ID |
| 15a | Extension Off (HP sendiri) | Shield Protected/Guardian sendiri "Off" (dari `extension.lastSeenAt` App Group, selalu bisa diuji) |
| 15b | Extension Off (anggota keluarga) | GD-03 "Not connected" — butuh extension Umar mengirim `extensionLastSeenAt` (kontrak, mandat Umar C11). Kalau extension belum mengirimnya: tulis di "Batasan" header laporan, bukan temuan P0 |
| 16 | Retensi | scan > 14 hari (data uji dengan `created_at` mundur) hilang + objek R2 (replica, favicon) dan Storage (screenshot lama) terhapus; catatan verdict hilang setelah 14 hari, keputusannya tetap |
| 17 | ON-04 di iPhone (Guardian + Protected) | Turn on membuka Settings; setelah extension On + satu halaman dimuat, kembali ke app → lanjut ke ON-05; Off → tetap di ON-04; video tutorial bisa PiP (kalau C3 butir 4 sudah ada, kalau belum tulis di "Batasan") |
| 18 | Deep link dari extension | popup "See detail" / "Review in Shoo" membuka Detail scan yang benar; tanpa id → `shoo://activity` → Activity; link rusak → Shield |
| 19 | Scan dari subdomain | scan dari `https://login.<domain>/…` tersimpan (201) dengan registrable domain. Verdict per link (origin + path, #241): `safe` hanya link itu; `not_safe` juga berlaku untuk link lain di domain itu kecuali host bersama (`verdict_shared`) |

Riwayat: skenario 4, 5, 9, 19 ditulis ulang 15 Nov 2026 (link `/j/<code>`, kode 30 menit, replica ganti screenshot, verdict per link). Kolom **Waktu** (detik, opsional) diisi untuk skenario yang lulus berdasarkan waktu (#10, #17) dan untuk catatan performa.
