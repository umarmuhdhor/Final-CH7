# Template laporan QA — Shoo (format Catalyst)

Salin blok di bawah ke `qa/QA-A-<YYYY-MM-DD>.md` atau `qa/QA-E2E-<YYYY-MM-DD>.md`. Aturan prioritas, bukti, dan retest: [`../ref/R7-protokol-qa.md`](../ref/R7-protokol-qa.md).

```markdown
# Laporan QA <A | End-to-End> — Shoo

<Lingkungan singkat> · <tanggal>

| Item | Keterangan |
| :-: | :-: |
| Build | <commit / build TestFlight> |
| Backend | <URL Worker> · Supabase <ref> · migrasi <versi> |
| Perangkat | <simulator/iPhone, iOS> |
| Metode | <simulator tool / perangkat fisik / curl>, bahasa EN + ID, <n> layar, <n> skenario |
| Batasan | <apa yang tidak diuji dan kenapa> |

# Ringkasan

| P0 | P1 | P2 | P3 | Kesimpulan |
| :-: | :-: | :-: | :-: | :-: |
| 0 | 0 | 0 | 0 | <Siap / Belum siap sampai P0/P1 ditutup> |

<2–4 paragraf: apa yang berhasil, apa yang memblokir, kenapa penting.>

# Daftar temuan

| ID | Prio | Area | Temuan |
| :-: | :-: | :-: | :-: |
| P0-1 | P0 | <Detail / Pairing / API …> | <satu kalimat> |

P0 = memblokir alur inti, membocorkan data, atau informasi salah · P1 = fitur inti salah/tidak konsisten, ada workaround · P2 = kualitas/UX yang terlihat · P3 = kosmetik

# Detail temuan

## P0-1 · <judul>

P0 · <Area>

Langkah: 1) … 2) … 3) …

Hasil: …

Harapan: … (kutip "Selesai kalau" PRD bila relevan)

Catatan: <dugaan penyebab, request/response, ID PRD>

Bukti: QA-<ronde>/P0-1_<slug>.png — <keterangan>

<!-- Setelah fix: -->
Retest <lingkungan> · <commit/build> · <tanggal> · LULUS | SEBAGIAN | GAGAL

<apa yang diuji ulang dan hasilnya>

Retest: QA-<ronde>/P0-1_retest.png — <keterangan>

# Yang sudah berjalan baik

| Area | Hasil |
| :-: | :-: |
| <Onboarding> | <…> |

# Lampiran — matriks uji

| # | Skenario / layar | Mode | Bahasa | Waktu (s) | Hasil |
| :-: | :-: | :-: | :-: | :-: | :-: |
| 1 | ON-01 splash | – | EN | – | ✓ |

✓ lulus · △ lulus sebagian · ✗ gagal.
```
