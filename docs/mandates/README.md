# Ringkasan mandat

Detail lengkap + checkbox progres: [umar.md](umar.md) · [imelda.md](imelda.md) · [alief.md](alief.md). Kalau ada perbedaan, yang berlaku file detail.

## Umar — Lead (`contracts/`, `ios/ShooExtension/`, `ios/ShooLiveActivity/`, `ios/ShooShared/`, `ios/project.yml`)

| # | PRD ID | Tugas | Selesai kalau |
|---|---|---|---|
| L0 | — | Override signing per developer | Tim bisa build ke iPhone sendiri tanpa ubah `project.yml` |
| S3 | EX-03 | Spike Dynamic Island | Jalur dipilih (Live Activity / pill in-page) |
| U1 | EX-02 | Pipeline scan | Skor naik per layer, reset per URL |
| U2 | EX-04 | Popup warning 30 / 50 | Sekali per halaman, tidak muncul kalau langsung ≥80 |
| U3 | EX-05 | Highlight + coret form | Protected tidak bisa hapus, Guardian bisa tutup |
| U4 | EX-06 | Layar blokir | Tidak bisa di-bypass, auto-buka kalau Safe |
| U5 | EX-07 | Kirim hasil | Skor ≥30 → `POST /scans` + screenshot bukti |
| U6 | EX-03 | Indikator live | Sesuai hasil S3 |
| U7 | EX-01 | Izin semua situs | Izin dicabut → app Off |

## Imelda — Team AI (`detector/`, `ai/`)

| # | Tugas | Isi singkat | Selesai kalau | Bergantung pada |
|---|---|---|---|---|
| M1 | Layer 2: cek link | Daftar brand resmi, TLD murah, brand + kata tambahan, ejaan mirip; M1b: pembedah seluruh URL + hosting gratis (`suspicious_link`) | Test lolos, domain resmi tanpa sinyal | — |
| M2 | Eval set | ≥ 50 halaman scam + ≥ 50 halaman resmi, skrip eval | Satu perintah, hasilnya ditempel di PR | — |
| M3 | Layer 3: isi & form | `POST /analyze`, form PIN/OTP/kartu/KTP, kalimat mendesak, logo palsu, umur domain | Fixture `blocked-92` & `warning-63` bisa direproduksi (skor ±10) | M2 |
| M4 | Layer 4: reality check (LLM) | Prompt "wajar atau tidak", output JSON, batas 8 detik | Salah blokir turun, deteksi scam tidak turun | M2, M3 |
| M5 | Layer 1: database | `GET /public-blocklist` di `ai/` + detector pakai `ShooLists.match` ([desain](../design/blocklist.md)). Unduh/simpan daftar = extension, bukan Imelda | Domain cocok → langsung 100% | — (`ShooLists` sudah ada di `main`) |
| M6 | Kalibrasi bobot | Atur bobot sinyal | Situs resmi < 30%, ≥ 90% scam ≥ 50% | M1–M5 |
| M7 | Deploy `/analyze` + `/public-blocklist` | URL HTTPS publik + rate limit per IP | URL dikirim ke Umar & Alief | M3, M4, M5 |

Semua teks alasan wajib 2 bahasa: `{ "en": "...", "id": "..." }`.
Bukan tugas Imelda: hoaks (Fase 2), AI belajar dari keputusan keluarga (menunggu PM), UI.

## Alief — Team App + Backend (`ios/ShooApp/`, `backend/`)

### Spike · di iPhone sendiri (minggu 1)
| # | PRD ID | Tugas | Selesai kalau |
|---|---|---|---|
| S1 | ON-04, PR-04, GD-01 | Deteksi extension On/Off | `docs/spikes/extension-status.md` terisi + usulan window Active ke Umar |
| S2 | ON-04 | Buka pengaturan extension | `docs/spikes/open-extension-settings.md` terisi |

### Fase A · UI dengan data palsu (fixtures)
| # | PRD ID | Tugas | Selesai kalau |
|---|---|---|---|
| A1 | — | Fondasi: tab Shield/Activity, `MockRepository`, String Catalog EN + ID | App jalan dengan data fixtures |
| A2 | ON-01 | Splash 3 slide + Skip | Sesuai PRD 8.1 |
| A3 | ON-02 | Isi nama + avatar acak | 1–20 karakter, avatar bukan inisial |
| A4 | ON-03 | Pilih mode Guardian / Protected | Permanen setelah dipilih |
| A4b | ON-04 | Turn on extension | Fallback PRD §10 dulu, disempurnakan dari S1 + S2 |
| A5 | ON-05 | Izin notifikasi | Ditolak → pengingat di Home |
| A6 | DT-01 s.d. 06 | Layar Detail | Ring skor, bukti 1–3, tombol hanya untuk Guardian |
| A7 | PR-04, PR-05 | Shield + Activity (Protected) | Card blokir terakhir, filter All/Warning/Blocked |
| A8 | GD-01, 02, 03, 05 | Shield, Family mode, Activity (Guardian) | Maks. 3 orang, filter per nama |
| A9 | PF-01 | Profile | Nama, avatar, bahasa, status extension |

### Fase B · Backend
| # | Tugas | Isi singkat | Dibutuhkan oleh |
|---|---|---|---|
| B1 | Devices | Daftar perangkat + token (tanpa login) | Semua |
| B2 | Family | Kode 4 digit (60 detik), join, hapus anggota, maks. 3 orang | GD-04, PR-01 |
| B3 | Scans | Simpan + ambil riwayat (skor ≥ 30) + screenshot | Activity, extension |
| B4 | Verdicts | Safe / Not safe per domain | GD-07, layar blokir |
| B5 | Blocklist | Daftar domain Not safe | **Imelda M5, kerjakan lebih awal** |
| B6 | Push | Notifikasi ke Guardian | GD-06 |
| B7 | Retensi & keamanan | Hapus otomatis 14 hari, batas percobaan kode | PRD §10 |

### Fase C · Sambungkan app ke backend
| # | PRD ID | Tugas |
|---|---|---|
| C1 | — | `ApiRepository` menggantikan data palsu + tulis sesi ke App Group |
| C2 | GD-04 | Family code: QR + hitung mundur + link undangan |
| C3 | PR-01, PR-02, PR-03 | Connect lewat QR / kode / link WA |
| C4 | GD-06 | Tap push → buka Detail |
| C5 | GD-07 | Tombol It's safe / Not safe |

**Ditahan:** Live Activity lewat push (kalau spike S3 Umar memutuskan begitu).
Bukan tugas Alief: popup & layar blokir di Safari (Umar), skor & teks alasan (Imelda), hoaks (Fase 2).
