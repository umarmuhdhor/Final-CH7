# Serah terima: mandat Team AI (Imelda)

> Dari: Umar (@umarmuhdhor) · Untuk: Imelda (@imeldamayanti)
> Keadaan per 24 Okt 2026, `main` @ `c1bea24`

Sejak 23 Okt 2026 mandatmu ([`docs/mandates/imelda.md`](../../docs/mandates/imelda.md)) aku kerjakan. Dokumen ini merangkum apa yang sudah jalan, keputusan yang aku ambil atas namamu, dan apa yang masih terbuka. Folder `detector/` dan `ai/` masih tercatat atas namaku di `CLAUDE.md` sampai kita sepakat lain.

## 1. Ringkasan status

| Tugas | Status | Inti |
|---|---|---|
| M1 Layer 2: cek nama link | ✅ | `brands.json`, `cheap_tld`, `brand_plus_keyword`, `lookalike_domain` |
| M2 Eval set | 🟡 | 50 scam + 53 legit, tapi scam **nyata** cuma 1; sisanya sintetis |
| M3 Layer 3: isi & form | ✅ | `POST /analyze`, sinyal `asks_*`, `urgent_language`, `brand_logo_offsite`, `new_domain` (RDAP di server) |
| M4 Layer 4: LLM | ✅ | Live di produksi; detail di §2 |
| M5 Layer 1: database | ✅ | `/public-blocklist` dari Phishing.Database lewat Workers KV. Live sejak 24 Okt 2026: 190.000 domain, dibangun ulang otomatis tiap 6 jam oleh GitHub Action `public-blocklist` |
| M6 Kalibrasi | 🟡 | Salah blokir aman, deteksi scam belum capai target (§3) |
| M7 Deploy | ✅ | `https://shoo-ai.uumaarrrrr22.workers.dev`, rate limit per IP di kedua endpoint |

Test di `main`: `ai/` 302/302, `detector/` 38/38.

## 2. Keputusan yang aku ambil

Semua tercatat di [`plan/imelda/log/DECISIONS.md`](../imelda/log/DECISIONS.md).

| ID | Keputusan |
|---|---|
| D-imelda-05 | Gerbang LLM **berlaku**. LLM hanya dipanggil kalau halaman punya form ≥ 1 field **dan** skor sementara ≥ 15. Situs resmi tidak pernah memanggil (`GATE_MIN_SCORE = 15` di `ai/src/layer4/reality.js`) |
| D-imelda-36 | Penyedia LLM: `https://bandelbanget.xyz/v1`, model `deepseek-v4-flash` (bisa diganti lewat `LLM_MODEL`). ⚠️ Penyedia ini **tidak punya kebijakan zero data retention yang bisa diverifikasi**. Risiko diterima lead; pembatas data D-imelda-27 tetap berlaku. Kebijakan privasi + label App Store ada di issue #97 (Alief) |
| D-imelda-37 | Hasil eval layer 4: deteksi naik, salah blokir tidak bertambah (§3) |
| D-imelda-38 | Sumber blocklist publik: Phishing.Database `phishing-domains-ACTIVE.txt` (lisensi MIT). Dibangun **di luar Worker** oleh GitHub Action tiap 6 jam, disimpan di Workers KV; Worker hanya mengalirkan JSON tersimpan, supaya muat di batas CPU 10 ms. Server menyimpan maks. 190.000 domain (extension 200.000, sisa ruang untuk delta). Build ditolak kalau domain baru > 25% atau daftar menyusut > 50% |
| D-imelda-39 | Waktu layer 4 dihitung dari deadline: `/analyze` harus menjawab ≤ 6,5 s sejak request masuk; layer 4 dapat sisa waktunya, maks. 6 s (sebelumnya tetap 4 s). Timeout turun dari 47% ke 29% |

## 3. Angka eval

Set eval: 50 scam + 53 legit, dev server lokal, `deepseek-v4-flash`.

| Metrik | Target MVP | Tanpa layer 4 | Dengan layer 4 |
|---|---|---|---|
| Scam skor ≥ 50 | ≥ 90% | 31/50 (62%) | 38/50 (76%) |
| Scam skor ≥ 80 | ≥ 70% | 13/50 (26%) | 21/50 (42%) |
| Legit ditandai (≥ 30) | 0 | 1/53 | 1/53 (`trap-fintech-kyc-sah`, dari layer 3) |
| Sinyal layer 4 di legit | — | — | 0/53 |

Catatan:
- Layer 4 hanya bisa **menambah** skor (D-imelda-06), jadi tidak bisa mengurangi salah blokir. M4 dinilai lulus untuk "tidak menambah salah blokir, tidak menurunkan deteksi".
- Target deteksi belum tercapai, dan belum bisa dinilai jujur karena 49 dari 50 sampel scam masih sintetis. Kalibrasi M6 perlu diulang begitu ada data scam nyata.

## 4. Yang masih terbuka

| # | Isi | Langkah berikutnya |
|---|---|---|
| A4 / D1 | Sumber scam nyata berlisensi untuk M2 | Cari sumber dengan lisensi yang boleh dipakai, atau izin tertulis. OpenPhish, PhishTank, dan URLhaus sudah ditolak karena lisensi (D-imelda-19). Jangan membuka URL scam di browser; hanya lewat `ai/eval/tools/capture.mjs` |
| M6 | Kalibrasi ulang bobot | Setelah A4 ada: jalankan eval, atur bobot, tempel tabel sebelum/sesudah di PR |
| C6 | Review bobot awal layer 3–4 sebelum ambang 30/50/80 diubah | Bisa sekalian dengan M6 |
| C8 | Tambah `accept` ke `PageSnapshot.forms[].fields` untuk `asks_selfie_ktp` | Perubahan kontrak; buka issue ke lead kalau masih perlu |
| C11 | Cache RDAP di KV | Rate limit sudah jalan. `createKvCache` sudah ada dan dites di `ai/src/rdap/cache.js`, tapi belum dipasang di `ai/src/index.js` (cache masih in-memory per isolate). Perlu binding KV baru di `wrangler.toml` |
| D3 | Uji di iPhone/Safari sungguhan | Menunggu build TestFlight (#55) |
| E1 | Gambar hasil eval (PNG) | Opsional |

## 5. Cara menjalankan

```bash
cd ai && npm ci && npm test
```

```bash
cd detector && node --test
```

Eval (dua terminal):

```bash
cd ai && npm run dev
```

```bash
node ai/eval/run.mjs --analyze-url http://localhost:8787
```

- `npm run dev` tidak memanggil RDAP, jadi domain scam tidak terkirim ke registry. Layer 4 butuh `LLM_*` di `ai/.env` (gitignored).
- **Semua secret aku yang atur:** `ai/.env`, secret Worker (`LLM_*`), dan secret GitHub Actions untuk blocklist. Jangan buat, ganti, atau minta key sendiri; kalau butuh, bilang ke aku dan aku yang pasang.
- Setelah mengubah `detector/src/`, jalankan `detector/scripts/sync-to-extension.sh` dan commit `src/` + `ios/ShooExtension/Resources/detector.js` bersamaan.
- Deploy (`npm run deploy`) hanya oleh aku, karena akun Cloudflare atas namaku.

## 6. Bacaan penting

- [`docs/mandates/imelda.md`](../../docs/mandates/imelda.md): mandat + checkbox
- [`plan/imelda/TODO.md`](../imelda/TODO.md): keputusan, akun, pesan ke tim
- [`plan/imelda/log/DECISIONS.md`](../imelda/log/DECISIONS.md): semua keputusan D-imelda-NN
- [`ai/README.md`](../../ai/README.md): sumber blocklist, lisensi, setup KV, layer 4
- [`docs/design/blocklist.md`](../../docs/design/blocklist.md): desain layer 1

Pertanyaan atau usulan: buka GitHub issue dengan template **Question / proposal**, assign ke @umarmuhdhor (CLAUDE.md aturan 7).
