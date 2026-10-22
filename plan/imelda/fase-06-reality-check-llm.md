# Fase 06 — Layer 4: reality check LLM (M4)

| Field | Nilai |
|---|---|
| Branch | `feat/AI-M4-reality-check` |
| Prasyarat | Fase 02 dan 04 (butuh eval). Model + key (TODO A2, B1) |
| Requirement | M4: prompt, JSON terstruktur → `unreasonable_request`, model via `.env`, batas waktu |
| Review | `ecc:security-reviewer` wajib (key, prompt injection dari isi halaman) |
| Fase berikutnya | 07 |

## Tujuan

Menilai apakah data yang diminta halaman wajar untuk jenis halamannya (toko minta alamat = wajar; halaman "cek hadiah" minta PIN = tidak wajar). Satu-satunya layer yang butuh model AI.

## Bacaan wajib

- PRD §5 (layer 4), `contracts/api.md`, `contracts/detector-interface.md`
- `ai/eval/` (hasil fase 04), `ai/CLAUDE.md`

## Langkah kerja

1. **LANGKAH MANUAL:** pilih model setelah baca hasil eval (TODO A2) dan taruh key di `ai/.env`.
2. Prompt di `ai/prompts/`. Input: jenis halaman + data yang diminta (bukan seluruh halaman). Output JSON terstruktur; validasi dengan skema, tolak keluaran bebas.
3. Anggap isi halaman tidak tepercaya (prompt injection): isi halaman hanya sebagai data, tidak pernah sebagai instruksi; test dengan halaman yang berisi "abaikan instruksi sebelumnya".
4. Peta ke `unreasonable_request` (layer 4, label EN + ID, `evidence` = teks persis dari halaman).
5. Model diganti lewat `.env`. Batas waktu: bila total mendekati 8 detik, kembalikan sinyal layer 3 saja. LLM mati/error → layer 3 tetap menjawab.
6. Jalankan eval dengan dan tanpa layer 4; tulis tabel.

## Verifikasi

```bash
node --test ai/
node ai/eval/run.mjs --analyze-url http://localhost:8787   # dengan dan tanpa LLM
```

## Kriteria selesai (DoD)

- [ ] Output LLM tervalidasi skema; keluaran rusak → diabaikan, bukan error.
- [ ] Timeout dan LLM down → respons layer 3 (test).
- [ ] Eval: layer 4 mengurangi salah blokir di halaman resmi tanpa menurunkan deteksi scam (tabel di PR).
- [ ] Key hanya di `.env`; `.env.example` di-commit; prompt injection teruji.
